# coding: utf-8
"""受限只读查询语言：把管理端输入的 WHERE / ORDER BY 文本编译成 SQLAlchemy 表达式。

安全模型（任何一条都不能放宽）：

1. **不用字符串拼 SQL**。条件文本只解析成 AST，再由 :func:`build_where` /
   :func:`build_order_by` 映射成 SQLAlchemy 表达式对象；所有字面量都走 SQLAlchemy
   绑定参数，永远不会被当成 SQL 片段执行。
2. **列名必须命中白名单**。列标识符只允许 ``[A-Za-z_][A-Za-z0-9_]*``，且必须存在
   于调用方传入的反射列集合；不允许 ``表.列``、引号标识符或子查询。
3. **文法是最小白名单**。只有 ``= != <> < <= > >=``、``LIKE/ILIKE``、``IN``、
   ``BETWEEN``、``IS [NOT] NULL``、``AND / OR / NOT`` 与括号；没有函数调用、
   ``UNION``、``CASE``、注释和分号。
4. **词法层直接拒绝危险字符**：``;``、反引号、双引号、``$``、反斜杠、NUL 与控制
   字符一律报错，不做“清洗后继续执行”。
5. **资源上限**：文本长度、token 数、括号深度、``IN`` 元素个数与 ``ORDER BY`` 项数
   都有上限，避免用超长条件消耗数据库与 CPU。

本模块不访问数据库、不读取配置、不打日志，因此可以被单元测试完整覆盖。
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Union

from sqlalchemy import and_, asc, desc, not_, or_

# 文本与解析深度上限：与 DTO 的 max_length 呼应，这里再防御一次。
MAX_CLAUSE_LENGTH = 512
MAX_TOKENS = 512
MAX_DEPTH = 8
MAX_IN_VALUES = 200
MAX_ORDER_TERMS = 5
MAX_IDENTIFIER_LENGTH = 64
MAX_STRING_LITERAL_LENGTH = 200

_IDENTIFIER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUMBER_RE = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)")
_TWO_CHAR_OPERATORS = ("<=", ">=", "<>", "!=")
_SINGLE_CHAR_OPERATORS = ("=", "<", ">")
# 这些字符在任何位置都不允许出现：分号、标识符引号、变量占位符、转义符。
_FORBIDDEN_CHARS = frozenset({";", "`", '"', "$", "\\"})

# 文法关键字：参与条件语法自身。
_KEYWORD_WORDS = frozenset(
    {
        "AND",
        "OR",
        "NOT",
        "LIKE",
        "ILIKE",
        "IN",
        "IS",
        "BETWEEN",
        "NULL",
        "TRUE",
        "FALSE",
        "ASC",
        "DESC",
    }
)

# 额外禁词：即使出现在“列名”位置也直接拒绝，避免把 DDL/DML 塞进条件。
_RESERVED_WORDS = _KEYWORD_WORDS | frozenset(
    {
        "SELECT",
        "INSERT",
        "UPDATE",
        "DELETE",
        "DROP",
        "ALTER",
        "CREATE",
        "TRUNCATE",
        "UNION",
        "EXCEPT",
        "INTERSECT",
        "JOIN",
        "FROM",
        "WHERE",
        "ORDER",
        "GROUP",
        "BY",
        "HAVING",
        "LIMIT",
        "OFFSET",
        "CASE",
        "WHEN",
        "THEN",
        "ELSE",
        "END",
        "CAST",
        "EXEC",
        "EXECUTE",
        "CALL",
        "GRANT",
        "REVOKE",
        "COPY",
        "PRAGMA",
        "ATTACH",
        "DETACH",
        "VACUUM",
        "INTO",
        "OUTFILE",
        "DUMPFILE",
        "PROCEDURE",
        "DECLARE",
        "SET",
        "VALUES",
        "RETURNING",
        "WITH",
        "USING",
        "ON",
        "AS",
        "DISTINCT",
        "COLLATE",
        "SIMILAR",
        "NULLS",
        "FIRST",
        "LAST",
    }
)


class QueryLanguageError(Exception):
    """条件文本不合法；调用方负责转成对应业务错误码。"""


class QuerySyntaxError(QueryLanguageError):
    """文法或词法不合法。"""


class UnknownColumnError(QueryLanguageError):
    """条件里使用了不在当前表列清单中的列。"""

    def __init__(self, column: str) -> None:
        super().__init__(f"unknown column: {column}")
        self.column = column


# ---- AST ------------------------------------------------------------------


@dataclass(frozen=True)
class Comparison:
    column: str
    operator: str
    value: Any


@dataclass(frozen=True)
class Like:
    column: str
    pattern: str
    case_insensitive: bool
    negated: bool


@dataclass(frozen=True)
class IsNull:
    column: str
    negated: bool


@dataclass(frozen=True)
class InList:
    column: str
    values: tuple[Any, ...]
    negated: bool


@dataclass(frozen=True)
class Between:
    column: str
    low: Any
    high: Any
    negated: bool


@dataclass(frozen=True)
class And:
    children: tuple["WhereNode", ...]


@dataclass(frozen=True)
class Or:
    children: tuple["WhereNode", ...]


@dataclass(frozen=True)
class Not:
    child: "WhereNode"


WhereNode = Union[And, Or, Not, Comparison, Like, IsNull, InList, Between]


@dataclass(frozen=True)
class OrderTerm:
    column: str
    descending: bool = False


# ---- 词法 -----------------------------------------------------------------


@dataclass(frozen=True)
class _Token:
    """kind: ``word`` / ``number`` / ``string`` / ``operator`` / 标点本身。"""

    kind: str
    value: Any


def _reject_char(char: str) -> None:
    """字符级黑名单：命中即失败，不做“剔除后继续”。"""
    if char in _FORBIDDEN_CHARS or ord(char) < 0x20 or ord(char) == 0x7F:
        raise QuerySyntaxError("条件中包含不允许的字符")


def _read_string(text: str, start: int) -> tuple[str, int]:
    """读取单引号字符串；只支持 SQL 标准的 ``''`` 转义。"""
    index = start + 1
    length = len(text)
    chunks: list[str] = []
    while index < length:
        char = text[index]
        if char == "'":
            if index + 1 < length and text[index + 1] == "'":
                chunks.append("'")
                index += 2
                continue
            return "".join(chunks), index + 1
        _reject_char(char)
        chunks.append(char)
        if len(chunks) > MAX_STRING_LITERAL_LENGTH:
            raise QuerySyntaxError("字符串字面量过长")
        index += 1
    raise QuerySyntaxError("字符串字面量缺少结束引号")


def _read_operator(text: str, start: int) -> tuple[str, int]:
    two_chars = text[start : start + 2]
    if two_chars in _TWO_CHAR_OPERATORS:
        return two_chars, start + 2
    char = text[start]
    if char in _SINGLE_CHAR_OPERATORS:
        return char, start + 1
    raise QuerySyntaxError("不支持的操作符")


def _allows_signed_number(tokens: list[_Token]) -> bool:
    """判断当前位置的 ``+`` / ``-`` 是否可能是带符号字面量。

    只允许出现在表达式开头、运算符之后、``(`` / ``,`` 之后，或 BETWEEN / AND /
    OR / NOT 等文法关键字之后；其余位置一律视为算术运算并拒绝。
    这样 ``BETWEEN -10 AND -1`` 可用，而 ``col-1``、``id > 1 + 2`` 被拒绝。
    """
    if not tokens:
        return True
    previous = tokens[-1]
    if previous.kind in ("operator", "(", ","):
        return True
    if previous.kind == "word":
        return str(previous.value).upper() in _KEYWORD_WORDS
    return False


def _tokenize(text: str) -> list[_Token]:
    """把条件文本切成 token；任何不认识的字符都直接报错。"""
    tokens: list[_Token] = []
    index = 0
    length = len(text)
    while index < length:
        char = text[index]
        if char in " \t\r\n":
            index += 1
            continue
        _reject_char(char)
        if char == "'":
            value, index = _read_string(text, index)
            tokens.append(_Token("string", value))
        elif char in "(),":
            tokens.append(_Token(char, char))
            index += 1
        elif char in "=<>!":
            operator, index = _read_operator(text, index)
            tokens.append(_Token("operator", operator))
        else:
            number_match = _NUMBER_RE.match(text, index)
            identifier_match = _IDENTIFIER_RE.match(text, index)
            if number_match is not None:
                literal = number_match.group(0)
                if literal[0] in "+-" and not _allows_signed_number(tokens):
                    raise QuerySyntaxError("条件中不支持算术运算")
                tokens.append(_Token("number", _parse_number(literal)))
                index = number_match.end()
            elif identifier_match is not None:
                tokens.append(_Token("word", identifier_match.group(0)))
                index = identifier_match.end()
            else:
                raise QuerySyntaxError("条件中包含无法识别的字符")
        if len(tokens) > MAX_TOKENS:
            raise QuerySyntaxError("条件过于复杂")
    if not tokens:
        raise QuerySyntaxError("条件不能为空")
    return tokens


def _parse_number(literal: str) -> Any:
    if "." in literal:
        return float(literal)
    return int(literal)


# ---- 语法 -----------------------------------------------------------------

_COMPARISON_OPERATORS = frozenset({"=", "!=", "<>", "<", "<=", ">", ">="})
_NEGATABLE_WORDS = ("LIKE", "ILIKE", "IN", "BETWEEN")


class _Parser:
    """递归下降解析器：文法固定，任何越界输入都抛 QuerySyntaxError。"""

    def __init__(self, tokens: list[_Token]) -> None:
        self._tokens = tokens
        self._position = 0
        self._depth = 0

    # -- 基础操作 --

    def _peek(self) -> _Token | None:
        if self._position < len(self._tokens):
            return self._tokens[self._position]
        return None

    def _advance(self) -> _Token:
        token = self._peek()
        if token is None:
            raise QuerySyntaxError("条件意外结束")
        self._position += 1
        return token

    def _accept_kind(self, kind: str) -> bool:
        token = self._peek()
        if token is not None and token.kind == kind:
            self._position += 1
            return True
        return False

    def _expect_kind(self, kind: str) -> None:
        if not self._accept_kind(kind):
            raise QuerySyntaxError(f"缺少 {kind}")

    def _is_word(self, word: str) -> bool:
        token = self._peek()
        return (
            token is not None
            and token.kind == "word"
            and token.value.upper() == word
        )

    def _accept_word(self, word: str) -> bool:
        if self._is_word(word):
            self._position += 1
            return True
        return False

    def _expect_word(self, word: str) -> None:
        if not self._accept_word(word):
            raise QuerySyntaxError(f"缺少 {word}")

    def _enter(self) -> None:
        self._depth += 1
        if self._depth > MAX_DEPTH:
            raise QuerySyntaxError("条件嵌套过深")

    def _leave(self) -> None:
        self._depth -= 1

    # -- 入口 --

    def parse(self) -> WhereNode:
        node = self._or_expression()
        if self._position != len(self._tokens):
            raise QuerySyntaxError("条件在预期位置之后还有多余内容")
        return node

    # -- 布尔结构 --

    def _or_expression(self) -> WhereNode:
        self._enter()
        try:
            parts = [self._and_expression()]
            while self._accept_word("OR"):
                parts.append(self._and_expression())
        finally:
            self._leave()
        if len(parts) == 1:
            return parts[0]
        return Or(tuple(parts))

    def _and_expression(self) -> WhereNode:
        parts = [self._negation()]
        while self._accept_word("AND"):
            parts.append(self._negation())
        if len(parts) == 1:
            return parts[0]
        return And(tuple(parts))

    def _negation(self) -> WhereNode:
        if self._accept_word("NOT"):
            return Not(self._negation())
        if self._accept_kind("("):
            self._enter()
            try:
                node = self._or_expression()
            finally:
                self._leave()
            self._expect_kind(")")
            return node
        return self._predicate()

    # -- 谓词 --

    def _predicate(self) -> WhereNode:
        column = self._column()
        if self._accept_word("IS"):
            negated = self._accept_word("NOT")
            self._expect_word("NULL")
            return IsNull(column=column, negated=negated)
        negated = False
        if self._is_word("NOT"):
            # 这里只前进一格（越过 NOT），不消费后面的谓词关键字：
            # LIKE / ILIKE / IN / BETWEEN 仍由下面的分支负责消费。
            # 早期实现用“试消费”来探测谓词，会把关键字提前吞掉，导致
            # ``NOT LIKE`` / ``NOT IN`` / ``NOT BETWEEN`` 落到比较运算符分支而报错。
            self._position += 1
            if not any(self._is_word(word) for word in _NEGATABLE_WORDS):
                raise QuerySyntaxError("NOT 后只支持 LIKE / ILIKE / IN / BETWEEN")
            negated = True
        if self._accept_word("LIKE"):
            return Like(
                column=column,
                pattern=self._string_literal(),
                case_insensitive=False,
                negated=negated,
            )
        if self._accept_word("ILIKE"):
            return Like(
                column=column,
                pattern=self._string_literal(),
                case_insensitive=True,
                negated=negated,
            )
        if self._accept_word("IN"):
            return self._in_list(column, negated)
        if self._accept_word("BETWEEN"):
            low = self._literal()
            self._expect_word("AND")
            high = self._literal()
            return Between(
                column=column, low=low, high=high, negated=negated
            )
        operator = self._comparison_operator()
        return Comparison(column=column, operator=operator, value=self._literal())

    def _column(self) -> str:
        token = self._peek()
        if token is None or token.kind != "word":
            raise QuerySyntaxError("条件必须以列名开头")
        word = str(token.value)
        if word.upper() in _RESERVED_WORDS:
            raise QuerySyntaxError(f"不支持的关键字: {word}")
        if len(word) > MAX_IDENTIFIER_LENGTH or not _IDENTIFIER_RE.fullmatch(word):
            raise QuerySyntaxError("列名不合法")
        self._position += 1
        return word

    def _comparison_operator(self) -> str:
        token = self._peek()
        if token is None or token.kind != "operator":
            raise QuerySyntaxError("缺少比较运算符")
        operator = str(token.value)
        if operator not in _COMPARISON_OPERATORS:
            raise QuerySyntaxError("不支持的比较运算符")
        self._position += 1
        return operator

    def _string_literal(self) -> str:
        token = self._peek()
        if token is None or token.kind != "string":
            raise QuerySyntaxError("LIKE / ILIKE 需要一个字符串模式")
        self._position += 1
        return str(token.value)

    def _literal(self) -> Any:
        token = self._peek()
        if token is None:
            raise QuerySyntaxError("缺少取值")
        if token.kind == "number":
            self._position += 1
            return token.value
        if token.kind == "string":
            self._position += 1
            return token.value
        if token.kind == "word":
            word = str(token.value).upper()
            if word == "NULL":
                self._position += 1
                return None
            if word == "TRUE":
                self._position += 1
                return True
            if word == "FALSE":
                self._position += 1
                return False
        raise QuerySyntaxError("取值必须是数字、字符串、TRUE、FALSE 或 NULL")

    def _in_list(self, column: str, negated: bool) -> WhereNode:
        self._expect_kind("(")
        values = [self._literal()]
        while self._accept_kind(","):
            if len(values) >= MAX_IN_VALUES:
                raise QuerySyntaxError("IN 列表元素过多")
            values.append(self._literal())
        self._expect_kind(")")
        return InList(column=column, values=tuple(values), negated=negated)


# ---- 对外入口 -------------------------------------------------------------


def parse_where(text: str) -> WhereNode:
    """把 WHERE 文本解析成 AST；不合法即抛 QuerySyntaxError。"""
    clause = (text or "").strip()
    if not clause:
        raise QuerySyntaxError("条件不能为空")
    if len(clause) > MAX_CLAUSE_LENGTH:
        raise QuerySyntaxError("条件过长")
    return _Parser(_tokenize(clause)).parse()


def parse_order_by(text: str) -> tuple[OrderTerm, ...]:
    """把 ORDER BY 文本解析成 ``(列, 方向)`` 列表。"""
    clause = (text or "").strip()
    if not clause:
        raise QuerySyntaxError("排序条件不能为空")
    if len(clause) > MAX_CLAUSE_LENGTH:
        raise QuerySyntaxError("排序条件过长")
    tokens = _tokenize(clause)
    terms: list[OrderTerm] = []
    position = 0
    while position < len(tokens):
        token = tokens[position]
        if token.kind != "word":
            raise QuerySyntaxError("ORDER BY 必须以列名开头")
        word = str(token.value)
        if word.upper() in _RESERVED_WORDS:
            raise QuerySyntaxError(f"ORDER BY 不支持的关键字: {word}")
        if len(word) > MAX_IDENTIFIER_LENGTH or not _IDENTIFIER_RE.fullmatch(word):
            raise QuerySyntaxError("ORDER BY 列名不合法")
        position += 1
        descending = False
        if position < len(tokens) and tokens[position].kind == "word":
            keyword = str(tokens[position].value).upper()
            if keyword == "DESC":
                descending = True
                position += 1
            elif keyword == "ASC":
                position += 1
            else:
                raise QuerySyntaxError("ORDER BY 只接受列名与 ASC / DESC")
        terms.append(OrderTerm(column=word, descending=descending))
        if len(terms) > MAX_ORDER_TERMS:
            raise QuerySyntaxError("ORDER BY 项数过多")
        if position < len(tokens):
            if tokens[position].kind != ",":
                raise QuerySyntaxError("ORDER BY 多项之间必须用逗号分隔")
            position += 1
            if position >= len(tokens):
                raise QuerySyntaxError("ORDER BY 末尾缺少列名")
    if not terms:
        raise QuerySyntaxError("排序条件不能为空")
    return tuple(terms)


# ---- AST → SQLAlchemy 表达式 ----------------------------------------------


def _resolve_column(columns: Any, name: str) -> Any:
    """列对象只能来自反射结果；未知名直接失败，绝不回退成文本拼接。"""
    try:
        return columns[name]
    except (KeyError, IndexError) as exc:
        raise UnknownColumnError(name) from exc


def build_where(columns: Any, node: WhereNode) -> Any:
    """把 AST 映射成 SQLAlchemy 布尔表达式（字面量全部走绑定参数）。"""
    if isinstance(node, And):
        return and_(*[build_where(columns, child) for child in node.children])
    if isinstance(node, Or):
        return or_(*[build_where(columns, child) for child in node.children])
    if isinstance(node, Not):
        return not_(build_where(columns, node.child))
    column = _resolve_column(columns, node.column)
    if isinstance(node, Comparison):
        return _comparison(column, node.operator, node.value)
    if isinstance(node, Like):
        target = (
            column.ilike(node.pattern)
            if node.case_insensitive
            else column.like(node.pattern)
        )
        return not_(target) if node.negated else target
    if isinstance(node, IsNull):
        return column.is_not(None) if node.negated else column.is_(None)
    if isinstance(node, InList):
        target = column.in_(node.values)
        return not_(target) if node.negated else target
    if isinstance(node, Between):
        target = column.between(node.low, node.high)
        return not_(target) if node.negated else target
    raise QuerySyntaxError("不支持的条件节点")


def _comparison(column: Any, operator: str, value: Any) -> Any:
    """比较运算符到 Column 表达式；两边都是对象/绑定参数。"""
    if value is None:
        # SQL 三值逻辑里 ``col = NULL`` 永远不成立。这里显式映射成 IS [NOT] NULL，
        # 既符合直觉，也避免不同方言对 NULL 比较的隐式差异。
        if operator == "=":
            return column.is_(None)
        if operator in ("!=", "<>"):
            return column.is_not(None)
        raise QuerySyntaxError("NULL 只能与 = 或 != 比较")
    if operator == "=":
        return column == value
    if operator in ("!=", "<>"):
        return column != value
    if operator == "<":
        return column < value
    if operator == "<=":
        return column <= value
    if operator == ">":
        return column > value
    if operator == ">=":
        return column >= value
    raise QuerySyntaxError("不支持的比较运算符")


def build_order_by(columns: Any, terms: tuple[OrderTerm, ...]) -> list[Any]:
    """把 ORDER BY 项映射成 Column 排序表达式。"""
    ordered: list[Any] = []
    for term in terms:
        column = _resolve_column(columns, term.column)
        ordered.append(desc(column) if term.descending else asc(column))
    return ordered

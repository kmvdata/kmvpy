# coding: utf-8
"""受限查询语言的单元测试：文法白名单、注入拒绝与 AST → SQL 绑定参数。

运行方式（在 __PY_PROJECT_NAME__ 下）：

    PYTHONPATH=. python -m unittest discover -s tests -p "test_database_query_lang.py"

本模块不连接数据库：只用 SQLite 的 Table/Column 对象验证解析与表达式编译结果，
并检查编译后的语句参数是绑定值而不是拼接进 SQL 文本。
"""

import unittest

from sqlalchemy import Column, Integer, MetaData, String, Table, select
from sqlalchemy.dialects import postgresql

from __PROJECT_NAME__.common.infra.database import query_lang


def _table():
    metadata = MetaData()
    return Table(
        "work_ticket",
        metadata,
        Column("id", Integer, primary_key=True),
        Column("title", String(64)),
        Column("status", String(16)),
        Column("creator_user_kid", Integer),
    )


def _compiled_text(statement):
    """编译成 PostgreSQL 方言文本，用于断言参数已绑定。"""
    return str(
        statement.compile(
            dialect=postgresql.dialect(),
            compile_kwargs={"literal_binds": False},
        )
    )


class WhereSyntaxTest(unittest.TestCase):
    """合法文法必须能解析成 AST。"""

    def test_comparisons(self):
        for operator in ("=", "!=", "<>", "<", "<=", ">", ">="):
            node = query_lang.parse_where(f"id {operator} 10")
            self.assertIsInstance(node, query_lang.Comparison)
            assert isinstance(node, query_lang.Comparison)
            self.assertEqual(node.operator, operator)

    def test_and_or_not_and_parentheses(self):
        node = query_lang.parse_where(
            "(status = 'open' OR status = 'closed') AND NOT id < 5"
        )
        self.assertIsInstance(node, query_lang.And)
        assert isinstance(node, query_lang.And)
        self.assertIsInstance(node.children[0], query_lang.Or)
        self.assertIsInstance(node.children[1], query_lang.Not)

    def test_like_ilike_and_negation(self):
        like = query_lang.parse_where("title LIKE 'ab%'")
        self.assertIsInstance(like, query_lang.Like)
        assert isinstance(like, query_lang.Like)
        self.assertFalse(like.case_insensitive)
        self.assertFalse(like.negated)

        ilike = query_lang.parse_where("title NOT ILIKE 'ab%'")
        self.assertIsInstance(ilike, query_lang.Like)
        assert isinstance(ilike, query_lang.Like)
        self.assertTrue(ilike.case_insensitive)
        self.assertTrue(ilike.negated)

    def test_negated_in_between_and_like(self):
        """回归：NOT 只越过自身一格，不得吞掉后面的谓词关键字。"""
        not_like = query_lang.parse_where("title NOT LIKE 'ab%'")
        self.assertIsInstance(not_like, query_lang.Like)
        assert isinstance(not_like, query_lang.Like)
        self.assertFalse(not_like.case_insensitive)
        self.assertTrue(not_like.negated)

        not_in = query_lang.parse_where("status NOT IN ('open')")
        self.assertIsInstance(not_in, query_lang.InList)
        assert isinstance(not_in, query_lang.InList)
        self.assertTrue(not_in.negated)

        not_between = query_lang.parse_where("id NOT BETWEEN 1 AND 5")
        self.assertIsInstance(not_between, query_lang.Between)
        assert isinstance(not_between, query_lang.Between)
        self.assertTrue(not_between.negated)

    def test_not_followed_by_non_predicate_rejected(self):
        """NOT 后必须是可否定谓词，避免把半截条件当成合法查询。"""
        for clause in ("id NOT 5", "id NOT IS NULL", "id NOT"):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_in_between_is_null(self):
        in_node = query_lang.parse_where("status IN ('open', 'closed')")
        self.assertIsInstance(in_node, query_lang.InList)
        assert isinstance(in_node, query_lang.InList)
        self.assertEqual(in_node.values, ("open", "closed"))

        between = query_lang.parse_where("id BETWEEN -10 AND -1")
        self.assertIsInstance(between, query_lang.Between)
        assert isinstance(between, query_lang.Between)
        self.assertEqual((between.low, between.high), (-10, -1))

        is_null = query_lang.parse_where("title IS NULL")
        self.assertIsInstance(is_null, query_lang.IsNull)
        assert isinstance(is_null, query_lang.IsNull)
        self.assertFalse(is_null.negated)

        is_not_null = query_lang.parse_where("title IS NOT NULL")
        self.assertIsInstance(is_not_null, query_lang.IsNull)
        assert isinstance(is_not_null, query_lang.IsNull)
        self.assertTrue(is_not_null.negated)

    def test_boolean_and_null_literals(self):
        node = query_lang.parse_where("status = NULL")
        self.assertIsInstance(node, query_lang.Comparison)
        assert isinstance(node, query_lang.Comparison)
        self.assertIsNone(node.value)

        node = query_lang.parse_where("creator_user_kid != FALSE")
        self.assertIsInstance(node, query_lang.Comparison)
        assert isinstance(node, query_lang.Comparison)
        self.assertIs(node.value, False)

    def test_string_escape(self):
        node = query_lang.parse_where("title = 'it''s'")
        self.assertIsInstance(node, query_lang.Comparison)
        assert isinstance(node, query_lang.Comparison)
        self.assertEqual(node.value, "it's")


class WhereRejectionTest(unittest.TestCase):
    """注入与越权输入必须在解析阶段被拒绝。"""

    def test_statement_terminator_rejected(self):
        for clause in (
            "1=1; DROP TABLE user_base",
            "id = 1; SELECT 1",
            "id = 1 --",
            "id = 1 /* comment */",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_union_and_subquery_rejected(self):
        for clause in (
            "id = 1 UNION SELECT kid FROM user_base",
            "id IN (SELECT id FROM user_base)",
            "EXISTS (SELECT 1)",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_quoted_identifiers_rejected(self):
        for clause in (
            '"id" = 1',
            "`id` = 1",
            "id::text = '1'",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_qualified_and_dotted_columns_rejected(self):
        for clause in (
            "work_ticket.id = 1",
            "public.work_ticket.id = 1",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_function_call_rejected(self):
        for clause in (
            "lower(title) = 'a'",
            "pg_sleep(10) IS NULL",
            "char_length(title) > 3",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_pseudo_columns_hit_column_whitelist(self):
        """``current_user`` 这类词能通过文法，但必须在列白名单处失败。"""
        table = _table()
        node = query_lang.parse_where("current_user IS NULL")
        with self.assertRaises(query_lang.UnknownColumnError):
            query_lang.build_where(table.c, node)

    def test_parameter_placeholder_and_escape_rejected(self):
        for clause in (
            "id = $1",
            "title = 'a\\' OR 1=1 --'",
            "id = ?",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_arithmetic_rejected(self):
        for clause in ("id-1 = 0", "id > 1 + 2", "id * 2 = 4"):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_trailing_garbage_rejected(self):
        for clause in ("id = 1 id = 2", "id = 1 AND", "(id = 1", "id = "):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_empty_rejected(self):
        for clause in ("", "   ", "\t\n"):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_where(clause)

    def test_control_characters_rejected(self):
        with self.assertRaises(query_lang.QueryLanguageError):
            query_lang.parse_where("id = 1\x00")

    def test_limit_guards(self):
        too_long = "id = 1 AND " * 100
        with self.assertRaises(query_lang.QueryLanguageError):
            query_lang.parse_where(too_long)

        deep = "(" * (query_lang.MAX_DEPTH + 2) + "id = 1"
        deep += ")" * (query_lang.MAX_DEPTH + 2)
        with self.assertRaises(query_lang.QueryLanguageError):
            query_lang.parse_where(deep)

        many_values = ", ".join(["1"] * (query_lang.MAX_IN_VALUES + 5))
        with self.assertRaises(query_lang.QueryLanguageError):
            query_lang.parse_where(f"id IN ({many_values})")

        long_literal = "a" * (query_lang.MAX_STRING_LITERAL_LENGTH + 10)
        with self.assertRaises(query_lang.QueryLanguageError):
            query_lang.parse_where(f"title = '{long_literal}'")


class BuildExpressionTest(unittest.TestCase):
    """AST → SQLAlchemy 表达式：字面量必须绑定，列必须来自反射表。"""

    def test_literals_are_bound(self):
        table = _table()
        node = query_lang.parse_where("title = 'x'' OR 1=1 --'")
        expression = query_lang.build_where(table.c, node)
        statement = select(table).where(expression)
        compiled = statement.compile(dialect=postgresql.dialect())
        sql = str(compiled)
        # 危险文本只能作为绑定参数值出现，不能进入 SQL 文本本身。
        self.assertNotIn("OR 1=1", sql)
        # 占位符形态随方言 paramstyle 变化：psycopg2 用 %(name)s，asyncpg 用 $1，
        # 默认 named 才是 :name。因此按三种形态之一定位，不能写死冒号。
        self.assertRegex(sql, r"(%\(\w+\)s)|(:\w+)|(\$\d+)")
        self.assertEqual(list(compiled.params.values()), ["x' OR 1=1 --"])

    def test_unknown_column_rejected(self):
        table = _table()
        node = query_lang.parse_where("secret_column = 1")
        with self.assertRaises(query_lang.UnknownColumnError):
            query_lang.build_where(table.c, node)

    def test_null_comparison_maps_to_is_null(self):
        """``= NULL`` / ``!= NULL`` 必须映射成 IS [NOT] NULL，否则三值逻辑下永远查不到。"""
        table = _table()
        equal = query_lang.parse_where("title = NULL")
        compiled = _compiled_text(
            select(table).where(query_lang.build_where(table.c, equal))
        )
        self.assertIn("work_ticket.title IS NULL", compiled)

        not_equal = query_lang.parse_where("title != NULL")
        compiled = _compiled_text(
            select(table).where(query_lang.build_where(table.c, not_equal))
        )
        self.assertIn("work_ticket.title IS NOT NULL", compiled)

    def test_null_with_ordering_operator_rejected(self):
        """大小比较与 NULL 组合没有语义，必须在编译阶段拒绝而不是生成恒假条件。"""
        table = _table()
        for clause in ("id < NULL", "id >= NULL"):
            node = query_lang.parse_where(clause)
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.build_where(table.c, node)

    def test_in_list_bound(self):
        table = _table()
        node = query_lang.parse_where("status IN ('open', 'closed')")
        statement = select(table).where(query_lang.build_where(table.c, node))
        compiled = statement.compile(dialect=postgresql.dialect())
        sql = str(compiled)
        # IN 列表走展开参数，取值不出现在 SQL 文本里。
        self.assertIn("__[POSTCOMPILE", sql)
        self.assertNotIn("'open'", sql)


class OrderByTest(unittest.TestCase):
    """ORDER BY 解析与列白名单。"""

    def test_multiple_terms(self):
        terms = query_lang.parse_order_by("id DESC, title")
        self.assertEqual(
            terms,
            (
                query_lang.OrderTerm(column="id", descending=True),
                query_lang.OrderTerm(column="title", descending=False),
            ),
        )

    def test_rejects_sql_snippets(self):
        for clause in (
            "id; DROP TABLE user_base",
            "id DESC, (SELECT 1)",
            "id COLLATE \"C\"",
            "1",
            "id DESC,",
            "id,",
        ):
            with self.assertRaises(query_lang.QueryLanguageError):
                query_lang.parse_order_by(clause)

    def test_rejects_too_many_terms(self):
        clause = ", ".join(["id"] * (query_lang.MAX_ORDER_TERMS + 1))
        with self.assertRaises(query_lang.QueryLanguageError):
            query_lang.parse_order_by(clause)

    def test_build_order_by_uses_reflected_columns(self):
        table = _table()
        terms = query_lang.parse_order_by("id DESC")
        compiled = _compiled_text(
            select(table).order_by(*query_lang.build_order_by(table.c, terms))
        )
        self.assertIn("ORDER BY work_ticket.id DESC", compiled)

    def test_build_order_by_rejects_unknown_column(self):
        table = _table()
        terms = query_lang.parse_order_by("secret_column ASC")
        with self.assertRaises(query_lang.UnknownColumnError):
            query_lang.build_order_by(table.c, terms)


if __name__ == "__main__":
    unittest.main()
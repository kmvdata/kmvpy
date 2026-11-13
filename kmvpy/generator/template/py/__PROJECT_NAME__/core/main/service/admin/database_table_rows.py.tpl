# coding: utf-8
"""管理端数据表行数据浏览服务。

只做三件事：取得配置声明的默认连接、按固定顺序调用 Hub 与 Infra、把结果映射
成 DTO。分页收敛、条件与排序解析、列白名单校验、表存在性判定与结构组装全部在
``DatabaseTableRowsHub`` 内，本层不做任何业务分支。

本接口只读：不进入事务写入路径、不执行任何 DDL/DML，也不 import 其他 Service。
默认连接由 ``DatabaseCatalogHub.default_storage()`` 提供，它只取应用已初始化的
单例并归一错误语义，不创建也不关闭资源。

WHERE / ORDER BY 文本在进入 Infra 之前已经变成受限 AST：Infra 只把 AST 映射成
SQLAlchemy 表达式（绑定参数 + 反射列对象），不存在字符串拼接的 SQL。
"""

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger
from sqlalchemy.exc import (
    DataError,
    IntegrityError,
    ProgrammingError,
    SQLAlchemyError,
)

from __PROJECT_NAME__.common.dto.admin.database_table_rows import (
    AdminDatabaseTableRowsCellRes,
    AdminDatabaseTableRowsColumnRes,
    AdminDatabaseTableRowsReq,
    AdminDatabaseTableRowsRes,
)
from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.database import query_lang
from __PROJECT_NAME__.common.infra.database.rows import read_table_rows
from __PROJECT_NAME__.core.main.hub.database_catalog import DatabaseCatalogHub
from __PROJECT_NAME__.core.main.hub.database_table_rows import DatabaseTableRowsHub


class AdminDatabaseTableRowsService:
    """表数据浏览的入口：默认连接 → Hub 校验 → Infra 只读读取 → DTO。"""

    @staticmethod
    async def list_rows(
        req: AdminDatabaseTableRowsReq,
    ) -> AdminDatabaseTableRowsRes:
        storage = DatabaseCatalogHub.default_storage()
        page, size = DatabaseTableRowsHub.normalized_page(req.page, req.size)
        # 表名与条件都在任何数据库交互之前校验：非法输入不会产生一次查询。
        table_name = DatabaseTableRowsHub.validated_table_name(req.table_name)
        where_node = DatabaseTableRowsHub.parse_where(req.where_clause)
        order_terms = DatabaseTableRowsHub.parse_order_by_terms(
            req.order_by_clause
        )
        try:
            raw = await read_table_rows(
                storage.engine,
                table_name,
                page=page,
                size=size,
                order_by=req.order_by,
                order_desc=req.order_desc,
                where_node=where_node,
                order_terms=order_terms,
            )
            DatabaseTableRowsHub.ensure_table_exists(raw)
            # 条件和排序列都必须在反射列名单内；非法列在这里转成 46012，
            # 因此不会出现“条件被悄悄忽略”的结果。
            DatabaseTableRowsHub.ensure_clause_columns(
                DatabaseTableRowsHub.column_names(raw),
                order_terms,
            )
            DatabaseTableRowsHub.resolve_order_column(
                DatabaseTableRowsHub.column_names(raw),
                req.order_by,
            )
            data = DatabaseTableRowsHub.build_result(raw, page=page, size=size)
        except KmvException:
            raise
        except query_lang.UnknownColumnError as exc:
            # 条件里的列不在反射列名单内：明确失败，不降级成无条件查询。
            logger.warning(
                "管理端查询条件引用未知列 table=%s: %s",
                req.table_name,
                exc,
            )
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_COLUMN_UNKNOWN_ERROR
            ) from exc
        except (DataError, ProgrammingError) as exc:
            # 条件取值/运算符与列类型不匹配（例如数字列 LIKE 字符串、数字列比
            # 较非数字常量）：属于条件非法，按 46013 返回，既不暴露数据库原始
            # 报错，也不退化成 500。ProgrammingError 覆盖方言报出的
            # “operator does not exist” 一类错误。
            logger.warning(
                "管理端查询条件类型不匹配 table=%s: %s",
                table_name,
                exc,
            )
            raise KmvException(
                error=database_table_exc.QUERY_CLAUSE_SYNTAX_INVALID_ERROR
            ) from exc
        except IntegrityError as exc:
            logger.warning(
                "读取数据表行数据失败 table=%s: %s",
                table_name,
                exc,
                exc_info=exc,
            )
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_OPERATION_FAILED_ERROR
            ) from exc
        except SQLAlchemyError as exc:
            # 连接、超时等其余数据库故障：统一成可重试的业务错误。
            logger.warning(
                "读取数据表行数据失败 table=%s: %s",
                table_name,
                exc,
                exc_info=exc,
            )
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_OPERATION_FAILED_ERROR
            ) from exc

        return AdminDatabaseTableRowsRes(
            table_name=str(data["table_name"]),
            columns=[
                AdminDatabaseTableRowsColumnRes(**column)
                for column in data["columns"]
            ],
            rows=[
                [AdminDatabaseTableRowsCellRes(**cell) for cell in row]
                for row in data["rows"]
            ],
            primary_key_columns=[
                str(name) for name in data["primary_key_columns"]
            ],
            total=data["total"],
            page=int(data["page"]),
            size=int(data["size"]),
            elapsed_ms=int(data["elapsed_ms"]),
            where_clause=DatabaseTableRowsHub.normalized_clause(
                req.where_clause
            ),
            order_by_clause=DatabaseTableRowsHub.normalized_clause(
                req.order_by_clause
            ),
        )

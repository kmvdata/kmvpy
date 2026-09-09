# ORM、Storage 与数据库会话

在修改 ORM 表、字段/索引/约束、模型注册、SQLAlchemy 查询、`DefaultStorage`、Redis/storage 技术能力或数据库兼容性时读取本文件。涉及事务编排时同时读取主 Skill 直接链接的 `service-hub.md`。

## ORM 模型

- 一个文件定义一张表模型，继承 `KOrmBase`。
- 每个业务表同时提供自增主键 `id` 和全局唯一业务标识 `kid`。
- 使用显式 SQLAlchemy 类型、`nullable`、`index`、`unique`、server default 和中文 `comment`。
- 需要自增兼容时设置 `__table_args__ = {"sqlite_autoincrement": True}`。
- 从 `common/infra/orm/__init__.py` 统一导入 `BIGINT_TYPE`、`AUTO_INCREMENT_PK_TYPE`；不要重复定义共享类型。
- Boolean server default 使用 `true()`/`false()`，不要使用数据库方言相关的 `text("1")`/`text("0")`。
- 时间字段优先使用数据库默认值，并明确更新时间策略。
- 只有与单行记录强相关、不依赖外部服务的短小 helper 才放在模型上。
- 不在 ORM `__init__.py` 增加新的复杂启动/业务逻辑。

```python
class ModelName(KOrmBase):
    __tablename__ = "table_name"
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(
        AUTO_INCREMENT_PK_TYPE,
        primary_key=True,
        index=True,
        autoincrement=True,
        comment="自增主键ID",
    )
    kid = Column(
        BIGINT_TYPE,
        nullable=False,
        unique=True,
        comment="全局唯一kid",
    )
    create_time = Column(
        DateTime,
        nullable=False,
        index=True,
        server_default=func.now(),
        comment="创建时间",
    )
    update_time = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
        comment="更新时间",
    )
```

## 模型注册

新增模型后同时完成：

1. 在 `common/infra/orm/__init__.py` 导入模型。
2. 将模型加入 `_REGISTERED_ORM_MODELS`；它是项目表初始化的唯一注册数据源。
3. 验证 `registered_orm_models()` 能返回模型。
4. 验证 `registered_orm_model_by_table_name()` 能按 `__tablename__` 查到模型。
5. 检查初始化、管理端表维护和测试路径是否依赖该注册表。

## DefaultStorage

- 通过 `DefaultStorage.instance()` 获取单例。
- 让 Storage 只负责数据库/Redis 初始化、资源生命周期、通用缓存或底层能力透传。
- 不在 `DefaultStorage` 添加业务查询、业务校验或业务状态判断；这些属于 Hub。
- 跨 Hub 重复且完全无业务语义的技术行为才适合下沉 Storage/Infra。
- 保持 kmvpy 所需的 Kosmos 反向资源绑定等框架兼容行为；该兼容绑定仅服务底层资源访问，不代表项目存在平行于 Hub 的业务层。

## Session

- 只由 Service 进入 `DefaultStorage.instance().session_scope()`。
- 把同一个 `session` 显式传给事务内的一个或多个 Hub 方法。
- Hub 不创建 session，不提交或回滚；`session_scope()` 在上下文退出时完成事务提交。
- Hub 查询/写入使用传入 session，或调用显式接受该 session 的纯 Infra 能力；不得隐式开启第二个事务。
- 在 Service 外层捕获提交阶段可能出现的 `IntegrityError`。

## 跨数据库检查

- 同时考虑 SQLite、MySQL 和 PostgreSQL 的自增、Boolean 默认值、时间默认值、唯一约束和 SQL 语法。
- 不依赖 SQLite 宽松类型行为或 MySQL 专属 SQL，除非明确使用方言分支并提供其他数据库路径。
- 修改索引/约束时检查已有数据迁移与初始化行为，不假设自动同步一定无损。

## 新增 ORM 流程

1. 明确表用途和聚合归属。
2. 设计文件名、类名、`__tablename__`、字段、索引和约束。
3. 创建模型并复用共享类型。
4. 完成集中注册。
5. 在 Hub 中实现数据访问，不把查询放进 Service/Router。
6. 添加针对默认值、约束、注册和关键查询的测试。
7. 交付前读取 `verification.md`。

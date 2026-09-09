# Service、Hub 与事务边界

在修改 Service、Hub、业务判断、事务、多表聚合、多个 Hub 的组合或共享业务能力时读取本文件。

## 目录

- [职责判据](#职责判据)
- [Service 规则](#service-规则)
- [Hub 规则](#hub-规则)
- [session 调用边界](#session-调用边界)
- [事务与异常模板](#事务与异常模板)
- [常见决策](#常见决策)

## 职责判据

- 把权限、状态、存在性、额度、业务合法性、条件分支和聚合内多表变更放入 Hub。
- 把事务生命周期、无条件的调用顺序、底层异常转换和 DTO 组装放入 Service。
- 把 ORM、Redis、RPC、AI、文件存储和配置读取留在 Hub/Infra 边界内。
- 业务流程若必须根据查询结果决定下一步，把该决策封装为一个粗粒度 Hub 操作，不要在 Service 中分支。
- 多个独立 Hub 操作只需共享事务且按固定顺序执行时，由 Service 将同一个 `session` 逐一传入。

## Service 规则

- 使用无状态 `XxxService` 类和 `@staticmethod`。
- Service 之间不得互相调用；共享业务能力下沉 Hub。`service/common` 也不是 Service-to-Service 的例外。
- Service 不直接导入或操作 ORM，不调用 Storage 查询/cache helper，不访问 Redis/RPC/AI，不读取 Config。
- 唯一允许的 Infra 接触点是 `DefaultStorage.instance().session_scope()`，仅用于定义事务生命周期。
- Service 可捕获明确的底层异常并转换为统一 `KmvException`，不要把未知异常宽泛吞掉。
- Service 只返回 DTO 或稳定结构，绝不把 ORM 实例暴露给 Router。
- Service 不做业务 `if`/`match`/条件循环。用于上下文管理、明确异常处理和无业务语义的响应格式转换不算业务判断。
- 若某个 Service 方法无需数据库，可直接调用不含 `session` 的 Hub 方法并组装 DTO。

## Hub 规则

- 按业务主题组织 Hub，不按 user/admin 入口拆分；两端复用同一业务能力。
- 使用无状态 `XxxHub`/`XxxQueryHub` 类和 `@staticmethod`；状态全部通过参数传入。
- Hub 不依赖 FastAPI、Pydantic DTO、Router 或 Service。
- Hub 可以依赖 ORM、Storage/Redis 等 Infra、Config 和 `common.exception`。
- Hub 可以提供两种入口：
  - 粗粒度聚合操作：一次完成一个原子业务操作及其规则判断、多表写入和流水。
  - 可复用基础单元：纯校验、规范化、计算、查询或简单写入。
- 需要数据库访问的方法必须显式接受由 Service 传入的 `session`。
- Hub 不创建 session，不调用 `commit()`/`rollback()`；只有确需数据库生成值或提前触发约束时才调用 `flush()`。
- Hub 可返回 ORM 给 Service 做 DTO 映射，但不能让 ORM 穿过 Service 边界。
- Hub 不定义错误三元组，只引用 `common.exception` 中的常量/builder。

## session 调用边界

把 `session` 参数视为 Hub 之间的硬隔离线：

1. 任一签名含 `session` 的 Hub 方法，不得调用任何其他签名含 `session` 的 Hub 方法，包括当前类的私有/公开方法和其他 Hub。
2. 含 `session` 的 Hub 方法可以调用不含 `session` 的纯校验、规范化或计算方法。
3. 不含 `session` 的 Hub 方法不得自行创建 session 后转调含 `session` 的 Hub 方法。
4. 一个含 `session` 的粗粒度方法需要多表操作时，在当前方法内直接使用该 `session` 访问相关 ORM/Infra。
5. 需要串联多个含 `session` 的 Hub 方法时，只能由 Service 创建一个事务并逐一调用。

这组约束保证事务只在 Service 定义，并降低 Hub-to-Hub 交叉引用。

## 事务与异常模板

`KOrmStorage.session_scope()` 使用 `session.begin()`，提交发生在上下文退出阶段。把 `try` 放在整个 `async with` 外，才能捕获 flush 与 commit 阶段的 `IntegrityError`。

```python
class EntityService:
    @staticmethod
    async def update(req: EntityUpdateReq) -> EntityRes:
        db = DefaultStorage.instance()
        try:
            async with db.session_scope() as session:
                entity = await EntityHub.execute_update(
                    session,
                    kid=req.kid,
                    value=req.value,
                )
                response = EntityRes(
                    kid=str(entity.kid),
                    value=entity.value,
                )
            return response
        except IntegrityError as exc:
            raise KmvException(error=system_exc.DB_INTEGRITY_ERROR) from exc
```

固定顺序组合多个 Hub 时保持 Service 无业务分支：

```python
try:
    async with db.session_scope() as session:
        first = await FirstHub.execute_create(session, ...)
        second = await SecondHub.execute_attach(session, first_kid=first.kid, ...)
        response = CombinedRes(first_kid=str(first.kid), second_kid=str(second.kid))
    return response
except IntegrityError as exc:
    raise KmvException(error=system_exc.DB_INTEGRITY_ERROR) from exc
```

## 常见决策

| 情况 | 放置位置 |
|---|---|
| 邮箱规范化、状态校验、权限判断 | 不含 `session` 的 Hub 方法 |
| 查询不存在则创建 | 单个含 `session` 的粗粒度 Hub 方法 |
| 同一聚合的主表、明细、流水联动 | 单个含 `session` 的粗粒度 Hub 方法 |
| 两个操作无条件顺序执行并共享事务 | Service 调用两个含 `session` 的 Hub 方法 |
| 多个 Service 需要相同逻辑 | 下沉 Hub；不创建共享 Service 调用链 |
| 配置值影响业务规则 | Hub 读取 Config 后完成判断 |
| 返回 API 数据 | Service 将结果映射为 DTO/稳定结构 |

不要复制仓库中现存的越层访问、Service 业务分支或 Service-to-Service 调用；这些属于待迁移代码，不是新实现范式。

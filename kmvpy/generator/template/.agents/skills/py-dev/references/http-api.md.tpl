# DTO 与 HTTP Router

在新增或修改 DTO、FastAPI Router、鉴权依赖、审计装饰器、响应包装或 Router 注册时读取本文件。

## DTO

- 按 `common/dto/user` 与 `common/dto/admin` 分域。
- 使用 `XxxReq`、`XxxRes`、`XxxQuery` 命名并继承 `pydantic.BaseModel`。
- 使用明确类型和中文 `Field(description="...")`；按业务语义设置默认值、长度、范围和 `Literal`。
- 保持 DTO 为纯数据契约：不执行 IO、不读取配置、不访问 ORM、不承载业务流程。
- 对外的 BIGINT/KID 一律声明为 `str`，避免 JavaScript 精度丢失。
- 将 nullable 字段显式建模为 `T | None`，并与 SPA 的 `T | null` 对齐。
- 不直接返回 ORM 实例；在 Service 中组装 DTO 或稳定结构。
- 只在确有内部传递需求时使用 `exclude=True` 字段，并确认不会泄露到 API 响应。

## Router

- 按 user/admin 入口域放置文件，每个主题暴露一个 `router = APIRouter(prefix=..., tags=[...])`。
- 处理函数使用 `async def api_xxx(...)`。
- 使用 `@api_log` 记录 JSON API；成功结果通过 `ApiResponse.success_response(...)` 包装。
- 用户端受保护接口使用 `Depends(auth_user)`。
- 管理端受保护接口使用 `Depends(auth_admin)`；写操作或其他需审计操作增加 `@admin_op_log`，保持仓库现有装饰器顺序。
- Router 只完成参数绑定、依赖注入、鉴权上下文传递和响应包装。
- 不在 Router 中写 ORM/SQL、事务、缓存访问、业务判断或 Hub 调用。
- 需要设置 cookie/header 等 HTTP 细节时可在 Router 包装 Service 返回值，但不得把业务决策带回 Router。
- 新 Router 文件导入并加入 `core/main/router/__init__.py` 的 `routers` 列表。

## 契约检查

1. 拼接 `APIRouter.prefix + route.path` 得到最终 URL。
2. 核对 HTTP 方法、鉴权角色、请求 DTO、响应 DTO、分页元数据与错误语义。
3. 若契约对 SPA 可见，同时读取 `socket-and-spa-contracts.md` 并同步前端。
4. 若改变公共错误，读取 `config-and-errors.md`。
5. 按风险验证新增或修改接口的成功、鉴权与错误路径；交付前读取 `verification.md`。

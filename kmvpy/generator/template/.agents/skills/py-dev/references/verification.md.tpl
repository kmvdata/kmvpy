# 后端验证与交付检查

实现任务交付前、代码评审形成结论前读取本文件。纯解释任务仅在用户要求测试方案或合规检查时读取。

## 测试位置与格式

- 冒烟测试位于 `__PY_PROJECT_NAME__/app/st_test`。
- 测试类沿用 `StBasePyTest` 等现有 kmvpy 测试基类与 fixtures。
- 路由测试通常使用同名 `.yaml` 数据文件。
- YAML `step.action` 使用 `METHOD /uri`，路径必须是最终 API URL。
- 优先扩展最接近的现有测试；没有合适主题时才新建测试与数据文件。

## 推荐命令

从仓库根目录运行完整冒烟测试：

```bash
cd __PY_PROJECT_NAME__
source .venv/bin/activate
pytest app/st_test -vv
```

先运行聚焦测试以缩短反馈：

```bash
cd __PY_PROJECT_NAME__
source .venv/bin/activate
pytest app/st_test/test_user_opt_router.py -vv
```

按变更风险补充以下检查：

- Python 导入/语法：对修改包运行 `python -m compileall` 或项目已有静态检查。
- ORM：验证模型注册、表初始化、约束、默认值与目标数据库兼容性。
- API：验证成功、鉴权失败、业务失败、nullable、分页和 KID 字符串。
- Socket：验证 path/namespace、连接鉴权、`api_notice`、离线补偿和 Redis 条件。
- Schedule：验证注册、唯一 `kid`、幂等与失败路径。
- SPA 契约：若修改前端可见契约，使用 `spa-dev` 完成类型检查和相关测试。

## 分层复核

重新核对主 `SKILL.md` 的红线，并重点检查：

- Router 是否只调用 Service。
- Service 是否只通过 `session_scope()` 管理事务，而未做 ORM/Storage 查询、Config 读取或业务分支。
- Service 是否调用另一个 Service。
- Hub 是否保持无 DTO/FastAPI/Router/Service 依赖。
- 含 `session` 的 Hub 方法是否调用了任何其他含 `session` 的 Hub 方法。
- 事务异常捕获是否覆盖 `async with session_scope()` 的退出/提交阶段。
- DTO/稳定结构是否阻止 ORM 泄露到 Router。

## 注册与契约复核

- 新 Router 已加入 `core/main/router/__init__.py`。
- 新 ORM 已导入并加入 `_REGISTERED_ORM_MODELS`。
- 新 Schedule 已在 `schedule/__init__.py` 注册。
- 新错误只定义于 `common/exception`，调用点没有内联三元组。
- 新 Config 字段/helper 不含业务逻辑或 IO。
- API URL、HTTP 方法、DTO 字段、nullable、KID 和前端 API 方法已同步。

## 交付

- 运行 `git diff --check`，检查最终 diff 只包含任务相关变更。
- 说明实际运行的命令和结果；未运行某项检查时说明原因与剩余风险。
- 不把已有、未触及的架构债务混入本次修改；但若它直接阻止正确实现，明确报告。

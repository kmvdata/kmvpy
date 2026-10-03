# 后端验证与交付检查

实现任务交付前、代码评审形成结论前读取本文件。纯解释任务仅在用户要求测试方案或合规检查时读取。

## 验证策略

根据变更风险选择可重复的语法、导入、配置加载、应用初始化、契约检查和目标行为验证；不要为了形式完整引入与工程无关的测试框架。

建议覆盖以下检查：

- Python 导入/语法：对修改包运行 `python -m compileall` 或项目已有静态检查。
- ORM：验证模型注册、表初始化、约束、默认值与目标数据库兼容性。
- API：验证成功、鉴权失败、业务失败、nullable、分页和 KID 字符串。
- Socket：验证独立 path/namespace/transport、JWT+cookie+登录会话鉴权、同 sid 续签、结构化错误、订阅 ACK/校准、`api_notice`、已有离线补偿与 Redis 条件。
- Schedule：验证注册、唯一 `kid`、幂等与失败路径。
- SPA 契约：若修改前端可见契约，使用 `spa-dev` 完成类型检查和相关测试。

## 现有实时行为测试

涉及登录会话、Socket 或资源保护时，从 `__PY_PROJECT_NAME__` 使用项目解释器运行：

```bash
PYTHONPATH=. .venv/bin/python -m unittest discover -s tests -p test_realtime.py
```

前置条件为独立本机 Redis（默认 127.0.0.1:16389，可用 `__PROJECT_NAME_UPPER___TEST_REDIS_PORT` 指定），fixture 生成临时签名密钥和测试登录。不要改真实账号/密钥或借用已有业务 Redis；启动命令及双端浏览器复现见 [Web 实时连接文档](../../../../docs/web-realtime.md)。完成后关闭自己启动的服务。

按变更覆盖真实签名+cookie+Redis 会话、撤销/过期恢复/Redis 503、同会话更新与旧连接任务、房间初始化失败回滚；保护验证 off/observe/enforce、两域隔离、连接/订阅/HTTP 原子额度、多个独立进程竞争、TTL、实际终止续租进程和过期迟到续租拒绝。进程内 mock 或源码字符串断言不能证明共享额度正确。

真实浏览器与 polling/WebSocket 的入口是 SPA `tests/browser-acceptance.mjs`，后台配套 `tests/realtime_fixture.py`；它复用真实认证/传输/保护但省略业务离线数据库 hook，不能代替该 hook 的数据库回放验收。报告区分本机合成、真实账号、生产代理/亲和性与压力测试；环境不允许时说明具体未测项与影响，不由历史测试数量推断容量。

纯文档/skill 修改核对引用、契约和 diff；没有实现变化时无需重复启动后端或跑全部集成测试。

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

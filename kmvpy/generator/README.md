# `kmvpy.generator`

`kmvpy create` 生成 Python 后端、Quasar/Vue SPA、编辑器配置、部署脚本和实时连接验收用例。要求 Python >= 3.11。

## 创建工程与目录

```bash
kmvpy create demo_project -d /tmp
```

| 生成路径 | 内容 |
| --- | --- |
| `.vscode/` | Cursor / VS Code 解释器、导入路径和启动配置 |
| `.agents/skills/` | 后端与前端开发指南及 reference |
| `demo_project_py/pyproject.toml` | `kmvpy[mysql]` 运行依赖和 `test` extra |
| `demo_project_py/app/run.py` | 开发环境启动入口 |
| `demo_project_py/app/etc/{develop,release}/` | 配置和部署资源 |
| `demo_project_py/demo_project/` | DTO、Router、Service、Hub、ORM 和调度注册入口 |
| `demo_project_py/tests/` | Redis/鉴权/实时连接测试与本机验收服务 |
| `demo_project_spa/` | Quasar/Vue 页面与实时连接行为测试 |
| `biu` | 本地构建、上传与部署命令 |

## 更新已有工程

在工程父目录中可以按工程名更新：

```bash
cd /tmp
kmvpy update demo_project
```

如果当前命令行已经位于工程根目录，也可以直接执行：

```bash
cd /tmp/demo_project
kmvpy update
# 或
kmvpy update .
```

这两种写法等效于在父目录 `/tmp` 中执行 `kmvpy update demo_project`。

## 轮换 JWT 密钥

生成工程的配置采用 `private_key_path` + `public_keys[].kid` 的路径模式。需要轮换
user/admin JWT 密钥时，可执行：

```bash
kmvpy rotate-jwt-keys demo_project_py/app/etc/release/config.yaml
```

该命令会：

- 读取 user/admin 当前 `private_key_path` 和 active 公钥 `public_key_path` 所在目录
- 为 user/admin 分别生成新的私钥/公钥 PEM 文件
- 生成随机 `active_kid`/`kid`
- 将新公钥插入 `public_keys` 列表首位；旧公钥文件存在时最多额外保留 1 组用于旧 token 过渡验签，不存在时会移除旧配置
- 备份原 `config.yaml`

若配置缺少 `auth_config` 或 user/admin JWT 片段，命令会按 RS256、默认
issuer/audience/lifetime/session/redis 规格补齐，并将密钥生成到配置文件所在目录的
`./secrets`。

## 从调试工程回写模板

当你在生成后的工程里调试模板可用性后，可以把工程内容反向同步回当前目录或
指定目录下的 `template/`：

```bash
kmvpy gentpl demo_project -d /tmp
```

该命令会读取当前目录下的 `demo_project` 工程，并写入 `/tmp/template`。
`-d` 只指定模板输出父目录，不参与工程路径解析。不指定 `-d` 时，会读取当前目录下的
`demo_project`，并写入当前目录下的 `template/`。

如果第一个参数是相对路径或完整路径，例如 `../work/demo_project` 或
`/tmp/demo_project`，则直接读取该工程路径，并取最后一级目录名 `demo_project`
作为工程名。

写入模板时会把 Python 子项目根目录 `demo_project_py/` 映射为模板根下的 `py/`，
不会额外生成 `py/__PY_PROJECT_NAME__/` 层；文本内容里的
`demo_project`、`demo_project_py`、`demo_project_spa`、`DEMO_PROJECT_CONFIG_PATH`
会分别回写为 `__PROJECT_NAME__`、`__PY_PROJECT_NAME__`、`__SPA_PROJECT_NAME__`、
`__CONFIG_ENV_VAR__`。二进制资源会按字节同步。

为避免把运行时产物写回模板，`gentpl` 会先递归读取工程内各层 `.gitignore`，
并按 Git 的目录作用域和规则优先级跳过被忽略的文件；同时会叠加以下内置规则：

```gitignore
node_modules/
__pycache__/
.git/
*.log
*.tmp
bun.lock
.quasar/
**/dist/spa/
```

它不会删除模板中已有但工程里不存在的文件；唯一例外是旧版 `gentpl` 生成的
`py/__PY_PROJECT_NAME__/` 包装目录会被清理，避免同一 Python 子项目模板同时存在新旧两套路径。

## 安装与启动

在编辑器中打开外层 workspace 根目录，以保留生成的 `.vscode` 配置。激活项目 Python 环境，在后端目录安装：

```bash
cd demo_project_py
python -m pip install -e .
python app/run.py
```

生成工程通过 `kmvpy[mysql]` 默认包含 MySQL（aiomysql）、PostgreSQL（asyncpg）和 SQLite（aiosqlite）异步驱动。切换数据库只需修改配置中的数据库 URL。项目不再额外重复声明 SQLAlchemy、cryptography 或数据库驱动；旧项目级 `mysql`、`postgresql`、`sqlite`、`all` extras 已合并到默认安装。

配置默认为 `app/etc/develop/config.yaml`，可通过 `DEMO_PROJECT_CONFIG_PATH` 指定。运行真实应用前，应配置 JWT 密钥文件和数据库/Redis；可用 `kmvpy rotate-jwt-keys app/etc/develop/config.yaml` 生成开发密钥。用编辑器的 `Python: Select Interpreter` 选择已安装依赖的解释器。

## 运行生成工程的测试

在后端目录安装测试依赖：

```bash
python -m pip install -e ".[test]"
```

`test` extra 提供 pytest 与 HTTP/Socket.IO 测试客户端。当前模板提供 `tests/test_realtime.py` 和 `tests/realtime_fixture.py`，不自动生成业务账号冒烟数据或 `app/st_test`。

实时验收使用独立 Redis（默认本机 16389 端口），不使用业务 Redis。按生成项目的 [Web 实时连接与恢复文档](template/docs/web-realtime.md.tpl) 准备环境后，在 Python 子项目运行：

```bash
PYTHONPATH=. python -m unittest discover -s tests -p test_realtime.py
```

浏览器验收还需要启动 `tests/realtime_fixture.py`，并准备 Bun、Playwright/Chromium。具体命令、Redis端口、合成身份边界和验收限制以生成的 `docs/web-realtime.md` 为准。前端独立行为测试从 SPA 目录执行 `bun run test`。

## 自行新增 YAML 接口冒烟测试

KMVPy 的公共 `kmvpy.common.st` 模块保留 `StBasePyTest`、`StTestCase` 和 `StExpect`。需要业务 API 冒烟测试时，可自行添加 Python/YAML 同名文件；应用配置、数据库隔离、鉴权数据及 `client` fixture 由项目提供。

例如在 `tests/test_api.py` 中使用：

```python
from kmvpy.common.st import StBasePyTest, StTestCase


class TestApi(StBasePyTest):
    @StBasePyTest.data_driven
    def test_example(self, client, testdata: StTestCase):
        self.run_case(client, testdata)
```

同目录 `tests/test_api.yaml`：

```yaml
test_example:
  case_list:
    - comment: endpoint returns success
      steps:
        - step_kid: STEP_EXAMPLE
          action: GET /api/example
      expected:
        code: 0
```

`/api/example` 代表项目自行实现的接口。`step.action` 使用 `METHOD /uri`；GET/DELETE 等请求的 `request` 映射为查询参数，其余方法映射为 JSON。`StExpect` 校验必要条件，不要求完整响应完全相等。动态参数和鉴权流程可通过 `build_request_kwargs`、`after_step_hook` 和 `NextStepRequest` 扩展。

新增 fixture 后，使用 `python -m pytest tests/test_api.py -q` 执行。公共框架的完整行为以 `kmvpy/common/st/` 的源码与回归为准。

## 构建、部署与升级

生成项目的 `biu` 本地构建使用 `build` 和 `setuptools>=77.0.3`，无需单独安装 wheel 包：

```bash
python -m pip install build "setuptools>=77.0.3"
```

远程 `deploy.sh` 先安装应用 wheel，再安装并校验 `KMVPY_VERSION` 指定的 `kmvpy[mysql]` 版本，然后执行可选密钥轮换并启动服务。完整流程见生成的 `docs/ops-biu-release-guide.md`。

`kmvpy update` 保留既有业务代码、配置和依赖声明，只补缺失文件，并针对受支持的旧发布脚本作升级。已有工程升级到本次依赖契约时，应人工同步 `pyproject.toml`、`deploy.sh` 和 `biu`：默认依赖使用 `kmvpy[mysql]>=0.2.3,<0.3`，测试依赖使用 `kmvpy[test]>=0.2.3,<0.3`，并同步部署脚本固定版本。不要预期 update 覆盖已存在的业务入口或依赖文件。

## 维护生成器

修改 `kmvpy/generator/project_generator.py`、`template/` 及相邻回归。库源码环境安装 `pip install -e ".[test,dev,mysql]"` 后执行：

```bash
python -m pytest kmvpy/generator -q
python -m build
python -m twine check --strict dist/*
```

生成器回归会验证当前真实布局、Python 语法与包内导入、前端路由目标、依赖元数据、增量更新与模板回写，以及 SQLite 生命周期和 Redis ACL 兼容。

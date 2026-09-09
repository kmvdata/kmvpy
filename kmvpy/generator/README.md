# `kmvpy.generator`

`kmvpy.generator` 会生成一套开箱即用的项目骨架，其中 Python 子项目默认内置一套适合在 Cursor 中使用的自动化冒烟测试框架。

这套框架的目标不是做重型集成测试，而是用最少的样板代码完成以下事情：

- 启动生成后的 FastAPI 应用
- 通过 `pytest` 执行接口冒烟测试
- 用 YAML 描述测试步骤和期望结果
- 在测试类里用少量 hook 处理鉴权、动态请求参数、步骤间状态传递

## 生成后的目录

执行：

```bash
kmvpy create demo_project -d /tmp
```

会得到：

```text
/tmp/demo_project/
├── .vscode/
├── demo_project_py/
│   ├── pyproject.toml
│   ├── README.md
│   ├── app/
│   │   ├── run.py
│   │   ├── etc/
│   │   │   ├── develop/config.yaml
│   │   │   └── release/config.yaml
│   │   └── st_test/
│   │       ├── conftest.py
│   │       ├── test_health_router.py
│   │       ├── test_health_router.yaml
│   │       ├── test_user_opt_router.py
│   │       └── test_user_opt_router.yaml
│   └── demo_project/
└── demo_project_spa/
```

其中自动化冒烟测试相关文件都在 `PROJECT_NAME_py/app/st_test/` 下。

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

## 在 Cursor 中使用

### 1. 打开 workspace 根目录

请直接在 Cursor 打开生成后的外层目录，例如：

```text
/tmp/demo_project
```

不要只打开 `demo_project_py/`，因为 generator 会同时生成：

- 外层 `.vscode/` 配置
- Python 子项目 `demo_project_py/`
- 前端子项目 `demo_project_spa/`

生成器已经为 Cursor / VS Code 准备好了：

- `.vscode/settings.json`
- `.vscode/launch.json`

其中已经配置：

- `PYTHONPATH` 指向 `PROJECT_NAME_py`
- Python 调试工作目录为 `PROJECT_NAME_py`
- CursorPyright 能正确识别包导入

### 2. 选择 Python 解释器

在 Cursor 中建议这样做：

1. 打开终端
2. 进入 Python 子项目目录
3. 创建虚拟环境并安装依赖
4. 在 Cursor 中将解释器切换到该虚拟环境

推荐命令：

```bash
cd demo_project_py
python -m venv .venv
source .venv/bin/activate
pip install -e ".[test,sqlite]"
```

如果你要连接其他数据库，也可以按需安装：

```bash
pip install -e ".[test,mysql]"
pip install -e ".[test,postgresql]"
pip install -e ".[test,all]"
```

在 Cursor 中可通过以下方式切换解释器：

- `Cmd/Ctrl + Shift + P`
- 输入 `Python: Select Interpreter`
- 选择 `demo_project_py/.venv` 对应的解释器

### 3. 启动应用

你可以直接用终端启动：

```bash
cd demo_project_py
source .venv/bin/activate
python app/run.py
```

也可以直接使用生成好的调试配置：

- 打开 Cursor 的 Run and Debug
- 选择 `Python: Uvicorn demo_project`
- 启动后会以 `demo_project_py` 为工作目录运行 `uvicorn`

如果你只是执行 `st_test` 冒烟测试，通常不需要额外手工启动服务，因为测试会直接通过 `TestClient` 调用应用对象。

## 这套冒烟测试框架怎么工作

它的本质是：

- `pytest` 负责收集和执行测试
- `StBasePyTest.data_driven` 把 YAML 用例转成参数化测试
- 测试类调用 `self.run_case(...)` 按步骤执行 HTTP 请求
- `fastapi.testclient.TestClient` 直接调用 ASGI 应用
- `StExpect` 只校验必要条件，不要求完整响应完全一致

对应关系如下：

- 测试代码文件：`app/st_test/test_user_opt_router.py`
- 测试数据文件：`app/st_test/test_user_opt_router.yaml`

这两个文件必须：

- 文件名同名
- 位于同一目录
- YAML 顶层 key 对应测试方法名

例如 Python 测试里有：

```python
@StBasePyTest.data_driven
def test_email_login(self, user_smoke_client, testdata: StTestCase):
    self.run_case(user_smoke_client, testdata)
```

那么同目录 YAML 中就必须有：

```yaml
test_email_login:
  comment: user login smoke
  case_list:
    - comment: login with registered account
      steps:
        - step_kid: STEP_EMAIL_LOGIN
          action: POST /api/user/email/login
          request:
            email: smoke_login@example.com
            password: "SmokePass123"
      expected:
        code: 0
```

## 框架核心约定

### 1. 每个 step 都是一个 HTTP 动作

`step.action` 必须写成：

```text
<METHOD> <URI>
```

例如：

```text
GET /api/ping
POST /api/user/email/register
```

### 2. `request` 会自动映射到请求参数

- `GET/DELETE/HEAD/OPTIONS` 会映射到 `params`
- 其他请求方法会映射到 `json`

所以 YAML 中写：

```yaml
request:
  email: demo@example.com
  password: "123456"
```

对 `POST` 请求来说就会变成 JSON body。

### 3. 断言是“必要条件匹配”

这套框架不是快照测试。

如果你在 `expected.data` 中只写了：

```yaml
data:
  user:
    email: smoke@example.com
```

那么它只会检查这些关键字段，不会要求响应里的其他字段也完全一致。

这很适合做接口冒烟测试，因为返回体新增无关字段时，不会轻易把测试打爆。

### 4. 可以在步骤之间传递运行时状态

框架给测试类预留了几个 hook：

- `build_request_kwargs(...)`
- `before_step(...)`
- `after_step(...)`
- `after_step_hook(...)`

默认生成的 `test_user_opt_router.py` 就演示了两种典型用法：

- 在登录或注册成功后，从响应里提取 token 存到 `runtime`
- 在访问需要鉴权的接口时，自动把 `Authorization` 写入请求头

## 直接运行冒烟测试

### 运行全部 `st_test`

```bash
cd demo_project_py
source .venv/bin/activate
pytest app/st_test
```

### 仅运行健康检查

```bash
cd demo_project_py
source .venv/bin/activate
pytest app/st_test/test_health_router.py -q
```

### 仅运行用户模块测试

```bash
cd demo_project_py
source .venv/bin/activate
pytest app/st_test/test_user_opt_router.py -q
```

### 只运行某一个测试方法

```bash
cd demo_project_py
source .venv/bin/activate
pytest app/st_test/test_user_opt_router.py -k test_email_login -q
```

### 查看详细输出

```bash
cd demo_project_py
source .venv/bin/activate
pytest app/st_test -vv
```

## 在 Cursor 中直接运行测试

推荐两种方式。

### 方式一：内置终端

最稳定、最直观，适合先跑通一遍。

```bash
cd demo_project_py
source .venv/bin/activate
pytest app/st_test -vv
```

### 方式二：Testing 面板

如果你已经在 Cursor 中选好了虚拟环境解释器，一般可以直接：

1. 打开 Testing 面板
2. 等待 `pytest` 测试被发现
3. 运行 `app/st_test` 下的测试

如果发现失败或没有收集到测试，优先检查：

- 当前解释器是否为 `demo_project_py/.venv`
- 是否已安装 `pytest`
- 是否已安装对应数据库驱动，如 `aiosqlite`
- 当前打开的是不是外层 workspace 根目录

## 默认示例测试说明

### `test_health_router`

这个测试：

- 不依赖数据库
- 使用 `health_smoke_client`
- 验证 `GET /api/ping`

适合作为最小连通性验证。

### `test_user_opt_router`

这个测试：

- 依赖数据库
- 使用 `user_smoke_client`
- 默认会动态生成一个临时 SQLite 配置文件
- 数据库 URL 会被改写成临时目录下的 `sqlite+aiosqlite:///.../smoke.db`

这意味着：

- 你无需准备 MySQL / PostgreSQL
- 新生成项目在本地即可直接做自动化冒烟测试
- 每次运行测试都会使用独立临时库，避免污染开发数据

如果缺少 `aiosqlite`，测试会自动跳过，并提示安装：

```bash
pip install -e ".[sqlite,test]"
```

## 如何新增一个冒烟测试

推荐按这个顺序做：

1. 在 `app/st_test/` 下新增一个测试文件，例如 `test_order_router.py`
2. 在同目录新增 `test_order_router.yaml`
3. 让测试类继承 `StBasePyTest`
4. 覆盖 `on_assert()`，把 HTTP 响应转成 `ApiResponse`
5. 用 `@StBasePyTest.data_driven` + `self.run_case(...)` 执行 YAML 用例

一个最小示例：

```python
from kmvpy.common.response import ApiResponse
from kmvpy.common.st import StBasePyTest, StExpect, StTestCase


class TestOrderRouter(StBasePyTest):
    def on_assert(self, resp, expected: StExpect):
        assert resp is not None, "No steps produced a response"
        assert resp.status_code == 200, f"HTTP {resp.status_code}: {resp.text}"
        expected.assert_on(ApiResponse(**resp.json()))

    @StBasePyTest.data_driven
    def test_create_order(self, user_smoke_client, testdata: StTestCase):
        self.run_case(user_smoke_client, testdata)
```

对应 YAML：

```yaml
test_create_order:
  comment: create order smoke
  case_list:
    - comment: create one order
      steps:
        - step_kid: STEP_CREATE_ORDER
          action: POST /api/order/create
          request:
            sku: demo-sku
            quantity: 1
      expected:
        code: 0
        data:
          sku: demo-sku
          quantity: 1
```

## 常见问题

### 为什么我运行 `pytest app/st_test` 报导入错误？

优先检查：

- 你是不是在 `PROJECT_NAME_py/` 目录下运行命令
- 虚拟环境是否已经激活
- 是否已执行 `pip install -e .` 或 `pip install -e ".[test,sqlite]"`
- Cursor 当前解释器是否指向 `.venv`

### 为什么用户相关冒烟测试被跳过？

因为 `user_smoke_client` 会显式检查 `aiosqlite`。如果你没有安装 SQLite 测试依赖，测试会被跳过。

安装命令：

```bash
pip install -e ".[test,sqlite]"
```

### 为什么 YAML 改了但测试行为不对？

重点检查：

- YAML 文件名是否和测试文件同名
- YAML 顶层 key 是否和测试方法名一致
- `step.action` 是否是 `METHOD /uri` 这种格式
- `request` / `expected` 字段结构是否正确

## 给 generator 维护者

如果你的目标不是“使用生成后的测试框架”，而是修改 generator 自身，请改读：

1. `kmvpy/generator/AGENTS.md`
2. `kmvpy/generator/project_generator.py`
3. `kmvpy/generator/test_project_generator.py`
4. `kmvpy/generator/template/py/app/st_test/*.tpl`

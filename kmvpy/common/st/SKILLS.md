# `kmvpy.common.st` Agent Guide

本文件帮助 AI 理解并使用 `kmvpy/common/st` 里的轻量冒烟测试框架。

如果你的目标是编写、阅读或修改基于这个框架的测试，请先读：

1. `st_base_py_test.py`
2. `st_test_case.py`
3. `st_expect.py`
4. `test_st_expect.py`

## 框架定位

把这个 `st` 框架理解成一层很薄的约定层：

- 测试运行器仍然是 `pytest`
- 用例数据来自与测试文件同名的 `.yaml`
- `@data_driven` 负责把 YAML 里的 `case_list` 转成 `pytest.mark.parametrize(...)`
- 每个参数化样本都会被解析成 `StTestCase`
- 断言层的核心不是"完全相等"，而是 `StExpect` 的"必要条件成立"
- 基类提供 `run_case` / `on_step` / `on_assert` 三段式执行框架

它更像"YAML 驱动的冒烟测试骨架"，而不是完整 DSL 或状态机。

## 统一导入

`__init__.py` 提供统一入口，推荐用法：

```python
from kmvpy.common.st import StBasePyTest, StTestCase, Step, StExpect, Mismatch
```

## 目录内各文件职责

### `st_base_py_test.py`

框架入口、运行时胶水层和步骤执行框架。

- `_load_config(caller_src_path)`：加载与调用测试文件同名的 `.yaml`，并做缓存
- `_load_config(...)` 还会把 `users` 列表转成 `config["user_map"]`
- `data_driven(method)`：把 YAML 用例转成 `pytest` 参数化；通过 `inspect.getfile(method)` 定位 YAML，不依赖栈深度
- `generate_testcases(method_name, caller_path)`：按测试方法名读取对应 `case_list`
- `run_case(client, testdata)`：遍历 `testdata.steps`，对每一步调用 `on_step()`，最后调用 `on_assert()`
- `on_step(client, step, runtime)`：默认把 `step.action` 解析成 `"<METHOD> <URI>"` 并直接发起 HTTP 请求
- `build_request_kwargs(method, uri, step, runtime)`：给默认请求执行器补充 `json/params/headers`
- `after_step(resp, method, uri, step, runtime)`：在步骤完成后提取 token 等运行时状态
- `on_assert(resp, expected)`：对最终响应做断言，默认期望 resp 是 `ApiResponse`；HTTP 测试应覆盖此方法先做转换

### `st_test_case.py`

定义 YAML 用例会被解析成什么数据结构。

- `Step`
  - `action: str`，格式约定为 `GET /api/xxx`、`POST /api/xxx`
  - `inputs: dict | None`
- `StTestCase`
  - `name: str`
  - `username: str | None`
  - `steps: list[Step]`
  - `expected: StExpect`

### `st_expect.py`

定义"预期值"的断言语义。

- `code`、`msg`、`total` 是顶层条件
- `total` 对比的是 `ApiResponse.total`（YAML 中也可写 `count`，自动映射到 `total`）
- `data` 支持递归比较
- 比较是"必要条件比较"，不是"完全结构相等"
- `Mismatch(path, expected, actual)`：不匹配项的结构化表示
- `check(resp)` → `List[Mismatch]`：收集所有不匹配项，空列表表示全部通过
- `assert_on(resp)`：断言并在失败时抛出带路径诊断的 `AssertionError`
- `is_required_condition_for(resp)` → `bool`：向后兼容的布尔接口

### `test_st_expect.py`

行为样例，覆盖了：

- 嵌套字典和列表的子集匹配
- `assert_on` 成功 / 失败路径
- `check` 返回结构化 `Mismatch`
- `total` 字段与 `count` 别名兼容
- 缺失 key / 列表长度不匹配的诊断

### `__init__.py`

统一导出 `StBasePyTest`、`StTestCase`、`Step`、`StExpect`、`Mismatch`。

## 必须记住的约定

### 1. YAML 文件名必须和测试文件同名

`data_driven` 通过 `inspect.getfile(method)` 获取被装饰方法的源文件路径，然后推导同名 `.yaml`：

- `test_user_smoke.py`
- `test_user_smoke.yaml`

它们必须放在同一目录。

### 2. YAML 顶层键必须和测试方法名一致

`generate_testcases(method_name, caller_path)` 会读取：

- `config[method_name]["case_list"]`

所以如果测试方法叫 `test_login`，YAML 里就必须有 `test_login:` 这一节。

### 3. `case_list` 中每一项都必须能构造成 `StTestCase`

也就是说每个 case 至少要满足：

- 有 `steps`
- 有 `expected`
- 最好显式提供 `name`

如果没写 `name`，框架会回退到：

- `config[method_name]["name"]`
- 如果这个也没有，就用方法名本身

### 4. `data_driven` 的失败多数是"字段结构不匹配"

`data_driven()` 内部会把每个样本直接喂给 `StTestCase(**testcase)`。
如果 YAML 结构不对，会抛出：

- `ValueError("Test case argument error: ...")`

这通常不是 pytest 问题，而是 YAML 字段名或嵌套结构不符合 `StTestCase` / `StExpect` 的定义。

### 5. `step.action` 必须写成 `"<METHOD> <URI>"`

`run_case()` 在遍历 steps 时会调用 `self.on_step(client, step, runtime)`。
基类默认实现会直接解析 `step.action` 并调用：

```python
client.request(method, uri, **request_kwargs)
```

其中：

- `GET` / `DELETE` / `HEAD` / `OPTIONS` 默认把 `inputs` 放到 `params`
- 其他方法默认把 `inputs` 放到 `json`

因此 YAML 里的 step 应该写成：

- `GET /api/ping`
- `POST /api/user/email/register`

如果 action 不是“两段式”，框架会抛出 `ValueError`。

### 6. HTTP 测试应覆盖 `on_assert()`

基类 `on_assert()` 默认期望 `resp` 是 `ApiResponse`。
如果 `resp` 是 HTTP Response 对象（如 TestClient 的返回），子类应覆盖 `on_assert()` 做转换：

```python
def on_assert(self, resp, expected: StExpect):
    assert resp is not None, "No steps produced a response"
    assert resp.status_code == 200, f"HTTP {resp.status_code}: {resp.text}"
    expected.assert_on(ApiResponse(**resp.json()))
```

## `StExpect` 的精确语义

这是整个框架里最容易误解、也最值得保留的部分。

### 顶层字段

`check(resp)` / `assert_on(resp)` / `is_required_condition_for(resp)` 的判断规则：

- 如果 `expect.code` 不为 `None`，则必须等于 `resp.code`
- 如果 `expect.msg` 不为 `None`，则必须等于 `resp.msg`
- 如果 `expect.total` 不为 `None`，则必须等于 `resp.total`
- 如果 `expect.data` 为 `None`，则不校验 `resp.data`

注意：YAML 中可以写 `count:` 或 `total:`，两者等价（`count` 自动映射到 `total`）。

### 三种断言方式

| 方法 | 返回 | 适用场景 |
|------|------|----------|
| `check(resp)` | `List[Mismatch]` | 需要编程式处理不匹配项 |
| `assert_on(resp)` | `None`（失败抛异常） | **推荐**，失败时输出完整路径诊断 |
| `is_required_condition_for(resp)` | `bool` | 向后兼容，无诊断信息 |

`assert_on` 失败时的输出示例：

```
AssertionError: Smoke test assertion failed:
  data.user.name: expected 'bob', got 'alice'
  data.user.email: expected 'bob@test.com', got '<missing>'
```

### `data` 的递归比较

#### 字典

字典是"子集匹配"：

- `expect.data` 里写出的 key，必须都存在于 `resp.data`
- 但 `resp.data` 可以有更多未声明字段

这很适合冒烟测试，只断言关键字段，不锁死完整返回结构。

#### 列表

列表是"等长且按顺序逐项匹配"：

- 长度必须相等
- 顺序必须一致
- 每个元素递归比较

所以列表不是"包含关系"，而是"精确位置匹配"。

#### 嵌套对象

如果 `expect.data` 里嵌入了 `StExpect`，会继续调用其
`check(...)`。

虽然当前仓库里的样例主要覆盖了字典/列表，但代码已经支持这类递归写法。

## 一个典型测试应该怎么写

推荐模式是：测试类继承 `StBasePyTest`，通常只覆盖 `on_assert`；如果需要鉴权头、token 回填等运行时逻辑，再覆盖 `build_request_kwargs` / `after_step`；测试方法使用 `@data_driven` + `run_case`。

```python
from kmvpy.common.response import ApiResponse
from kmvpy.common.st import StBasePyTest, StExpect, StTestCase, Step


class TestUserSmoke(StBasePyTest):
    def on_assert(self, resp, expected: StExpect):
        assert resp is not None, "No steps produced a response"
        assert resp.status_code == 200
        expected.assert_on(ApiResponse(**resp.json()))

    @StBasePyTest.data_driven
    def test_login(self, smoke_client, testdata: StTestCase):
        self.run_case(smoke_client, testdata)
```

对应 YAML 可以写成：

```yaml
test_login:
  name: 登录冒烟
  case_list:
    - name: 正常登录
      username: admin
      steps:
        - action: POST /api/login
          inputs:
            login_name: admin
            password: "123456"
      expected:
        code: 0
        msg: ok
        data:
          token: demo
```

## `users` / `user_map` 的含义

`_load_config()` 会执行：

```python
config["user_map"] = {u["user_type"]: u for u in config.get("users", [])}
```

这说明 YAML 可以额外维护一组用户配置，并按 `user_type` 建索引。

但要注意：

- 当前 `st` 目录里的公开流程没有直接消费 `user_map`
- 它更像给具体业务测试类预留的辅助配置
- 如果你要使用它，通常需要在自定义测试逻辑里显式读取配置

因此，AI 不要假设 `username` 会自动映射成用户信息；当前代码里没有这一步。

## 修改这个框架时最容易改坏的点

### 默认 HTTP 执行器 / `on_assert` 的覆盖契约

`run_case()` 依赖 `on_step()` 的默认 HTTP 执行逻辑和 `on_assert()` 的断言逻辑。

如果你重构了：

- `run_case()` 的执行流程
- `on_step()` 的签名（`client, step, runtime`）
- `parse_step_action()` 的 `"<METHOD> <URI>"` 约定
- `build_request_kwargs()` 的签名（`method, uri, step, runtime`）
- `after_step()` 的签名（`resp, method, uri, step, runtime`）
- `on_assert()` 的签名（`resp, expected`）

就可能导致已有测试类或 generator 生成的模板无法正常运行。

### 列表比较不是"部分匹配"

很多人会误以为 `expected.data` 里只写部分列表元素即可。
当前实现不是这样。

对列表来说：

- 长度必须一致
- 顺序必须一致

如果你要把列表语义改成"包含"或"子序列"，必须同步补测试。

## 给 AI 的工作建议

### 编写新用例时

优先保持现有轻约定，不要发明额外 DSL。

建议：

1. 测试方法名先定好
2. 建同名 YAML
3. 每个 case 明确写 `name`
4. `steps` 中的 `action` 统一写成 `METHOD /uri`
5. `expected` 只断言关键字段，避免把冒烟测试写成快照测试
6. 断言优先使用 `assert_on()`（有诊断），而不是 `is_required_condition_for()`（无诊断）

### 编写新测试类时

1. 继承 `StBasePyTest`
2. 优先复用默认 `on_step()`，让 YAML 直接驱动 HTTP 请求
3. 覆盖 `on_assert(resp, expected)` 做 HTTP → ApiResponse 转换
4. 如需鉴权头、动态 query/body、token 回填，再覆盖 `build_request_kwargs(...)` / `after_step(...)`
5. 每个测试方法只需 `@data_driven` + `self.run_case(client, testdata)`
6. 步骤间共享状态（如 token）通过 `runtime` 字典传递

### 扩展数据模型时

如果你给 `Step` 或 `StTestCase` 新增字段，需要一起检查：

1. `st_test_case.py` 的 Pydantic 模型
2. YAML 示例和现有用例
3. `data_driven()` 的报错是否仍然清晰
4. 是否需要新增测试覆盖解析行为

### 扩展断言语义时

如果你改 `StExpect`，至少要补：

1. 成功匹配用例
2. 失败匹配用例（验证 `Mismatch` 的 path 和 expected/actual）
3. 字典递归用例
4. 列表语义用例
5. `total -> resp.total` 映射用例

## 最小验证

如果你修改了这个框架本身，至少运行：

```bash
pytest kmvpy/common/st/test_st_expect.py
```

如果你新增了基于该框架的业务测试，还应再运行对应测试文件，确认：

- YAML 被正确加载
- `@data_driven` 能生成参数化 case
- 默认 HTTP step 执行器或你自定义的 hook 逻辑符合预期
- `on_assert` 的断言在失败时能输出有用的诊断信息

## 一句话心智模型

把 `kmvpy.common.st` 当成"pytest + 同名 YAML + Pydantic 用例模型 + 必要条件断言 + 默认 HTTP step 执行器 + 少量 runtime hook" 的薄封装；它负责组织、表达和执行冒烟测试骨架，业务差异通常通过 `build_request_kwargs` / `after_step` / `on_assert` 注入。

# HTTP、DTO、鉴权与错误契约

在修改 DTO、API wrapper、Axios、ApiResponse、鉴权存储、登录/退出、后端 URL/方法或 Kmv API 错误链时读取本文件。涉及后端编辑时同时使用 `py-dev`。

## 调用链与 client 选择

```text
page/component -> ApiXxx static method -> user/admin/generic HTTP client -> Axios -> backend
                                                            -> unwrap ApiResponse<T> -> T
```

- 页面和组件只调用 `src/network/api` wrapper，不直接拼 URL、调用原始 Axios 或 `fetch`。
- 用户接口使用 `postUserApi/getUserApi`，管理接口使用 `postAdminApi/getAdminApi`。
- 用户或管理员的登录、注册等认证入口即使位于公开页面，也继续使用对应域 client，以接入 token、401 和 Socket 生命周期。
- 只有真正域中立、无需 user/admin 身份生命周期的公开接口才使用 generic `postApi/getApi`。
- 不手写 Authorization、device 或 content-type 请求头；底层 Axios 已统一处理，第三方请求除外。

## DTO 规则

- 对象形状使用 `export interface`；字面量枚举等非对象类型可使用 `type`。
- 传输 JSON 字段与后端一致，保持 `snake_case`；TypeScript 方法、变量和本地派生状态使用 `camelCase`。
- 后端 nullable 字段写成 `T | null`；只有后端允许字段缺失时才使用 `?`。
- BIGINT/KID 对外保持 `string`，比较 Socket 或 route 值时使用 `String(...)` 归一化。
- 后端分页端点通常以请求 `page/size` 和业务响应 `{ items, total }` 表示；不要与 `ApiResponse` envelope 自身 nullable 的 `page/size/total` 混为一谈。
- 精确相同的跨域契约只保留一个权威定义，不为了域隔离复制 interface。新契约确实由多域共享且没有权威模块时，可建立 `src/network/dto/shared`；域专属 DTO 仍留在 user/admin。
- 修改字段、nullable、枚举、URL 或 HTTP 方法时检查所有后端返回点、前端 DTO、API wrapper、页面、Socket 过滤和测试数据。

## API wrapper 规则

- 类名使用 `ApiXxx`，方法使用 `static` 和 `camelCase`，并显式声明请求与响应泛型。
- URL、HTTP 方法和 empty-data 语义必须与后端 Router 完全一致；不要因为当前多数接口使用 POST 就猜测新接口。
- wrapper 只负责传输与对应域的网络会话生命周期，不维护页面 loading、业务筛选、缓存、Dialog、Notify 或路由状态。
- 当前仅认证/退出 wrapper 可以按既有模式同步对应域 Socket 的 authorization/logout；不要把这一例外扩展到普通业务 API。
- 传给底层 helper 的 fallback 必须已由 i18n 翻译，可由调用者传入或通过 `i18n.global.t(...)` 获取；不要新增单语言硬编码 fallback。
- 可取消读取让 API 方法向底层 helper 透传可选 `AxiosRequestConfig` / `signal`；不要在 wrapper 吞掉取消或另起不受页面协调器控制的请求。

## ApiResponse 与错误

- `post*Api/get*Api` 已解包 `ApiResponse<T>`，页面拿到的是 `T`，不再访问 `.data`。
- `unwrapApiResponse` 默认把成功但 `data` 为 null/undefined 视为错误；只有后端明确返回空数据时才设计并验证 `allowEmptyData` 通路。
- 业务失败应保留 `ApiResponseError` 的 `code` 与 envelope，供 Kmv resolver 使用；不要再包装成普通 `Error`。
- 当前 helper 的非 2xx 分支保留 `AxiosError.response` 的状态、headers 和 body，供鉴权及 Kmv resolver 分类；不要改回普通 `Error`。部分遗留页面直接展示 `error.message`，任务触及时按统一错误链修正。
- 不直接在页面显示后端 `msg`。调用 `useKmvApiErrorMessage().resolveFromError(...)` 等统一入口；未知 code 的后端 msg 回退只能由 resolver 内部控制。

## 鉴权契约

- user 使用 `get/set/clearStoredUserAuthorization`，admin 使用 `get/set/clearStoredAdminAuthorization`；不要从页面调用无域底层 helper。
- 存储键分别为 `${VITE_AUTH_STORAGE_KEY}:user` 与 `${VITE_AUTH_STORAGE_KEY}:admin`。
- 请求所用凭据快照由 `axios.ts` 保存；响应续签只有请求、当前凭据与新 token 属于同一稳定 `sid`/用户/域且 JWT `exp` 前进才写入。迟到旧会话续签不能覆盖新登录，相同/倒退结果不能覆盖较新 token。
- `axios_user.ts` / `axios_admin.ts` 仅在 HTTP 401、`X-Auth-Error: session_invalid`、`X-Auth-Role` 匹配且请求凭据仍为当前凭据时退出本域。普通 401 文案、网络故障、503、429 不清登录；跳转只作用于当前路由所属失效域。
- 登录、响应头续签、跨标签 logout 与跳转由对应 boot/client 管理。普通 token 更新不换协调身份，不拆健康 Socket 或进行中的有效握手。
- 鉴权存储使用 `realtime/session.ts` 的 `StorageOverlay`；删除失败仍以内存 tombstone 屏蔽旧凭据。整页刷新会丢失内存覆盖，不能宣称已持久退出；后台会话校验仍是权限依据。
- 对应域连接/续期校验为 `POST /api/{user|admin}/socket/session`，要求成功 envelope 的 `code: 0` 与 `data.valid: true`，支持 signal 和 5s 超时。过期 token 可通过有效登录会话续签；共享会话存储暂不可用返回 503，应保留登录。连接校验单流程与恢复详见主 Skill 的 `sockets.md`。
- user/admin API client、鉴权 helper、登录路由、Socket 和 logout 广播必须成套匹配，不能交叉。
- 任何登录成功 fallback 都要核对 `routes.ts` 中真实存在的路由名。

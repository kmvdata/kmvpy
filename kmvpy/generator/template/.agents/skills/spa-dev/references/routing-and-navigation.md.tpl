# 路由、鉴权、Layout 与导航

在新增页面入口、修改 URL、鉴权跳转、redirect、Layout、drawer、导航或页面标题时读取本文件。

## 访问域

| 域 | 入口与 Layout | 鉴权与网络身份 |
|---|---|---|
| `home` | `/`、`/auth`、`/login`，`HomeLayout` | 公开页面；用户认证操作仍使用 user client |
| `app` | `/app/**`，`UserLayout` | `requiresAuth`、user auth/client/socket |
| `admin` | `/admin/login` 及 `/admin/**`，内容页使用 `AdminLayout` | `requiresAdminAuth`、admin auth/client/socket |

- `/app` 默认进入 `user-profile`；用户内容按 `personal`、`work-tickets`、`help` 分组。
- `/admin` 默认进入 `admin-users`；管理内容按 `management`、`system` 组织。
- `/user` 与 `/dashboard` 仅用于兼容重定向，不在这些路径下增加主入口。
- `/admin/login` 是独立认证页，不挂在 `AdminLayout` 下。

## 路由与守卫

- 只在 `src/router/routes.ts` 注册页面入口，使用指向真实文件的懒加载 import。
- 路由名保持稳定的 kebab-case；用户路由通常以 `user-` 开头，管理路由以 `admin-` 开头。
- `/app` 子路由继承 `requiresAuth`；除登录外的 `/admin` 子路由继承 `requiresAdminAuth`。
- 有稳定路由名时优先使用具名跳转；修改或删除名称前搜索所有 `router.push/replace`、redirect 与 template `:to`。
- 兼容重定向保留 query/hash。
- 登录后的 `redirect` 只接受以单个 `/` 开头且不以 `//` 开头的字符串，避免开放重定向。
- history 部署必须由服务端把未知前端路径回退到 `index.html`。
- 不假设代码中的 fallback route name 仍存在；以 `routes.ts` 为准核对。

## 页面放置

- 用户内容页放在 `src/pages/app/<group>`，URL 保留分组段，例如 `/app/personal/profile`。
- 管理内容页放在 `src/pages/admin/<group>`，URL 保持在 `/admin/**`。
- 挂载在 `UserLayout` 或 `AdminLayout` 下的内容页使用 `q-page` 根容器；独立登录或公开页面可拥有自己的页面外壳。
- 不为单个页面新增 Layout，也不把用户页放入 admin 路由树或反向放置。

## Layout 与导航

Layout 只负责全局外壳、toolbar、drawer、导航状态、当前标题/副标题和 `router-view`；不承载业务表单、列表、详情或页面数据请求。

增加 drawer 入口时：

1. 先注册路由，再更新对应 `UserLayout.vue` 或 `AdminLayout.vue` 的 nav item。
2. 让 `toUri` 与最终 route path 完全一致，并核对 query 参与激活判断的情况。
3. 更新 item 类型、section 类型、扁平索引、section 映射、展开状态和最长路径匹配。
4. 同步 `layouts.userNav.*` 或 `layouts.adminNav.*` 的标题与副标题，两种语言同时维护。
5. 优先复用现有 section；只有形成稳定的多页面业务域时才增加一级分组。

没有 drawer 入口的详情页仍需检查 Layout 能否解析合理标题，以及父导航是否保持激活。

## 修改流程

1. 明确 home/app/admin 域、最终 URL、鉴权要求和是否需要 drawer 入口。
2. 创建或移动页面后更新 `routes.ts`，再处理导航和 i18n。
3. 搜索旧路径、路由名、redirect、深链和 Socket `api_uri` 过滤条件。
4. 验证未登录跳转、登录回跳、刷新深链、404 fallback、query/hash 和移动端 drawer。

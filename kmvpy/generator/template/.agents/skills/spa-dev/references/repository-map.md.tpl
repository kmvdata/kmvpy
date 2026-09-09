# SPA 项目地图与运行基线

在定位文件、调整依赖、修改 Quasar/Vite 配置、增加 boot 文件或确认运行命令时读取本文件。

## 信息来源优先级

1. 真实代码、`package.json`、`bun.lock`、`quasar.config.ts` 和实际 import。
2. 本 Skill 与对应 reference。
3. README 仅作背景；其中的包管理器、目录或启动方式可能滞后。

不要把现存的硬编码文案、越域导入或旧路由名当作新实现范式；先核对调用方，再局部修正任务涉及的部分。

## 运行基线

- 技术栈为 Quasar SPA、Vue 3、TypeScript strict、Vite、Vue Router、Pinia、Axios、Vue I18n 和 Socket.IO client。
- 路由模式为 history；浏览器构建目标为 ES2022，Node 目标为 22，`package.json` 要求 Node >= 22.22.0。
- 仓库存在 `bun.lock`，默认使用 Bun；`package.json` 当前未声明 `packageManager` 字段。
- 常用命令为 `bun run dev`、`bun run lint`、`bun run build` 和 `bun run format`。
- `VITE_API_BASE_URL` 与 `VITE_AUTH_STORAGE_KEY` 在网络模块加载时必须存在。

`quasar.config.ts` 当前 boot 顺序为：

```text
app_logo -> pinia -> i18n -> framework_style -> axios -> axios_user -> axios_admin
```

`src/boot/api_response.ts` 是被网络层导入的普通模块，不是 Quasar boot 文件。新增 boot 文件后必须在 `quasar.config.ts` 注册，并检查顺序依赖。

## 目录职责

- `src/boot`：全局初始化、Axios client、鉴权生命周期、i18n、Pinia 和框架样式。
- `src/router`：集中路由表、history 创建和全局鉴权守卫。
- `src/layouts`：公开、用户和管理端外壳、导航、toolbar、drawer 与 `router-view`。
- `src/pages/home`：公开首页和认证入口。
- `src/pages/app`：普通用户 `/app` 内容页。
- `src/pages/admin`：管理端登录和 `/admin` 内容页。
- `src/components`：可复用、由 props/slots 驱动的 UI 片段。
- `src/composables`：可复用 Vue 生命周期与状态组合逻辑。
- `src/network/dto`：后端传输契约，当前按 `user`、`admin` 组织。
- `src/network/api`：静态 API wrapper，当前按 `user`、`admin` 组织。
- `src/network/socket`、`src/network/admin_socket`：两套隔离的实时连接和多标签协作。
- `src/css`：动态字号层、主题层、Quasar/遗留桥接和访问域样式。
- `src/i18n`：`zh-CN`、`en-US` 文案与 Kmv 错误翻译。
- `src/utils/frameworkStyle.ts`：主题和字号模式切换。

## 依赖与跨 Skill 规则

- 优先复用现有依赖；不要引入第二套 UI、样式或状态管理框架。
- 不为简单 helper 新增依赖，不降级现有依赖，也不通过关闭 TypeScript、ESLint 或 Quasar checker 绕过错误。
- 更新依赖时同时更新 `package.json` 与 `bun.lock`，并说明现有栈不足之处。
- 任何 `__PY_PROJECT_NAME__` 编辑都同时使用 `py-dev` Skill；只读取后端以核对契约时也遵循其架构事实，不顺带扩大修改范围。

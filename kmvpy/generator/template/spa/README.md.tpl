# __SPA_PROJECT_NAME__

这是 `__PROJECT_NAME__` 的 Quasar + Vue SPA 前端工程模板。

## 开发

```bash
npm install
npm run dev
```

## 打包

```bash
npm run build
```

## 说明

- 路由模式默认使用 `history`
- 已启用 Quasar 插件：`Notify`、`Dialog`
- 默认注入了 `src/boot/api_response.ts` 与 `src/boot/axios.ts`
- 默认生成 `.env.development` 与 `.env.production`，API 地址和后端默认示例配置联动
- 默认提供 `HomeLayout` 与 `UserLayout` 两套布局：首页和未登录页面走 `HomeLayout`，登录后示例页走 `UserLayout`
- 首页右上角内置登录按钮，点击后弹出认证对话框；`/auth` 页面与首页弹窗复用同一套邮箱登录/注册流程
- 登录或注册成功后会写入本地授权信息，并跳转到 `UserLayout` 下的 `/app/personal/users` 用户端首页
- 页面目录默认按 `src/pages/home` 与 `src/pages/user` 拆分，方便与 `network/api/user`、`network/dto/user` 的普通用户域保持一致
- 已包含与后端同构的 `user/user_op` DTO / API 封装；SPA 开发规范统一维护在 `kmvpy/generator/__SKILLS.md.tpl`


## 构建证书

如需再nginx下发布spa，可以通过如下方式构建证书：

```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d www.example.com # 替换成目标域名
```

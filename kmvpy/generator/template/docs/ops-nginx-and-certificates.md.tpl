# Nginx 配置与证书指南

Nginx 承担两个入口：

- `https://www.example.com` → 静态 SPA（文件根目录 `<发布目录>/spa`）
- `https://api.example.com` → 后端 API + Socket.IO 反代（后端监听 `127.0.0.1:15000`，见 release/config.yaml）

API 反代必须保留 WebSocket upgrade（Socket.IO 路径 `/ws/socket.io`）。

## 1. 生成配置

```bash
BIU_API_HOST=https://api.example.com \
BIU_SPA_HOST=https://www.example.com \
BIU_DEPLOY=deploy@example.com:/home/__PROJECT_NAME__/__PROJECT_NAME___dist \
./biu nginx
```

生成到当前目录：

```text
nginx.conf.d/api.example.com.conf
nginx.conf.d/www.example.com.conf
```

## 2. 安装并重载

```bash
sudo cp nginx.conf.d/api.example.com.conf /etc/nginx/conf.d/
sudo cp nginx.conf.d/www.example.com.conf /etc/nginx/conf.d/
sudo nginx -t && sudo systemctl reload nginx
```

`nginx -t` 报证书文件不存在？先做第 3 步。

## 3. 证书

### 生产：Let's Encrypt（推荐）

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d api.example.com
sudo certbot --nginx -d www.example.com
```

生成的配置默认引用 `/etc/letsencrypt/live/<域名>/` 下的证书，certbot 会自动补齐 SSL 参数文件。

### 测试/内网：自签证书

每个域名生成一个（以 api 为例，www 域名重复一遍）：

```bash
DOMAIN=api.example.com
sudo mkdir -p /etc/letsencrypt/live/${DOMAIN}
cat > /tmp/${DOMAIN}.cnf <<EOF
[req]
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req
[dn]
CN = ${DOMAIN}
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DOMAIN}
EOF
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/letsencrypt/live/${DOMAIN}/privkey.pem \
  -out /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
  -config /tmp/${DOMAIN}.cnf
sudo chmod 600 /etc/letsencrypt/live/${DOMAIN}/privkey.pem
```

服务器上没有 certbot 生成的 `/etc/letsencrypt/options-ssl-nginx.conf` 时手动补齐：

```bash
sudo tee /etc/letsencrypt/options-ssl-nginx.conf >/dev/null <<'EOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
EOF
sudo openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
```

自签证书浏览器会警告，需把证书导入信任链；团队多人共用时建议用自签 CA 统一签发（每台机器只信任一个根 CA），避免逐台信任多个证书。

## 4. 域名与三处对齐

正式环境在 DNS 加 A 记录；本地测试写 `/etc/hosts`：

```text
192.168.1.10 api.example.com
192.168.1.10 www.example.com
```

换域名时三处必须同步：

1. `biu` 顶部 `BIU_API_HOST` / `BIU_SPA_HOST`
2. `__SPA_PROJECT_NAME__/.env.production` 的 `VITE_API_BASE_URL`（用 `biu` 构建会自动同步）
3. `release/config.yaml` 的 `service.cors_allow_origins`

## 5. 验证

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -kI https://www.example.com        # SPA
curl -k https://api.example.com/docs    # API（-k 仅用于自签测试）
openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null
```

## 排障速查

| 现象 | 处理 |
| --- | --- |
| `nginx -t` 报 options-ssl-nginx.conf 不存在 | 按第 3 步手动创建 |
| 浏览器访问仍警告 | 自签需信任证书本身；多人环境建议 CA 方案 |
| Socket.IO 连不上 | 确认 API 反代保留 WebSocket upgrade、路径为 `/ws/socket.io` |
| 跨域失败 | 检查 `cors_allow_origins` 与浏览器实际 origin 一致 |

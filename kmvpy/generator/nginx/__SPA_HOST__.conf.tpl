server {
    listen __SPA_LISTEN__;
    server_name __SPA_HOST__;

    root __SPA_ROOT__;
    index index.html;
__SPA_SSL_DIRECTIVES__
    location / {
        try_files $uri $uri/ /index.html;
    }

    location = /index.html {
        add_header Cache-Control "no-cache";
    }

    location ~* \.(?:js|css|mjs|map|png|jpg|jpeg|gif|ico|svg|webp|woff|woff2|ttf|eot)$ {
        try_files $uri =404;
        access_log off;
        log_not_found off;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }
}
__SPA_HTTP_REDIRECT_SERVER__

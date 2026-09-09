map $http_origin $cors_origin {
    default "";
__CORS_SPA_ORIGIN_LINE__
}

map $http_access_control_request_headers $cors_allow_headers {
    default $http_access_control_request_headers;
    "" "Authorization,Content-Type,Accept,Origin,User-Agent,X-Requested-With,x-os-version,x-app-version,x-device-id,x-device-type,x-device-model,x-network,x-brand";
}

map $http_upgrade $connection_upgrade {
    default upgrade;
    "" close;
}

server {
    listen __API_LISTEN__;
    server_name __API_HOST__;
__API_SSL_DIRECTIVES__
    location / {
        proxy_pass http://127.0.0.1:15000;

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;

        proxy_hide_header Access-Control-Allow-Origin;
        proxy_hide_header Access-Control-Allow-Methods;
        proxy_hide_header Access-Control-Allow-Headers;
        proxy_hide_header Access-Control-Allow-Credentials;

        add_header Access-Control-Allow-Origin $cors_origin always;
        add_header Access-Control-Allow-Methods "GET,POST,OPTIONS,PUT,DELETE,PATCH" always;
        add_header Access-Control-Allow-Headers $cors_allow_headers always;
        add_header Access-Control-Allow-Credentials "true" always;
        add_header Access-Control-Max-Age 86400 always;
        add_header Vary Origin always;

        if ($request_method = OPTIONS) {
            return 204;
        }
    }
}
__API_HTTP_REDIRECT_SERVER__

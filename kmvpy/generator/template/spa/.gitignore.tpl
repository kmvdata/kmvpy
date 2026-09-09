# ==============================
# 系统自动生成文件（全局忽略）
# ==============================
.DS_Store
.thumbs.db
*.log
.cache/
.temp/
.tmp/

# ==============================
# 依赖包目录（必须忽略）
# 团队统一通过 lock 文件安装，不上传依赖包
# ==============================
node_modules/

# ==============================
# 构建 / 打包输出产物（必须忽略）
# 编译后生成的文件，服务器会自动构建
# ==============================
dist/
out/
build/
.quasar/
.output/
.nuxt/
.next/

# ==============================
# Quasar 框架专属文件
# ==============================
/quasar.config.*.temporary.compiled*

# ==============================
# Cordova 构建相关（移动端打包）
# ==============================
/src-cordova/node_modules
/src-cordova/platforms
/src-cordova/plugins
/src-cordova/www

# ==============================
# Capacitor 构建相关（移动端打包）
# ==============================
/src-capacitor/www
/src-capacitor/node_modules

# ==============================
# 环境变量配置（敏感信息，绝对不上传）
# ==============================
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# ==============================
# 调试日志文件（自动生成）
# ==============================
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
lerna-debug.log*

# ==============================
# 编辑器 / IDE 配置（个人习惯，不共享）
# ==============================
.idea/
.vscode/
*.suo
*.ntvs*
*.njsproj
*.sln
*.swp
*.swo

# ==============================
# 测试覆盖率报告（自动生成）
# ==============================
coverage/
*.lcov

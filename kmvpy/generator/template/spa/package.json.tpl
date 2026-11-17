{
  "name": "__SPA_PROJECT_NAME__",
  "version": "0.0.1",
  "description": "Quasar SPA for __PROJECT_NAME__",
  "productName": "__SPA_PROJECT_NAME__",
  "author": "kmvpy generator",
  "type": "module",
  "private": true,
  "scripts": {
    "lint": "eslint -c ./eslint.config.js \"./src*/**/*.{ts,js,cjs,mjs,vue}\"",
    "format": "prettier --write \"**/*.{js,ts,vue,scss,html,md,json}\" --ignore-path .gitignore",
    "dev": "quasar dev",
    "build": "quasar build",
    "postinstall": "quasar prepare",
    "test": "bun test tests/realtime.test.js"
  },
  "dependencies": {
    "@quasar/extras": "^2.1.0",
    "axios": "^1.21.0",
    "pinia": "^4.1.0",
    "quasar": "^2.35.2",
    "socket.io-client": "^4.8.4",
    "vue": "^3.5.44",
    "vue-i18n": "^11.4.18",
    "vue-router": "^5.4.0"
  },
  "devDependencies": {
    "@eslint/js": "^9.14.0",
    "@intlify/unplugin-vue-i18n": "^11.2.8",
    "@quasar/app-vite": "^2.1.0",
    "@types/node": "^22.0.0",
    "@vue/eslint-config-prettier": "^10.1.0",
    "@vue/eslint-config-typescript": "^14.4.0",
    "autoprefixer": "^10.6.2",
    "eslint": "^9.14.0",
    "eslint-plugin-vue": "^10.12.0",
    "globals": "^17.14.0",
    "prettier": "^3.9.10",
    "typescript": "^5.9.2",
    "vite-plugin-checker": "^0.11.0",
    "vue-eslint-parser": "^10.2.0",
    "vue-tsc": "^3.3.14"
  },
  "engines": {
    "node": ">=22.22.0",
    "npm": ">= 8.0.0",
    "yarn": ">= 1.22.0",
    "pnpm": ">= 10.0.0"
  }
}

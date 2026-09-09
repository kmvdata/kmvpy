import { defineConfig } from '#q-app/wrappers';

export default defineConfig(() => ({
  boot: ['app_logo', 'pinia', 'i18n', 'framework_style', 'axios', 'axios_user', 'axios_admin'],
  css: ['app.css', 'home.css', 'admin.css', 'user.css'],
  extras: ['roboto-font', 'material-icons'],
  build: {
    target: {
      browser: ['es2022'],
      node: 'node22',
    },
    typescript: {
      strict: true,
      vueShim: true,
    },
    vueRouterMode: 'history',
    vitePlugins: [
      [
        'vite-plugin-checker',
        {
          vueTsc: true,
          eslint: {
            lintCommand: 'eslint -c ./eslint.config.js "./src*/**/*.{ts,js,mjs,cjs,vue}"',
            useFlatConfig: true,
          },
        },
        { server: false },
      ],
    ],
  },
  devServer: {
    open: true,
  },
  framework: {
    plugins: ['Notify', 'Dialog'],
  },
  animations: [],
}));

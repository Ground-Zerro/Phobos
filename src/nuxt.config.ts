import { fileURLToPath } from 'node:url';

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  future: {
    compatibilityVersion: 4,
  },
  compatibilityDate: '2026-02-06',
  devtools: { enabled: true },
  modules: [
    '@nuxtjs/i18n',
    '@nuxtjs/tailwindcss',
    '@pinia/nuxt',
    '@eschricht/nuxt-color-mode',
    'radix-vue/nuxt',
    '@vueuse/nuxt',
    '@nuxt/eslint',
    '@nuxt/test-utils/module',
  ],
  colorMode: {
    preference: 'system',
    fallback: 'light',
    classSuffix: '',
    cookieName: 'theme',
  },
  css: ['~/app.css'],
  i18n: {
    langDir: 'locales/',
    experimental: {
      localeDetector: './localeDetector.ts',
    },
    locales: [
      { code: 'en', language: 'en-US', name: 'English', file: 'en.json' },
      { code: 'de', language: 'de-DE', name: 'Deutsch', file: 'de.json' },
      { code: 'es', language: 'es-ES', name: 'Español', file: 'es.json' },
      { code: 'it', language: 'it-IT', name: 'Italiano', file: 'it.json' },
      { code: 'fr', language: 'fr-FR', name: 'Français', file: 'fr.json' },
      { code: 'ko', language: 'ko-KR', name: '한국어', file: 'ko.json' },
      { code: 'ru', language: 'ru-RU', name: 'Русский', file: 'ru.json' },
      { code: 'uk', language: 'uk-UA', name: 'Українська', file: 'uk.json' },
      {
        code: 'zh-CN',
        language: 'zh-CN',
        name: '简体中文',
        file: 'zh-CN.json',
      },
      {
        code: 'zh-HK',
        language: 'zh-HK',
        name: '繁體中文（香港）',
        file: 'zh-HK.json',
      },
      {
        code: 'zh-TW',
        language: 'zh-TW',
        name: '正體中文 (台灣)',
        file: 'zh-TW.json',
      },
      { code: 'pl', language: 'pl-PL', name: 'Polski', file: 'pl.json' },
      { code: 'cs', language: 'cs-CZ', name: 'Čeština', file: 'cs.json' },
      {
        code: 'pt-BR',
        language: 'pt-BR',
        name: 'Português (Brasil)',
        file: 'pt-BR.json',
      },
      { code: 'tr', language: 'tr-TR', name: 'Türkçe', file: 'tr.json' },
      { code: 'bn', language: 'bn-BD', name: 'বাংলা', file: 'bn.json' },
      {
        code: 'id',
        language: 'id-ID',
        name: 'Bahasa Indonesia',
        file: 'id.json',
      },
      { code: 'nl', language: 'nl-NL', name: 'Nederlands', file: 'nl.json' },
      { code: 'nb', language: 'nb-NO', name: 'Norsk bokmål', file: 'nb.json' },
      { code: 'bg', language: 'bg-BG', name: 'Български', file: 'bg.json' },
      { code: 'gl', language: 'gl-ES', name: 'Galego', file: 'gl.json' },
      { code: 'vi', language: 'vi-VN', name: 'Tiếng Việt', file: 'vi.json' },
    ],
    defaultLocale: 'en',
    vueI18n: './i18n.config.ts',
    strategy: 'no_prefix',
    detectBrowserLanguage: {
      useCookie: true,
    },
  },
  experimental: {
    payloadExtraction: false,
  },
  vite: {
    build: {
      chunkSizeWarningLimit: 600,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (id.includes('radix-vue')) {
              return 'vendor-radix';
            }
            if (id.includes('@vueuse')) {
              return 'vendor-vueuse';
            }
            if (id.includes('intlify') || id.includes('vue-i18n')) {
              return 'vendor-i18n';
            }
            if (
              id.includes('/node_modules/pinia/') ||
              id.includes('node_modules/pinia/')
            ) {
              return 'vendor-pinia';
            }
          },
        },
      },
    },
  },
  nitro: {
    esbuild: {
      options: {
        target: 'node20',
      },
    },
    alias: {
      '#db': fileURLToPath(new URL('./server/database/', import.meta.url)),
    },
    externals: {
      traceInclude: [fileURLToPath(new URL('./cli/index.ts', import.meta.url))],
    },
  },
  alias: {
    // for typecheck reasons (https://github.com/nuxt/cli/issues/323)
    '#db': fileURLToPath(new URL('./server/database/', import.meta.url)),
  },
});

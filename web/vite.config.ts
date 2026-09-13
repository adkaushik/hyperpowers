import { defineConfig } from 'vite'
import { devtools } from '@tanstack/devtools-vite'

import { tanstackStart } from '@tanstack/react-start/plugin/vite'

import viteReact from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { nitro } from 'nitro/vite'

// better-sqlite3 is a native addon: Vite cannot transform it and Rollup cannot
// bundle it, so it stays external in dev and in the build and is loaded by Node
// at runtime.
const NATIVE_DEPS = ['better-sqlite3']

const config = defineConfig({
  resolve: { tsconfigPaths: true },
  ssr: { external: NATIVE_DEPS },
  plugins: [
    devtools(),
    nitro({ rollupConfig: { external: [/^@sentry\//, ...NATIVE_DEPS] } }),
    tailwindcss(),
    tanstackStart(),
    viteReact(),
  ],
})

export default config

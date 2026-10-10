import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/ws': {
        target: 'ws://localhost:8081',
        ws: true,
        changeOrigin: true
      },
      '/api': {
        target: 'http://localhost:8081',
        changeOrigin: true
      }
    }
  }
})

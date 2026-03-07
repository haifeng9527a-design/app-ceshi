import { defineConfig } from 'vite';

const port = parseInt(process.env.PORT || '5174', 10);
const previewPort = parseInt(process.env.PREVIEW_PORT || '4174', 10);

export default defineConfig({
  server: {
    host: '0.0.0.0',
    port,
  },
  preview: {
    host: '0.0.0.0',
    port: previewPort,
  },
});

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

// Two pages, one bundle: the control panel at / and the installer at /setup/.
export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        ui: resolve(__dirname, "index.html"),
        setup: resolve(__dirname, "setup/index.html"),
      },
    },
  },
});

import { defineConfig, mergeConfig } from "vite";
import base from "./vite.config";

// Separate loopback-only preview: leaves the original UI/API ports untouched.
export default mergeConfig(base, defineConfig({
  server: { host: "127.0.0.1", port: 5177, strictPort: true,
    proxy: { "/api/demo": "http://127.0.0.1:8081" } },
}));

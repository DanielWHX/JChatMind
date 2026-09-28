import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  workers: 1,
  use: { baseURL: "http://127.0.0.1:5176", channel: process.env.PLAYWRIGHT_CHANNEL ?? "chrome", trace: "retain-on-failure" },
  webServer: { command: "npm run preview -- --host 127.0.0.1 --port 5176 --strictPort", url: "http://127.0.0.1:5176/demo", reuseExistingServer: false },
});

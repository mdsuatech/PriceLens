import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/browser",
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  use: {
    actionTimeout: 10_000,
    baseURL: "http://127.0.0.1:4178/PriceLens/",
    viewport: { width: 390, height: 844 },
    permissions: ["camera"],
    launchOptions: {
      executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
      args: [
        "--use-fake-device-for-media-stream",
        "--use-fake-ui-for-media-stream",
      ],
    },
  },
  webServer: {
    command: "npm run preview -- --port 4178 --strictPort",
    env: { PAGES_BASE: "/PriceLens/" },
    url: "http://127.0.0.1:4178/PriceLens/",
    reuseExistingServer: false,
  },
});

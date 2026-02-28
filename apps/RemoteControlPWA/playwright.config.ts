import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  expect: {
    timeout: 8_000
  },
  fullyParallel: false,
  retries: 0,
  reporter: [
    ["list"],
    ["html", { outputFolder: "output/playwright/report", open: "never" }]
  ],
  outputDir: "output/playwright/test-results",
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    serviceWorkers: "block"
  },
  webServer: {
    command: "python3 -m http.server 4173",
    cwd: __dirname,
    url: "http://127.0.0.1:4173",
    reuseExistingServer: true,
    timeout: 30_000
  },
  projects: [
    {
      name: "iphone-webkit",
      use: {
        ...devices["iPhone 14"],
        browserName: "webkit",
        colorScheme: "light"
      }
    },
    {
      name: "android-chrome",
      use: {
        ...devices["Pixel 7"],
        browserName: "chromium",
        colorScheme: "dark"
      }
    }
  ]
});

import { defineConfig } from "@playwright/test";
import path from "path";

const PERSISTENT_PROFILE = path.join(process.env.HOME || "", ".auto", "test");

export default defineConfig({
  testDir: "./e2e",
  timeout: 60000,
  use: {
    headless: false,
    actionTimeout: 30000,
  },
  projects: [
    {
      name: "chromium-persistent",
      use: {
        browserName: "chromium",
        launchOptions: {
          args: [
            `--user-data-dir=${PERSISTENT_PROFILE}`,
            "--disable-dev-shm-usage",
            "--no-sandbox",
          ],
        },
      },
    },
  ],
});

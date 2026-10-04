import { test, expect, chromium } from "@playwright/test";
import path from "path";
import os from "os";

// 获取扩展程序路径
const EXTENSION_PATH = path.join(__dirname, "..", ".output", "chrome-mv3");
// 使用持久化配置目录（符合 Target.md 要求）
const PERSISTENT_PROFILE = path.join(os.homedir(), ".auto", "test");

test.describe("Grap Page Extension - 阶段 2: 悬浮组件注入", () => {
  let context: any;
  let page: any;

  test.beforeAll(async () => {
    // 启动 Chromium 并加载扩展程序
    // 使用持久化 Profile 确保上下文连续性
    const browser = await chromium.launchPersistentContext(PERSISTENT_PROFILE, {
      headless: false,
      args: [
        `--disable-extensions-except=${EXTENSION_PATH}`,
        `--load-extension=${EXTENSION_PATH}`,
        "--disable-dev-shm-usage",
        "--no-sandbox",
      ],
    });

    page = browser.pages()[0] || (await browser.newPage());
  });

  test.afterAll(async () => {
    await context?.close();
  });

  test("页面右下角应存在悬浮按钮组件", async () => {
    // 访问测试页面
    await page.goto("https://example.com", { waitUntil: "networkidle" });

    // 等待悬浮组件加载
    const floatingButton = page.locator("#grap-page-floating-btn");

    // 验证组件存在且可见
    await expect(floatingButton).toBeVisible({ timeout: 5000 });
  });

  test("悬浮按钮应固定在页面右下角", async () => {
    await page.goto("https://example.com", { waitUntil: "networkidle" });

    const floatingButton = page.locator("#grap-page-floating-btn");

    // 获取元素位置和样式
    const style = await floatingButton.evaluate((el: HTMLElement) => {
      const styles = window.getComputedStyle(el);
      return {
        position: styles.position,
        bottom: styles.bottom,
        right: styles.right,
      };
    });

    // 验证固定定位
    expect(style.position).toBe("fixed");
    expect(parseInt(style.bottom)).toBeGreaterThan(0);
    expect(parseInt(style.right)).toBeGreaterThan(0);
  });
});

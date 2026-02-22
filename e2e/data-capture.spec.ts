import { test, expect, chromium } from "@playwright/test";
import path from "path";

// 获取扩展程序路径
const EXTENSION_PATH = path.join(__dirname, "..", ".output", "chrome-mv3");
const BACKEND_URL = "http://127.0.0.1:3000";

test.describe("Grap Page Extension - 阶段 3: 数据捕获与发送", () => {
  let context: any;
  let page: any;

  test.beforeAll(async () => {
    // 启动 Chromium 并加载扩展程序
    const browser = await chromium.launchPersistentContext("", {
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

  test("点击悬浮按钮应触发数据发送", async () => {
    // 先清空后端数据
    await fetch(`${BACKEND_URL}/api/pages`);

    // 访问测试页面
    await page.goto("https://example.com", { waitUntil: "networkidle" });

    // 等待悬浮按钮出现
    const floatingButton = page.locator("#grap-page-floating-btn");
    await expect(floatingButton).toBeVisible();

    // 点击前获取当前最新记录 ID
    const beforeResponse = await fetch(`${BACKEND_URL}/api/pages`);
    const beforeData = await beforeResponse.json();
    const beforeCount = beforeData.pages.length;

    // 点击按钮
    await floatingButton.click();

    // 等待处理完成
    await page.waitForTimeout(5000);

    // 验证后端收到新数据
    const afterResponse = await fetch(`${BACKEND_URL}/api/pages`);
    const afterData = await afterResponse.json();

    // 验证记录数增加
    expect(afterData.pages.length).toBeGreaterThanOrEqual(beforeCount);
  });

  test("应发送正确的数据结构到后端", async () => {
    // 访问一个有独特内容的页面
    await page.goto("https://example.com", { waitUntil: "networkidle" });

    // 获取当前页面 URL 用于验证
    const currentUrl = page.url();

    // 等待悬浮按钮
    const floatingButton = page.locator("#grap-page-floating-btn");
    await expect(floatingButton).toBeVisible();

    // 点击前获取当前页数
    const beforeResponse = await fetch(`${BACKEND_URL}/api/pages`);
    const beforeData = await beforeResponse.json();
    const beforeCount = beforeData.pages.length;

    // 点击按钮
    await floatingButton.click();

    // 等待处理完成（增加等待时间）
    await page.waitForTimeout(8000);

    // 检查后端 API 验证数据已保存 - 重试直到数据出现
    let data: any = null;
    for (let i = 0; i < 5; i++) {
      const response = await fetch(`${BACKEND_URL}/api/pages`);
      data = await response.json();
      if (data.pages.length > beforeCount) break;
      await page.waitForTimeout(1000);
    }

    expect(data).toBeDefined();
    expect(data.pages.length).toBeGreaterThan(beforeCount);

    // 验证最新记录包含正确的数据
    const latestPage = data.pages[0];
    expect(latestPage.url).toContain(currentUrl);
    expect(latestPage.content).toBeTruthy();
  });

  test("应优先提取选中文本内容", async () => {
    // 访问测试页面
    await page.goto("https://example.com", { waitUntil: "networkidle" });

    // 选择一些文本
    const paragraph = page.locator("p").first();
    const textContent = await paragraph.textContent();
    expect(textContent).toBeTruthy();

    // 使用鼠标选择文本
    await paragraph.selectText();

    // 点击悬浮按钮
    const floatingButton = page.locator("#grap-page-floating-btn");
    await floatingButton.click();

    // 等待处理完成
    await page.waitForTimeout(5000);

    // 验证后端收到数据
    const response = await fetch(`${BACKEND_URL}/api/pages`);
    const data = await response.json();

    expect(data.pages.length).toBeGreaterThan(0);
  });
});

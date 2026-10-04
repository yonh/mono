#!/usr/bin/env node
/**
 * 测试脚本 - 模拟浏览器插件发送请求到后端
 * 使用方法：node test/e2e-test.js
 */

async function makeRequest(url, options = {}) {
  const response = await fetch(url, options);
  const data = await response.json();
  return {
    statusCode: response.status,
    headers: Object.fromEntries(response.headers.entries()),
    data,
  };
}

const TEST_DATA = {
  url: "https://github.com/example/repo",
  title: "Example Repository - GitHub",
  content: `
    This is a sample repository content.
    The purpose is to test the Grap Page extension.

    Features:
    - Extract page content
    - Send to local backend
    - Backend forwards to LLM API

    This test verifies the complete data flow from browser to backend.
  `,
  timestamp: new Date().toISOString(),
};

async function runTest() {
  console.log("🧪 Grap Page E2E 测试\n");
  console.log("=".repeat(50));

  // 测试 1: 健康检查
  console.log("\n测试 1: 健康检查...");
  try {
    const healthResult = await makeRequest("http://127.0.0.1:3000/health");
    console.log(`状态码：${healthResult.statusCode}`);
    console.log(`响应:`, JSON.stringify(healthResult.data, null, 2));

    if (healthResult.statusCode === 200 && healthResult.data.status === "ok") {
      console.log("✅ 健康检查通过");
    } else {
      console.log("❌ 健康检查失败");
      process.exit(1);
    }
  } catch (error) {
    console.log("❌ 健康检查失败:", error.message);
    console.log("请确保后端服务正在运行：npm run server");
    process.exit(1);
  }

  // 测试 2: 保存页面数据
  console.log("\n测试 2: 保存页面数据...");
  try {
    const saveResult = await makeRequest("http://127.0.0.1:3000/api/save", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(TEST_DATA),
    });
    console.log(`状态码：${saveResult.statusCode}`);
    console.log(`响应:`, JSON.stringify(saveResult.data, null, 2));

    if (saveResult.statusCode === 200 && saveResult.data.success === true) {
      console.log("✅ 数据保存成功");
      console.log(`   记录 ID: ${saveResult.data.id}`);
    } else {
      console.log("❌ 数据保存失败");
    }
  } catch (error) {
    console.log("❌ 数据保存失败:", error.message);
  }

  // 测试 3: 获取已保存的数据
  console.log("\n测试 3: 获取已保存的数据...");
  try {
    const pagesResult = await makeRequest("http://127.0.0.1:3000/api/pages");
    console.log(`状态码：${pagesResult.statusCode}`);

    if (pagesResult.statusCode === 200 && Array.isArray(pagesResult.data.pages)) {
      console.log(`✅ 获取成功，共 ${pagesResult.data.pages.length} 条记录`);
      if (pagesResult.data.pages.length > 0) {
        const latest = pagesResult.data.pages[0];
        console.log(`   最新记录：${latest.title}`);
        console.log(`   URL: ${latest.url}`);
        console.log(`   内容长度：${latest.contentLength} 字符`);
        if (latest.llmAnalysis) {
          console.log(`   LLM 分析：${latest.llmAnalysis.slice(0, 100)}...`);
        }
      }
    }
  } catch (error) {
    console.log("❌ 获取数据失败:", error.message);
  }

  console.log("\n" + "=".repeat(50));
  console.log("🎉 测试完成！\n");
}

runTest().catch(console.error);

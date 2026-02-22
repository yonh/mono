import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import * as fs from "fs";
import * as path from "path";

const app = new Hono();

// 中间件
app.use("*", logger());
app.use(
  "*",
  cors({
    origin: "*",
    allowMethods: ["GET", "POST", "OPTIONS"],
    allowHeaders: ["Content-Type"],
  }),
);

// 数据存储路径
const DATA_DIR = path.join(process.cwd(), "data");
const LOG_FILE = path.join(DATA_DIR, "pages.log");

// 确保数据目录存在
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 健康检查
app.get("/health", (c) => {
  return c.json({ status: "ok", timestamp: new Date().toISOString() });
});

// 保存页面数据
app.post("/api/save", async (c) => {
  try {
    const body = await c.req.json();
    const { url, title, content, timestamp } = body;

    // 验证必填字段
    if (!url || !title || !content) {
      return c.json(
        {
          success: false,
          error: "Missing required fields: url, title, content",
        },
        400,
      );
    }

    // 构建日志条目
    const logEntry = {
      id: Date.now(),
      url,
      title,
      content,
      timestamp: timestamp || new Date().toISOString(),
      receivedAt: new Date().toISOString(),
    };

    // 追加到日志文件
    const logLine = JSON.stringify(logEntry) + "\n";
    fs.appendFileSync(LOG_FILE, logLine, "utf-8");

    console.log("===== 新数据接收 =====");
    console.log(`URL: ${url}`);
    console.log(`标题：${title}`);
    console.log(`内容长度：${content.length} 字符`);
    console.log(`时间：${logEntry.timestamp}`);
    console.log("===================");

    return c.json({
      success: true,
      id: logEntry.id,
      message: "数据已保存",
    });
  } catch (error) {
    console.error("保存数据失败:", error);
    return c.json(
      {
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      },
      500,
    );
  }
});

// 获取已保存的数据
app.get("/api/pages", (c) => {
  try {
    if (!fs.existsSync(LOG_FILE)) {
      return c.json({ pages: [] });
    }

    const content = fs.readFileSync(LOG_FILE, "utf-8");
    const pages = content
      .trim()
      .split("\n")
      .filter(Boolean)
      .map((line) => JSON.parse(line));

    return c.json({ pages: pages.reverse() }); // 最新的在前
  } catch (error) {
    console.error("读取数据失败:", error);
    return c.json({ pages: [], error: "Failed to read data" });
  }
});

// 启动服务器
const port = 3000;

console.log(`🚀 服务器启动在 http://localhost:${port}`);
console.log(`📁 数据保存到：${LOG_FILE}`);

// 使用 Bun 或 Node.js 启动服务器
if (typeof Bun !== "undefined") {
  Bun.serve({ port, fetch: app.fetch });
} else {
  // Node.js - 使用 Hono 的 serve 方法
  const { serve } = await import("@hono/node-server");
  serve({
    fetch: app.fetch,
    port,
  });
}

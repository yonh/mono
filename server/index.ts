import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import * as fs from "fs";
import * as path from "path";
import * as yaml from "js-yaml";

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

// 读取 YAML 配置
const CONFIG_PATH = path.join(process.cwd(), "given_llm_api.yaml");
let llmConfig: any = {};

try {
  const yamlContent = fs.readFileSync(CONFIG_PATH, "utf-8");
  llmConfig = yaml.load(yamlContent) || {};
  console.log("📋 LLM 配置已加载:", llmConfig);
} catch (error) {
  console.warn("⚠️ 无法读取 LLM 配置文件，使用默认配置");
  llmConfig = {
    apikey: "",
    doc_url: "https://help.aliyun.com/zh/model-studio/coding-plan",
  };
}

// 数据存储路径
const DATA_DIR = path.join(process.cwd(), "data");
const LOG_FILE = path.join(DATA_DIR, "pages.log");

// 确保数据目录存在
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// 健康检查
app.get("/health", (c) => {
  return c.json({
    status: "ok",
    timestamp: new Date().toISOString(),
    llmConfigured: !!llmConfig.apikey,
  });
});

// 调用 LLM API
async function callLLMApi(prompt: string, context?: string) {
  const apiKey = llmConfig.apikey;

  if (!apiKey || !apiKey.startsWith("sk-")) {
    throw new Error("无效 API key");
  }

  // 阿里云百炼标准 API 端点
  const apiUrl =
    "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation";

  // 阿里云百炼标准请求格式
  const requestBody = {
    model: "qwen-plus",
    input: {
      messages: [
        {
          role: "system",
          content:
            "你是一个网页内容分析助手。用户会提供网页的标题、URL 和内容，请简要总结内容要点。",
        },
        {
          role: "user",
          content: `请分析以下网页内容:\n\n标题：${context?.split("\n")[0] || "未知"}\nURL: ${context?.split("\n")[1] || "未知"}\n\n内容摘要：${prompt}`,
        },
      ],
    },
    parameters: {
      result_format: "message",
    },
  };

  try {
    const response = await fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
        "X-DashScope-SSE": "disable",
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`LLM API 返回错误：${response.status} - ${errorText}`);
    }

    const result = await response.json();
    console.log("LLM 原始响应:", JSON.stringify(result).slice(0, 200));
    return {
      success: true,
      content: result.output?.choices?.[0]?.message?.content || "无响应内容",
      usage: result.output?.usage,
    };
  } catch (error) {
    console.error("调用 LLM API 失败:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : "未知错误",
      fallback: true,
    };
  }
}

// 保存页面数据并调用 LLM
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

    console.log("===== 新数据接收 =====");
    console.log(`URL: ${url}`);
    console.log(`标题：${title}`);
    console.log(`内容长度：${content.length} 字符`);

    // 调用 LLM API (如果有配置)
    let llmResult: any = null;
    if (llmConfig.apikey) {
      console.log("🤖 正在调用 LLM API...");
      const contentPreview = content.slice(0, 500); // 限制长度
      llmResult = await callLLMApi(contentPreview, `${title}\n${url}`);

      if (llmResult.success) {
        console.log("🤖 LLM 响应:", llmResult.content);
      } else {
        console.log("⚠️ LLM 调用失败，但继续保存数据");
      }
    } else {
      console.log("⚠️ 未配置 LLM API key，跳过分析");
    }

    // 构建日志条目
    const logEntry = {
      id: Date.now(),
      url,
      title,
      content,
      contentLength: content.length,
      timestamp: timestamp || new Date().toISOString(),
      receivedAt: new Date().toISOString(),
      llmAnalysis: llmResult?.success ? llmResult.content : null,
    };

    // 追加到日志文件
    const logLine = JSON.stringify(logEntry) + "\n";
    fs.appendFileSync(LOG_FILE, logLine, "utf-8");

    console.log("===================");

    return c.json({
      success: true,
      id: logEntry.id,
      message: "数据已保存",
      llmResult: llmResult?.success
        ? {
            summary: llmResult.content,
            usage: llmResult.usage,
          }
        : null,
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
console.log(`🤖 LLM API: ${llmConfig.apikey ? "已配置" : "未配置"}`);

// 使用异步方式启动服务器
(async () => {
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
})();

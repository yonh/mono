# Grap Page - 网页原义提取器

基于 WXT 的浏览器插件与本地后端服务 MVP，实现网页原义数据的无损提取、传输与存储，并支持对接本地大模型 API。

## 项目结构

```
grap_page/
├── src/
│   └── entrypoints/
│       ├── background.ts    # 后台脚本 - 右键菜单和网络请求
│       ├── content.ts       # 内容脚本
│       └── popup/
│           ├── index.html   # Popup 界面
│           └── main.ts      # Popup 逻辑
├── server/
│   └── index.ts             # 本地后端服务 (带 LLM 集成)
├── test/
│   └── e2e-test.js          # 端到端测试脚本
├── data/
│   └── pages.log            # 数据存储文件
├── given_llm_api.yaml       # LLM API 配置
├── package.json
├── wxt.config.ts
└── tsconfig.json
```

## 功能特性

- **右键菜单提取**: 右键点击页面选择"提取页面原义"
- **Popup 界面**: 点击插件图标提取当前页面
- **选区支持**: 如果有选中文本则提取选区，否则提取整个页面
- **无损提取**: 使用 `innerText` 保留原始文本格式
- **本地存储**: 数据保存到 `data/pages.log`
- **LLM 集成**: 自动调用阿里云百炼 API 进行内容分析 (需配置 API key)

## 安装依赖

```bash
npm install
```

## 使用方法

### 1. 配置 LLM API (可选)

编辑 `given_llm_api.yaml`:

```yaml
apikey: sk-your-api-key-here
doc_url: https://help.aliyun.com/zh/model-studio/coding-plan
```

### 2. 启动后端服务

```bash
npm run server
# 或
npx tsx server/index.ts
```

服务启动在 `http://localhost:3000`

### 3. 运行测试

```bash
node test/e2e-test.js
```

### 4. 构建插件

```bash
npm run build
```

在 Chrome 中：
1. 访问 `chrome://extensions/`
2. 启用"开发者模式"
3. 点击"加载已解压的扩展程序"
4. 选择 `.output/chrome-mv3` 目录

### 5. 使用插件

- **右键菜单**: 在任意页面右键，选择"提取页面原义"
- **Popup**: 点击插件图标，点击"提取当前页面"按钮

## API 端点

| 端点 | 方法 | 描述 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/api/save` | POST | 保存页面数据，调用 LLM API |
| `/api/pages` | GET | 获取已保存的数据 |

### POST /api/save

请求体：
```json
{
  "url": "https://example.com",
  "title": "Example Page",
  "content": "Page content...",
  "timestamp": "2026-02-22T18:00:00.000Z"
}
```

响应：
```json
{
  "success": true,
  "id": 1234567890,
  "message": "数据已保存",
  "llmResult": {
    "summary": "LLM 分析结果...",
    "usage": {...}
  }
}
```

## 技术栈

- **插件**: WXT (Manifest V3)
- **后端**: Hono (轻量级 HTTP 框架)
- **LLM**: 阿里云百炼 (通义千问)
- **运行时**: Node.js

## 注意事项

1. `sk-sp-` 前缀的 API key 是阿里云 Coding Plan 服务的特殊 token，可能需要特定的调用方式
2. 如 LLM API 调用失败，数据仍会保存到本地日志文件
3. CORS 已配置，允许跨域请求

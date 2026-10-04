import { defineConfig } from "wxt";

export default defineConfig({
  srcDir: "src",
  manifest: {
    name: "Grap Page - 网页原义提取器",
    description: "无损提取网页原义数据并发送至本地后端",
    version: "1.0.0",
    permissions: ["contextMenus", "storage", "tabs", "scripting"],
    host_permissions: [
      "http://localhost:3000/*",
      "http://127.0.0.1:3000/*",
      "<all_urls>",
    ],
  },
});

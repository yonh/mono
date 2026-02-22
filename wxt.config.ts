import { defineConfig } from 'wxt';

export default defineConfig({
  srcDir: 'src',
  manifest: {
    name: 'Grap Page - 网页原义提取器',
    description: '无损提取网页原义数据并发送至本地后端',
    version: '1.0.0',
    permissions: ['contextMenus', 'storage'],
    host_permissions: ['http://localhost:3000/*'],
  },
});

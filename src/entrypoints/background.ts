// 背景脚本 - 处理右键菜单和网络请求
export default defineBackground({
  type: 'module',
  main() {
    // 创建右键菜单
    browser.runtime.onInstalled.addListener(() => {
      browser.contextMenus.create({
        id: 'grab-page-content',
        title: '提取页面原义',
        contexts: ['page'],
      });
    });

    // 监听右键菜单点击
    browser.contextMenus.onClicked.addListener(async (info, tab) => {
      if (info.menuItemId === 'grab-page-content' && tab?.id) {
        try {
          // 执行内容脚本获取页面数据
          const results = await browser.scripting.executeScript({
            target: { tabId: tab.id },
            func: grabPageContent,
          });

          const pageData = results[0]?.result;
          if (pageData) {
            // 发送到本地后端
            const response = await fetch('http://localhost:3000/api/save', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(pageData),
            });

            if (response.ok) {
              const result = await response.json();
              console.log('数据发送成功:', result);

              // 显示通知
              await browser.notifications.create({
                type: 'basic',
                title: '提取成功',
                message: `已发送 ${pageData.title} 到本地后端`,
              });
            } else {
              throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
          }
        } catch (error) {
          console.error('提取页面内容失败:', error);
          browser.notifications.create({
            type: 'basic',
            title: '提取失败',
            message: error instanceof Error ? error.message : '未知错误',
          });
        }
      }
    });
  },
});

// 页面内容抓取函数（在页面上下文中执行）
function grabPageContent() {
  // 获取用户选区文本，如果没有选区则获取整个页面文本
  const selection = window.getSelection();
  const content = selection && selection.toString().trim()
    ? selection.toString()
    : document.body.innerText;

  return {
    url: window.location.href,
    title: document.title,
    content: content,
    timestamp: new Date().toISOString(),
  };
}

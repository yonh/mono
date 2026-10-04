// 内容脚本 - 注入悬浮组件
export default defineContentScript({
  matches: ['<all_urls>'],
  main() {
    console.log('Grap Page content script loaded');

    // 创建悬浮按钮
    function createFloatingButton() {
      // 检查是否已存在
      if (document.getElementById('grap-page-floating-btn')) {
        return;
      }

      const button = document.createElement('div');
      button.id = 'grap-page-floating-btn';
      button.textContent = '📄 提取页面';
      button.setAttribute('role', 'button');
      button.setAttribute('tabindex', '0');
      button.setAttribute('aria-label', '提取页面原义');

      // 样式 - 固定在右下角
      Object.assign(button.style, {
        position: 'fixed',
        bottom: '20px',
        right: '20px',
        zIndex: '999999',
        padding: '12px 20px',
        backgroundColor: '#007bff',
        color: 'white',
        borderRadius: '8px',
        cursor: 'pointer',
        fontFamily: 'system-ui, sans-serif',
        fontSize: '14px',
        fontWeight: '500',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.15)',
        transition: 'all 0.2s ease',
        userSelect: 'none',
      });

      // 悬停效果
      button.addEventListener('mouseenter', () => {
        button.style.backgroundColor = '#0056b3';
        button.style.transform = 'scale(1.05)';
      });

      button.addEventListener('mouseleave', () => {
        button.style.backgroundColor = '#007bff';
        button.style.transform = 'scale(1)';
      });

      // 点击事件 - 发送消息给 background
      button.addEventListener('click', async () => {
        button.textContent = '⏳ 提取中...';
        button.style.backgroundColor = '#6c757d';

        try {
          // 获取页面数据（不修改 DOM）
          const pageData = {
            url: window.location.href,
            title: document.title,
            content: window.getSelection()?.toString().trim() || document.body.innerText,
            timestamp: new Date().toISOString(),
          };

          // 发送到后端
          const response = await fetch('http://localhost:3000/api/save', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(pageData),
          });

          if (response.ok) {
            button.textContent = '✅ 成功!';
            button.style.backgroundColor = '#28a745';
            console.log('Grap Page: 数据发送成功', pageData);
          } else {
            throw new Error(`HTTP ${response.status}`);
          }
        } catch (error) {
          button.textContent = '❌ 失败';
          button.style.backgroundColor = '#dc3545';
          console.error('Grap Page: 提取失败', error);
        }

        // 2 秒后恢复
        setTimeout(() => {
          button.textContent = '📄 提取页面';
          button.style.backgroundColor = '#007bff';
        }, 2000);
      });

      document.body.appendChild(button);
      console.log('Grap Page: 悬浮按钮已注入');
    }

    // DOM 加载完成后注入
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', createFloatingButton);
    } else {
      createFloatingButton();
    }
  },
});

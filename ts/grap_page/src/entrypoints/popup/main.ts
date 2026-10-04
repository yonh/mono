// Popup 脚本
document.getElementById('grabBtn')?.addEventListener('click', async () => {
  const statusEl = document.getElementById('status');
  if (statusEl) statusEl.textContent = '正在提取...';

  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id) throw new Error('无法获取当前标签页');

    const results = await browser.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => ({
        url: window.location.href,
        title: document.title,
        content: window.getSelection()?.toString() || document.body.innerText,
        timestamp: new Date().toISOString(),
      }),
    });

    const pageData = results[0]?.result;
    const response = await fetch('http://localhost:3000/api/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(pageData),
    });

    if (response.ok) {
      if (statusEl) {
        statusEl.textContent = '✓ 发送成功!';
        statusEl.className = 'success';
      }
    } else {
      throw new Error(`HTTP ${response.status}`);
    }
  } catch (error) {
    if (statusEl) {
      statusEl.textContent = '✗ 失败：' + (error as Error).message;
      statusEl.className = 'error';
    }
  }
});

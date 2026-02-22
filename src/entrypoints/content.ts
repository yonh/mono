// 内容脚本
export default defineContentScript({
  matches: ['<all_urls>'],
  main() {
    console.log('Grap Page content script loaded');
  },
});

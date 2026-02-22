---
active: true
iteration: 1
max_iterations: 50
completion_promise: "COMPLETE"
started_at: "2026-02-22T18:53:01Z"
---


请基于 TDD (测试驱动开发) 模式开发一个 WXT 浏览器插件与本地后端，严格遵循以下规范：
1. **自动化测试**: 必须使用 Playwright 进行真实环境 E2E 测试。
2. **UI 交互**: 禁止使用 Popup，必须在页面右下角注入固定悬浮组件（Button/Panel），供自动化脚本定位点击。
3. **Git 提交**: 每完成一个功能模块且测试通过后，必须执行 git add 和 git commit，记录当前进度。

### 任务迭代计划
请按顺序执行以下阶段，每个阶段结束后必须 **提交 Git 代码**：

**阶段 1: 基础架构与测试环境**
- 初始化 WXT 项目与后端项目结构。
- 配置 Playwright 测试环境（支持加载插件）。
- 创建占位测试文件，确保测试框架能运行。
- **提交代码**: chore: init project structure and test env

**阶段 2: 前端组件注入 (TDD)**
- **测试**: 编写用例验证页面右下角是否存在指定 ID 的悬浮组件。
- **实现**: 编写 Content Script 逻辑，注入组件。
- **验证**: 运行测试直至通过。
- **提交代码**: feat: inject floating component via content script

**阶段 3: 数据捕获与发送 (TDD)**
- **测试**: 编写用例模拟点击组件，验证是否向后端发送了包含 url, title, content (原义) 的正确请求。
- **实现**: 实现点击事件监听与数据抓取逻辑，对接后端接口。
- **验证**: 运行测试直至通过。
- **提交代码**: feat: implement data capture and transmission

**阶段 4: 后端服务与 LLM 对接 (TDD)**
- **测试**: 编写用例启动后端，模拟请求，验证是否读取  并成功调用 LLM API。
- **实现**: 实现后端服务，处理 CORS，转发数据。
- **验证**: 运行测试直至通过。
- **提交代码**: feat: implement backend service and llm integration

**阶段 5: 端到端联调**
- 运行完整 Playwright 测试套件，确保全链路打通。
- 修复任何遗留 Bug。
- **提交代码**: test: e2e test passing and code cleanup

### 核心约束
- **数据原则**: 严禁修改页面 DOM，仅读取。
- **真实测试**: 必须真实运行浏览器与网络请求，不得仅使用 Mock。
- **提交规范**: 每个阶段成功后必须提交，不得跳过。

当所有阶段完成且 E2E 测试全绿，输出：
<COMPLETE>


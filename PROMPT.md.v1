/ralph-loop:ralph-loop "
### 任务目标
开发基于 WXT 的浏览器插件 MVP 与本地后端，采用 TDD (测试驱动开发) 模式，实现网页内容无损传递并对接本地大模型。

### 核心原则
1. **架构约束**: 必须通过 Content Script 在页面右下角渲染悬浮组件（严禁 Popup），必须使用 Playwright 进行真实环境 E2E 测试。
2. **数据约束**: 严禁修改 DOM，仅读取页面内容保持原义。
3. **流程约束**: 严格遵循 TDD（先写测试-再写实现），每个功能阶段测试通过后必须提交 Git 代码。
4. **Prompt 文件安全**: 允许对代码实现细节进行自由优化和重构。但如果涉及到对 `PROMPT.md` 文件的修改，**绝对禁止**删除、覆盖或大幅修改上述核心原则与任务规划。每次修改 `PROMPT.md` 前需重点审核是否偏离核心需求。

### 任务迭代计划
请按顺序执行以下阶段：

**阶段 1: 环境搭建**
- 初始化 WXT (TypeScript) 与后端项目结构。
- 配置 Playwright 测试环境。
- **测试**: 验证测试框架可正常运行。
- **Git Commit**: "chore: init project and playwright env"

**阶段 2: UI 组件注入**
- **测试**: 编写 E2E 用例，验证页面右下角存在指定 ID 的悬浮组件。
- **实现**: Content Script 逻辑，注入组件。
- **Git Commit**: "feat: inject floating component"

**阶段 3: 数据采集与传输**
- **测试**: 编写 E2E 用例，模拟点击组件，验证是否向后端发送包含 url, title, content 的正确 JSON 请求。
- **实现**: 点击事件监听、数据抓取、网络请求逻辑。
- **Git Commit**: "feat: capture and transmit data"

**阶段 4: 后端服务与 LLM 对接**
- **测试**: 编写测试验证后端接收请求，读取 `given_llm_api.yaml`，成功调用本地 LLM API 并返回。
- **实现**: 后端服务、跨域处理、LLM 对接逻辑。
- **Git Commit**: "feat: backend service and llm integration"

**阶段 5: 全链路联调**
- 运行完整 Playwright 测试套件，确保无红字报错。
- 修复潜在 Bug。
- **Git Commit**: "test: e2e pass and cleanup"

### 执行要求
- 保持代码简洁，MVP 优先。
- 每次迭代必须先运行测试，根据结果修改代码。

当所有阶段完成且 E2E 测试全绿，输出：
<COMPLETE>
" --completion-promise "COMPLETE" --max-iterations 50

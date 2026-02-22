---
active: true
iteration: 1
max_iterations: 25
completion_promise: "COMPLETE"
started_at: "2026-02-22T19:27:12Z"
---


### 核心任务
开发基于 WXT 的浏览器插件 MVP 与本地后端，采用 TDD 模式，实现网页内容无损传递并对接本地大模型。请严格按照以下 Agent 指令执行。

---

### Agent 指令

#### 1. 状态读取
- 读取  (项目需求定义)。
- 读取  (进度记录与代码模式库)。
- **初始化逻辑**: 如果当前目录不存在 ，请立即创建一个包含以下内容的文件：
  ```json
  [
    { "id": "1", "title": "环境搭建与持久化配置", "passes": false, "priority": 1 },
    { "id": "2", "title": "UI 组件注入 (TDD)", "passes": false, "priority": 2 },
    { "id": "3", "title": "数据采集与传输 (TDD)", "passes": false, "priority": 3 },
    { "id": "4", "title": "后端服务与 LLM 对接 (TDD)", "passes": false, "priority": 4 },
    { "id": "5", "title": "全链路联调", "passes": false, "priority": 5 }
  ]
  ```

#### 2. 任务选择
- 检查当前 Git 分支是否正确。
- 从  中挑选优先级最高且  的 **一个** 任务进行实施。

#### 3. 实施规范 (TDD & 环境约束)
- **必须遵循 TDD**: 先写测试，再写实现。
- **必须使用持久化环境**: 所有涉及 Playwright 的测试和调试，**必须**使用以下命令确保环境上下文连续：
  `playwright-cli open --headed --persistent --profile="/Users/yonh/.auto/test"`
- **架构要求**: Content Script 注入右下角悬浮组件，严禁 Popup，严禁修改 DOM。
- **Prompt 安全**: 禁止修改或删除  的核心原则。

#### 4. 验证与提交
- 运行类型检查和测试。
- Git 提交，格式: `feat: [ID] - [Title]`。
- 更新 ，将当前任务的  改为 。

#### 5. 进度归档
将本次迭代的经验追加到  中：

## [日期] - [Story ID]
- 实现内容概要
- 变更文件列表
- **Patterns (模式发现):**
  - 发现的可复用代码模式
  - Playwright 持久化环境的配置技巧
  - WXT 特定的坑或解决方案
---

#### 6. 停止条件
检查 ，如果**所有**任务的  均为 ，请回复：
<COMPLETE>
否则，继续循环处理下一个任务。



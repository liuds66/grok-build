# AI Dev One Route 2 v0.5 Phase 2.5

## LIVE MODEL BROWSER ACCEPTANCE GATE

验收日期：2026-08-18
结果：**FAIL（保留唯一 P2）**

本报告记录真实模型、真实应用运行时、真实临时 Git 项目和真实 WKWebView 验证结果。没有把未完成的桌面任务改写成成功。

## 1. 基线与产物

| 项目 | 实际值 |
|---|---|
| Branch | `v0.5-dev` |
| Commit（验收开始） | `f89ecb42e2bedbf7b38151d03fc8507ed0490edf` |
| 仓库绝对路径 | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座` |
| App 源码 | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/apps/nexus-desktop/Sources/NexusDesktop` |
| Rust 源码 | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/crates` |
| 安装 App | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/dist/Nexus.app` |
| Bundle ID | `cn.nexus.desktop` |
| Display Name | `AI Dev One` |
| App 文件名 | `Nexus.app`（兼容历史 Bundle/Keychain 名称） |
| App 可见版本 | `0.4.0-beta.1` |

本轮没有修改主仓库功能代码；当前主仓库 commit 仍为上述 SHA。

## 2. 模型与安全边界

- Provider：DeepSeek（OpenAI-compatible Chat Completions）。
- Model：`deepseek-v4-flash`。
- Endpoint：`https://api.deepseek.com`（报告不记录 API Key）。
- 凭据读取：使用既有 Keychain secure item `com.ai-dev-one.nexus.api-key` / `openai-coding`；通过进程内存或一次性环境继承传递，没有写入源码、fixture、任务 JSONL、截图 metadata 或报告。
- 完成后清除了临时读取文件、取消了 LaunchServices 环境变量、关闭了 App；没有修改或删除用户 Keychain 项。

## 3. 隔离项目与基线

测试项目：`/tmp/ai-dev-one-live-fixture.xWcP8Z`
技术栈：React / TypeScript / Vite 风格本地前端，包含页面、CSS、`tests/test.js` 和 Git 仓库。
初始 fixture commit：`12897c2`。为让开发服务器可被受管流程回收，fixture 的 `dev` 脚本在后续临时 commit `b428fe6` 中改为受控后台启动；该 commit 只存在于 `/tmp`，没有进入主仓库。

任务要求（未指定实现文件）：

> 把页面中的主要 Save 操作改成右上角固定操作按钮；桌面端保持清晰可见，移动端不能溢出或遮挡正文；运行测试并验证桌面和移动端浏览器布局；发现问题自行修复。

最终 fixture 工作树只留下一个预期修改：`styles.css`。`port.txt` 是服务器运行生成物，已移出 fixture，未计入 changed files。

## 4. 真实 Live Model 运行时任务

### 4.1 运行时层（headless Runtime）

- Session：`5a87b7f6-bd7d-4fb3-9c3d-1e5c2ea3e1fb`。
- 真实模型完成了项目读取、相关文件定位、CSS 修改、测试和最终检查。
- 事件证据：15 个 agent loop、22 个 `tool_started`、22 个 `tool_completed`、1 个 `turn_ended`；运行时 `shell.handle_prompt.done` 为 `ok=true`，总耗时约 144 秒。
- Changed file：`styles.css`。
- 真实 fixture 测试：`node tests/test.js` → `fixture tests passed`。
- 实际修复：移动端 media query 将 `.hero` 的右侧预留从 `0` 改为 `100px`，避免固定 Save 按钮覆盖标题内容。

### 4.2 Project Intelligence 与桌面 Agent UI 编排

桌面应用确实把 Project Intelligence bounded context 附加到了任务 prompt，内容包含：React/Vite 栈、`src/App.tsx` 的 `SaveAction`、`styles.css`、`package.json`、`tests/test.js` 等相关文件和测试。

桌面任务事务：`99cddcb0-8b5c-4a13-91a9-34711c51e50f`。真实观察结果：

- Architect 已进入并记录为 passed；
- Builder/工具读取阶段真实运行；
- 任务在输出最终 `end` 事件前持续停留在模型/工具循环；
- `fileChanges=[]`、`verification=[]`，没有进入 Browser Verification 和 Reviewer 完成路径；
- 事务最终为 `finalState=cancelled`（`finishedAt=2026-08-18T04:21:31Z`），不是 `completed`。

这不是浏览器验证器失败，而是桌面 Agent 编排任务在完成事件之前被停止。因此不能用 headless Runtime 的成功结果冒充同一桌面事务已完成。

## 5. 阶段结果

| 阶段 | 真实结果 | 证据 |
|---|---|---|
| Project Intelligence | PASS（上下文注入） | 桌面任务 prompt 中存在 bounded context；列出相关文件和测试 |
| Architect | PASS（已启动/通过） | 事务 pipeline 记录 Architect passed |
| Builder | PASS（Runtime 层真实修改） | headless live session 修改 `styles.css`；桌面事务自身未产生 fileChanges |
| Code Verification | PASS（fixture） | `node tests/test.js` 通过；桌面事务未到 Verification Gate |
| Browser Desktop | PASS | 真实 `BrowserVerificationService` / WKWebView，1440×900，截图/DOM/Console/Network/Layout 全通过 |
| Browser Mobile | PASS | 真实 `BrowserVerificationService` / WKWebView，390×844，截图/DOM/Console/Network/Layout 全通过 |
| Self Repair | 0 轮 | 首次浏览器验证已通过，不需要修复轮 |
| Reviewer | NOT REACHED | 桌面事务在最终 end 前取消，Reviewer 未完成 |
| Final task state | FAIL | 桌面事务 `cancelled`；headless Runtime 单独为 `ok=true`，不是同一事务 |

## 6. Browser Evidence

浏览器使用 macOS WebKit/WKWebView，URL 仅为受策略允许的 `http://localhost:4173/`。两个 viewport 均生成真实 `viewport.png` 和 `result.json`：

- Desktop 1440×900：`/Users/mac/Library/Application Support/Nexus/browser-verification/phase25-desktop/c1f00147-d3b9-406f-b3c0-d67628615c0d/viewport.png`
  - status `passed`
  - screenshots 1；console errors 0；page errors 0；failed requests 0；layout findings 0；instrumentation `true`
  - Save 按钮固定在右上角，正文没有被遮挡。
- Mobile 390×844：`/Users/mac/Library/Application Support/Nexus/browser-verification/phase25-mobile/890cbb83-7fd0-4cd2-b612-a3a85ee22369/viewport.png`
  - status `passed`
  - screenshots 1；console errors 0；page errors 0；failed requests 0；layout findings 0；instrumentation `true`
  - Save 按钮仍可见，标题和正文没有横向溢出或重叠。

截图由 `view_image` 复核，桌面和移动布局均符合任务目标。

## 7. 回归测试

### 项目回归

`bash scripts/test-nexus`：**82 通过，0 失败**。其中包含 Swift 类型检查、Project Intelligence、Browser Verification 契约与 localhost 视觉 E2E、签名/安装资源检查。

### 全部 CJS regression

24 个 `tests/*.cjs` 全部 **PASS，0 FAIL**，包括 Agent 状态机、Browser Verification、Checkpoint/Rollback、Core Recovery、Keychain、Policy、Project Intelligence、Resizable、Secret Redaction、Session、Task Transaction、Verification Gate、Workspace 等。

### Fixture

`node tests/test.js`：**PASS**。

## 8. 清理与 Secret Scan

- 浏览器验证结束后 `BrowserVerificationService.activeSession == nil`；受管 fixture server 数量为 0。
- 验收 App 已退出；`Nexus.app`、`nexus-agent`、fixture server 没有残留运行实例。
- 主仓库没有 build artifact、App bundle、临时 harness 或测试输出变更。
- `tests/secret-redaction.cjs`：PASS。
- 最终扫描覆盖主仓库（排除构建产物）、fixture 任务 JSONL、runtime logs、Task Transaction、Browser result metadata 和报告：没有发现真实 DeepSeek API Key、Bearer token 或 Authorization secret。源码中用于脱敏回归的合成 `sk-test` 字符串属于测试 fixture，不是真实凭据。

## 9. Gate 状态

| 优先级 | 数量 | 状态 |
|---|---:|---|
| P0 | 0 | 无数据丢失/安全绕过/残留进程问题 |
| P1 | 0 | Browser Verification 与 Project Intelligence 契约回归通过 |
| P2 | 1 | 桌面 Agent UI 任务未在同一 Task Transaction 内完成 `end → Browser → Reviewer → completed` |
| P3 | 0 | 无 |

P2 不能关闭。按 Gate 规则，本阶段应停止，不进入 Phase 3/GitHub Autonomous Loop。下一步应先定位桌面 Agent 任务未发出 `end` 事件的编排/运行时问题，再用同一安装 App 重新执行完整 acceptance；不应修改 Browser Verification 或 Project Intelligence 来掩盖这个结果。

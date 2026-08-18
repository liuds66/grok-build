# AI Dev One Route 2 v0.5 Phase 2

## Browser Visual Verification 实施报告

日期：2026-08-18
分支：`v0.5-dev`
Phase 1 基线：`e73b15a1ac3df501cfae0f32ad8f01a387830a24`
旧 v0.4.0-beta.1 tag 未修改；本阶段不创建 v0.5 tag。

本阶段只增加“本地前端运行 → 浏览器检查 → 证据 → Verifier/Reviewer”的闭环，不改变 Rust Core、ACP、Policy、Keychain、Checkpoint/Rollback、Resizable 或 Task Transaction 基础语义。

## 1. Architecture

| 组件 | 实现 | 职责 |
| --- | --- | --- |
| `BrowserDriver` | `WKBrowserDriver` | 隐藏的 macOS WebKit 页面、导航、viewport、DOM、截图、Console/Page Error/Network instrumentation |
| `DevServerSupervisor` | `BrowserVerification.swift` | 识别并启动本地 dev server、ready probe、PID/子进程 ownership、URL、日志、超时、停止和清理 |
| `BrowserVerificationService` | `BrowserVerification.swift` | 单 session 编排、状态迁移、证据保存、取消/超时和结果回调 |
| `BrowserVerificationPlanner` | `BrowserVerification.swift` | 读取 Project Intelligence，只有前端/UI 改动才要求浏览器验证 |
| Workspace UI | `main.swift` | Tools 页“浏览器验证”、状态/URL/viewport/Console/Network/Layout/截图 artifact 展示，以及“查看截图”本地窗口 |
| Agent integration | `main.swift` | Verification Gate 后运行 Browser Verification；失败回 Builder，最多 3 轮；成功后才进入 Verifier/Reviewer 完成门 |

浏览器驱动没有被 Agent 直接调用；后续可替换为 Playwright/CDP，而不会改变 `BrowserVerificationResult` 合约。

## 2. Browser Runtime / Dev Server

- 本机审计未发现项目内可复用的 Playwright、Puppeteer、CDP 或 Chromium bundle；也没有下载浏览器。
- 第一版使用系统自带 `macOS WebKit` (`WKWebView`)，无需用户安装 Chrome/Chromium，安装包没有新增大型浏览器二进制。
- Finder/LaunchServices 启动时沿用安装器 Node 工具链：`~/Library/Application Support/AI Dev One Installer/toolchains/node/bin` 被注入到受管 server 的 PATH。
- `package.json` 按 `dev → start → serve → preview` 顺序检测；支持 npm、pnpm、yarn、bun lockfile，识别 Vite、React、Next.js、Astro、Svelte、Nuxt，并读取 `aiDevOne.browserVerification.url`。
- 不硬编码 3000/5173；优先读取配置或解析受管进程 stdout/stderr 中的 localhost URL。
- 同一 verification session 最多一个受管 server。已存在且与项目配置完全匹配的 localhost 服务可 attach；用户自有服务不会被停止。只有 AI Dev One 启动的 process tree 才会被终止。

## 3. Security Model

- URL allowlist 仅接受 `http(s)://localhost` 和 `http(s)://127.0.0.1`，拒绝外域、`file://`、用户信息、query/fragment 会从证据 URL 中移除。
- 没有项目 dev server 时不会仅凭传入 localhost URL 探测任意本机服务；必须先通过项目 `package.json` 识别 server plan。
- 受管进程继承的环境会移除 `OPENAI_API_KEY`、`XAI_API_KEY`、所有 `*_API_KEY`、`AUTHORIZATION` 和 `*_AUTH_TOKEN`；Telemetry 已关闭。
- server stdout/stderr、Console/Page Error、DOM 摘要、Network URL、错误卡片统一使用 `BrowserVerificationRedaction`；不会读取 password input value，也不会把 screenshot 上传外部服务。
- Evidence 只写 Application Support，不写用户 repository；Screenshot 是本地 PNG，Result JSON 只存 artifact path/尺寸/SHA-256，不存二进制。
- 子进程停止使用 ownership、PID start token、descendant tree 和 2 秒 drain，避免误杀 PID 复用进程。

## 4. Verification Data Model

`BrowserVerificationSession` 记录 verification/task/project、dev server command/PID/URL、runtime、开始/结束时间、viewport 和状态：

`created → starting_server → launching_browser → loading_page → capturing → analyzing → passed/failed/cancelled/error/skipped`

`BrowserVerificationResult` 包含：

- PASS / FAIL / SKIPPED 状态和分级 finding（info/warning/error/critical）
- screenshot artifact、SHA-256、viewport
- title、sanitized URL、visible text summary、interactive count、buttons/links/inputs/forms/landmarks
- console errors/warnings、uncaught/page errors、failed requests
- horizontal/vertical overflow、off-screen/zero-size important controls、overlap findings
- instrumentation flag、summary 和 `timingsMS`

## 5. Screenshot / DOM / Console / Network / Layout

- `WKSnapshotConfiguration` 支持 viewport 和 full-page snapshot；默认 Agent 证据使用 viewport PNG，避免 Chat 被大图淹没。
- DOM 是有限摘要，不永久保存完整 HTML；重点控件做可视性、尺寸、越界和重叠检查。
- 注入的 WKUserScript 捕获 `console.error`、`console.warn`、`window.error`、`unhandledrejection`、fetch/XHR 非 2xx/网络失败。
- Console warning 不单独阻塞；Console error、页面错误、关键 Network failure 和布局错误进入 FAIL finding。纵向滚动只作 warning。
- 证据目录：`~/Library/Application Support/{Nexus|AI Dev One}/browser-verification/<task-id>/<verification-id>/`，保留策略为 14 天，并支持按 task 清理。

## 6. Viewport Strategy

提供固定 viewport：

- Desktop：1440 × 900
- Laptop：1280 × 800
- Mobile：390 × 844

默认任务只跑 Desktop；当任务/Project Intelligence 指示响应式或前端改动时可选择额外 viewport。当前第一版没有强制视觉模型审查，确定性 WebKit 检查可在没有模型凭据时独立运行。

## 7. Agent / Verifier / Reviewer / Self-repair

`BrowserVerificationPlanner` 使用 Project Intelligence 的 framework 和 transaction 前端改动判断 `browser_verification_required`，不会让后端任务无理由启动浏览器。

流程为：

`Unit/Type/Build Gate → Browser Verification → Verifier → Reviewer`

Browser FAIL 不由 Verifier 直接改文件，而是回 Builder，记录真实 finding 和 `Builder: browser fix loop n/3`，最多 3 轮；超过上限，Task Transaction 为 failed。Browser PASS 后才允许 Verifier/Reviewer gate 通过。Reviewer 复用 transaction 中的 verification check、artifact path 和 finding。

## 8. Local Fixtures / E2E Results

所有测试均使用临时 localhost fixture，无外部网络：

| 场景 | 真实结果 |
| --- | --- |
| Normal page | PASS；screenshot=1，Console=0，Network=0，Layout=0 |
| Console error | PASS（正确捕获）；fixture result=FAIL，errors=1，instrumentation=true |
| Broken asset/network | PASS（正确捕获）；fixture result=FAIL，failed=1 |
| Horizontal overflow | PASS（正确捕获）；fixture result=FAIL，layout findings=1 |
| Responsive mobile | PASS（正确捕获）；390×844 result=FAIL |
| Self-repair | PASS；首轮 FAIL，Builder 修复后第二轮 PASS |
| Process cleanup | PASS；`process.cleanup=true`，fixture/server 无残留 |

最新 Normal fixture 实测耗时（毫秒）：

| dev server startup | page + DOM | screenshot | total |
| ---: | ---: | ---: | ---: |
| 185.6 | 557.0 | 58.2 | 947.9 |

## 9. Tests / Build

- `bash scripts/test-nexus`：PASS，离线回归 **82 passed / 0 failed**，包括 Phase 1、v0.4、Browser unit/acceptance/live fixtures。
- Swift BrowserVerification/Project Intelligence harness typecheck：PASS。
- Browser driver/security/layout contract：PASS。
- Browser plan/URL/redaction acceptance：PASS。
- Browser live localhost E2E：PASS（上述 7 类场景）。
- `tests/secret-redaction.cjs`：PASS，扫描 165 个 runtime JSONL，无 credential-shaped value。
- `bash scripts/build-nexus-desktop`：PASS，产物 `dist/Nexus.app`。
- `codesign --verify --deep --strict dist/Nexus.app`：PASS；Bundle ID `cn.nexus.desktop`，显示名 `AI Dev One`。
- 安装包 smoke：PASS；窗口 1440×900、三栏和 snapshot probe 正常，进程可退出。
- Rust/Core/ACP 未修改；Phase 1/v0.4 Rust gate 继续沿用既有 PASS 基线。

## 10. Known Limitations / Gate Notes

1. 当前驱动是系统 WebKit，不提供 Chromium 特有的 DevTools trace；如未来需要 Chromium 兼容性，再新增受 Policy 管控的 runtime adapter。
2. 默认只保存 viewport screenshot；full-page 能力已在 driver 合约中可用，后续可按任务选择保存 full-page artifact。
3. 本机没有有效模型凭据，未执行真实外部模型驱动的 Agent UI 修改任务；本报告不伪造该结果。Agent integration contract、Verifier/Builder bounded self-repair 和 localhost visual E2E 均已真实执行。Phase 2 不访问外网，因此需要配置模型后再做一次 live-model acceptance。
4. 没有创建 v0.5 tag；本次只形成源码/测试/报告基线提交。

### Phase 2 状态

离线 Browser Visual Verification 能力：**PASS**
P0（凭据泄露、外网绕过、误杀用户进程、无限子进程、错误显示 PASS）：**0**
P1（Console/Network/Layout 检测、进程清理、Project Intelligence 接入、bounded self-repair、取消/超时）：**0**
P2：**1（真实 live-model Agent UI acceptance 尚未在无凭据环境执行）**
P3：**0**

建议：进入 v0.5 Phase 3 前，先在隔离测试项目配置临时模型凭据，完成一次不出网策略允许范围内的真实 Agent UI acceptance；不要把凭据提交到仓库或日志。

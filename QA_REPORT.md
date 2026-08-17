# AI Dev One Route 2 v0.3.0 QA / Product Hardening 报告

日期：2026-08-15
测试环境：macOS 12.7.6，原生 Swift/AppKit 桌面端，Rust `nexus-agent` 运行时，外置卷 `/Volumes/AI-DEV`。

## 范围和工程事实

本仓库当前实际不是 Electron/React 工程：没有 `package.json`、`electron/`、`src/ui/`、Vite 配置或 JavaScript Renderer；桌面端入口是 `apps/nexus-desktop/Sources/NexusDesktop/main.swift`，三栏布局使用 AppKit `NSSplitView`，后台使用 Rust `nexus-agent`。因此 Electron/React 专属检查已转换为等价的 AppKit/Runtime 检查，没有修改 Rust Core、ACP 或工具执行逻辑。

## P0 Critical

### P0-1：窗口曾可被压缩成极窄竖条

- 问题：布局 fitting size 可能反向影响主窗口边界。
- 原因：窗口 content host 与三栏布局没有隔离，异常保存的 bounds 也可能被恢复。
- 修复：保留并验证原生 `WindowContentHostView`；窗口 `1440×900`，最小 `1180×720`；启动时校验 NaN、越界、屏外和小于最小值的 frame，异常直接恢复并居中。
- 测试结果：异常 frame `28×28` 自愈为 `1440×900`；1280×800、1440×900、1728×1117、1920×1080、2560×1440 均保持完整主窗口；PASS。

### P0-2：API Key 明文存储和错误信息泄露风险

- 问题：旧版本把 `api_key` 写入 `~/.nexus/config.toml`。
- 修复：增加 macOS Keychain 存储、旧配置迁移、配置文件 `api_key` 清理、目录/文件权限强化（目标 `700/600`）；代理错误输出增加敏感值脱敏，不把 Key 放入命令行参数。
- 测试结果：当前配置 `api_key` 行数为 `0`，配置文件权限 `600`，外置数据目录权限 `700`；仓库/配置/会话中未发现用户 Key 形式的匹配；PASS。
- 注意：当前测试会话的 `securityd` 对钥匙串读取出现等待，已改为后台非阻塞访问；见 P1-2 的剩余风险。

### P0-3：钥匙串交互授权导致启动白屏/卡死

- 问题：第一版安全迁移在 AppKit 主线程同步调用 `SecItemCopyMatching`，调用栈确认启动卡在 Security.framework。
- 修复：钥匙串预热、迁移和保存全部移到后台；主线程不执行可能等待登录钥匙串的查询；设置保存期间界面保持响应。
- 测试结果：修复后主窗口正常出现，窗口列表显示 `1440×900`；采样显示钥匙串等待只存在于后台线程；PASS。

### P0-4：退出时代理子进程清理

- 问题：Cmd+Q/关闭窗口路径不完全覆盖运行中的 Agent 子进程。
- 修复：增加 `applicationShouldTerminate`，退出时中断当前任务；1 秒后仍运行则 terminate，避免孤儿进程。
- 测试结果：退出/重启检查没有残留 `nexus-agent`；PASS。

## P1 High

### P1-1：Core、Model、Agent 状态混用

- 问题：历史会话显示“OpenAI 接口拒绝密钥”，顶部和底部却显示 Agent Ready。
- 修复：Renderer 状态拆成 `CoreState`、`ModelState`、`AgentState`、`WorkspaceState`；鉴权错误显示“API 配置异常 / Model Config Required / Agent Idle”，不再把 Core Ready 当作 Agent Ready。
- 测试结果：静态合约测试、启动状态检查、错误路径检查；PASS。

### P1-2：钥匙串在当前系统会话中的可读性

- 问题：当前 macOS 会话中 `SecItemCopyMatching` 可能等待 `securityd` 的钥匙串交互，即使设置了非交互上下文也不能保证立即返回。
- 影响：应用不会再白屏，但冷启动时如果后台读取尚未完成，Model 状态会暂时显示“需要配置”；这不会泄露 Key，也不会阻塞 UI。
- 当前处理：后台读取、UI 明确显示配置状态、设置页可重新保存凭据；未把 Key 回退写回配置文件。
- 状态：未完全解决，建议在真实用户登录钥匙串已解锁的 macOS 机器上做一次升级验证。

### P1-3：Agent Pipeline 状态不真实

- 问题：四个 Agent 过去可能同时呈现运行/完成视觉。
- 修复：Architect、Builder、Verifier、Reviewer 按 Planning/Editing/Testing/Reviewing 顺序更新；未开始阶段显示 Waiting，完成显示 Completed，失败阶段显示 Failed，后续阶段保持 Waiting。
- 测试结果：`agent-state-unit.cjs` PASS；源代码类型检查 PASS。

### P1-4：错误处理缺少可操作入口

- 问题：错误卡片只有文本。
- 修复：统一系统错误卡片，增加“打开模型设置”和“重新连接”；401、403、429、502/503、超时、网络错误和模型不存在均映射为明确中文状态；重试不会追加重复 User 消息。
- 测试结果：`model-error-unit.cjs`、无 Key 代理探针（exit 2）、无 Key HTTP 探针（401）PASS。

### P1-5：Resizable 布局边界与持久化

- 问题：两侧 Pane 异常值可能挤压 Chat 或覆盖窗口。
- 修复/验证：Sidebar `220–420`（默认 260），Workspace `280–620`（默认 340），Chat 最小 520；空间不足时优先压缩 Workspace；非法 UserDefaults 值清理；双击恢复和重置布局保留。
- 测试结果：1280×800 最大 Pane 输入被压缩为可用宽度（Sidebar 420、Workspace 310，Chat 保持最小）；最小 Pane 220/280 可恢复；PASS。
- 限制：本环境未授予 Accessibility，无法用真实鼠标事件完成“快速拖动 30 次/离开窗口继续拖动”的物理自动化；原生 `NSSplitView` 拖拽、命中区和约束代码已通过静态检查。

### P1-6：Session/Composer 重复提交保护

- 修复/验证：Runner 单实例 guard、Composer running 状态、Enter/Shift+Enter/IME marked text 逻辑、重试复用原 User 消息；Session 消息按 session/message ID 更新。
- 测试结果：`session-state-unit.cjs` PASS；无运行时重复 Agent 的静态路径检查 PASS。
- 限制：20 个 Session、跨项目切换和 50 条真实消息的手工 UI 操作未在无障碍权限环境中自动完成。

### P1-7：Core 崩溃后的“重新启动 Core”

- 现状：当前桌面端按任务启动 `nexus-agent`，不是常驻独立 Core 服务；缺失代理时会显示 `Core Disconnected`，错误卡片可重试任务，但没有单独的 Core restart 按钮。
- 状态：未新增大功能，保留为 v0.4 产品项。

## P2 Medium

### P2-1：Workspace 文案混用和标题重复

- 修复：统一为“最近变更 / 已修改 / 已添加 / 已删除”，移除 `Recent Changes` 与“最近文件”重复标题；项目路径单行截断并提供 tooltip。
- 测试结果：`workspace-parser-unit.cjs` PASS。

### P2-2：大量 Git 变更可能撑爆 Renderer

- 修复：Recent Changes 首屏最多渲染 50 项，并显示剩余数量；Workspace 已禁用横向滚动。
- 状态：首屏保护已完成；尚未实现 Load More 或真正 virtual list，保留为后续优化。

### P2-3：配置 warning

- 现状：旧配置中的 `[features] remote_fetch = false` 对当前 Rust 版本会产生“unrecognized key” warning；没有隐藏该 warning，也没有擅自改变远程抓取策略。
- 状态：未解决，需结合 Rust 配置 schema 决定迁移/删除方式。

### P2-4：性能与视觉回归自动化不足

- 已完成：背景重绘降频，空闲采样未出现持续高 CPU；Deep Forest / Liquid Glass 主题未重设计。
- 未完成：不同显示器缩放、prefers-reduced-motion、窗口失焦降粒子和像素级截图 diff 未形成 CI。

### P2-5：权限、Policy、Checkpoint/Rollback 的交互回归

- 现有 Runtime/Policy/Checkpoint 逻辑未修改。
- 本轮未在真实只读目录、系统目录、危险命令审批、磁盘回滚场景执行破坏性测试；这些需要专用临时仓库和明确的人工审批窗口，不能用静态检查冒充通过。

## P3 Polish

本轮不重新设计 UI，也没有新增 P3 视觉功能；当前主题、三栏结构、Composer、状态胶囊和玻璃背景保持不变。P3 已修复 0 项，未解决 0 项。

## 自动化测试真实结果

| 检查 | 结果 |
|---|---|
| `NEXUS_SWIFT_MODULE_CACHE=/tmp/nexus-swift-module-cache ./scripts/test-nexus` | PASS：63 通过，0 失败 |
| `./scripts/test-nexus --gui` | PASS：63 通过，0 失败 |
| `swiftc -typecheck`（AppKit/Foundation/LocalAuthentication/Security） | PASS |
| `node tests/*-unit.cjs`（使用 Codex bundled Node） | PASS：6/6 |
| `./scripts/build-nexus-desktop` | PASS |
| App codesign verify | PASS |
| dist/installed executable SHA-256 | PASS：一致 |
| `git diff --check` / shell syntax | PASS |
| 无 Key 运行时探针 | PASS：明确 exit 2，不进入英文登录页 |
| 中转接口无 Key `/v1/models` | PASS：HTTP 401（符合预期） |
| 窗口 bounds/pane 自愈与尺寸矩阵 | PASS：1280×800、1440×900、1728×1117、1920×1080、2560×1440 |
| 退出/重启残留 `nexus-agent` 检查 | PASS：无残留 |
| `npm run typecheck` | WARNING：仓库无 `package.json`，不适用 |
| `npm test` | WARNING：仓库无 `package.json`，不适用 |
| `npm run build` | WARNING：仓库无 `package.json`，不适用 |
| `npm run test:route2` / `test:v03` / `test:policy` | WARNING：仓库无 `package.json`，不适用 |
| `cargo test` | WARNING：当前环境 `cargo` 不在 PATH，未执行 |
| 系统 Node.js | WARNING：未安装；合约测试使用 bundled Node 通过 |

补充：此前配置仍含有效 Key 时已做过一次真实中转探针：可用模型 `gpt-5.4` 返回 HTTP 200；不可用模型 `gpt` 返回 HTTP 503/model-not-found。该探针未把 Key 写入报告或日志。

## 数量汇总

| 优先级 | 已修复/验证 | 未解决 | 合计 |
|---|---:|---:|---:|
| P0 | 4 | 0 | 4 |
| P1 | 5 | 2 | 7 |
| P2 | 2 | 3 | 5 |
| P3 | 0 | 0 | 0 |

## 是否建议进入 v0.4

不建议把当前状态标记为“所有产品场景完全验收”；建议以当前构建作为可日常使用的 v0.3.0 hardening build，同时在进入 v0.4 前优先完成：

1. 在钥匙串已解锁的真实用户环境验证迁移后的冷启动和有效 API 请求。
2. 开启 Accessibility 后完成真实拖拽、连续提交、Session 切换和 1000+ 变更列表回归。
3. 明确 `remote_fetch` 配置 schema，并补充 Core crash/restart、Policy 和 Rollback 的隔离测试。

这些未覆盖项都已在本报告列出，没有用“应该没问题”替代测试结果。

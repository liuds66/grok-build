# AI Dev One Route 2 — Full System E2E Report

> 本报告记录本轮从构建、安装、冷启动到真实 Runtime 链路的现场验证。所有破坏性测试均使用一次性 Git fixture，不触碰真实项目。

## 0. 工程身份

| 项目 | 本轮值 |
|---|---|
| Repository root | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座` |
| Git branch | `codex/nexus-agent` |
| Git commit（开始/当前，本轮未提交） | `a5727c5960452e7527a154b25cb5bf00cda0545e` |
| App source | `apps/nexus-desktop/Sources/NexusDesktop` |
| Rust workspace | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/Cargo.toml` |
| Build scripts | `scripts/build-nexus`, `scripts/build-nexus-desktop` |
| Test scripts | `scripts/test-nexus`, `tests/*.cjs` |
| Build output | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/dist/Nexus.app` |
| Installed app | `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` |
| Bundle identifier | `cn.nexus.desktop` |
| Display name | `AI Dev One` |
| Executable filename | `Nexus` |
| External app filename | `Nexus.app`（历史兼容名称；Info.plist 用户可见品牌已是 AI Dev One） |
| E2E fixture | `/tmp/ai-dev-one-e2e.XTZjDo`（Git baseline `af4a9b819c8182f9d31a7ee721e0f2eeaa37d8fa`） |

## 1. 执行记录

本轮记录采用 `PASS / FAIL / BLOCKED / MANUAL`，不把未执行项目伪装成 PASS。

| 场景 | 预期 | 实际 | 结果 | 证据 |
|---|---|---|---|---|
| Rust workspace 编译 | 使用安装器 Rust 实际编译修改相关 workspace | `cargo 1.97.1` + `rustc 1.97.1`，`cargo check -p xai-grok-workspace` 完成；4 条既有 `f32` future-incompatible warning，无 error | PASS | `/tmp/ai-dev-one-cargo-check.log`，`Finished dev profile` |
| Rust workspace 测试 | 运行 `cargo test -p xai-grok-workspace` | 安装器 Rust 1.97.1 下，unit tests `1534 passed`，workspace_server tests `12 passed`；首次 doctest 因系统 rustdoc 1.92 与 rustc 1.97 混用报 222 个 E0514/E0432。随后用同一安装器 rustc/rustdoc 重跑约 55 分钟，仍停在外置盘 `xai-grok-workspace` 增量编译/链接阶段，无编译错误输出，因现场时限安全停止，未宣称 doctest PASS | PARTIAL / ENVIRONMENT BLOCKED | `/tmp/ai-dev-one-cargo-test.log`、`/tmp/ai-dev-one-cargo-test-rust197.log` |
| Swift/Electron 桌面构建 | 生成真实 app | `scripts/build-nexus-desktop` 成功生成 `dist/Nexus.app`；最新安装产物 mtime `2026-08-16 23:56:12` | PASS | 构建脚本输出 |
| 安装与签名 | 安装到外置盘真实应用路径并可验证 | 已复制到 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`；`codesign --verify --deep --strict` 通过；Bundle `cn.nexus.desktop`，显示名 `AI Dev One` | PASS | 安装路径与签名命令输出 |
| CJS 回归 | 所有 `tests/*.cjs` 通过 | 18 个测试，18 PASS，0 FAIL | PASS | `CJS_SUMMARY total=18 pass=18 fail=0` |
| GUI 离线烟测 | 类型检查、布局合同、资源、外置盘链接和运行中 App | 通过 67，失败 0 | PASS | `scripts/test-nexus --gui`：`结果：通过 67，失败 0` |
| 窗口/三栏布局 | 不受 pane fittingSize 压缩，默认 1440×900 | layout probe：window 1440×900；sidebar 260，chat 810，workspace 340；最小窗口合同 1180×720；真实 LaunchServices 退出→重启后进程恢复 | PASS | `NEXUS_LAYOUT_PROBE` 输出、`tests/resizable-layout-unit.cjs` |
| 真实只读 Agent 任务 | 网络可用、读取完成、不写磁盘 | 第一次旧 profile 复现网络隔离；修复后 `end=1 tool_start=2 tool_failed=0 error=0` | PASS（修复后） | `/tmp/ai-dev-one-readonly.jsonl` |
| 真实写入 Agent 任务 | Agent 修改文件并运行项目测试 | 首次复现 Finder PATH 缺 Node；注入安装器 Node PATH 后 `end=1 tool_start=14 tool_failed=0 error=0`，`multiply_ts/js=1`，`npm test=PASS` | PASS（修复后） | `/tmp/ai-dev-one-write-2.jsonl`、fixture git diff |
| Policy live allow | Agent→Tool→Policy→Shell 允许安全命令 | `echo AI_DEV_ONE_POLICY_ALLOW_OK`：`end=1 tool_start=1 tool_failed=0` | PASS | `/tmp/ai-dev-one-policy-allow.jsonl` |
| Policy live deny | 危险命令不能落盘执行 | `rm -rf ./protected.txt` 经真实 Tool chain 进入 `tool_update status=Failed`；`protected.txt` 仍存在 | PASS | `/tmp/ai-dev-one-policy-deny.jsonl`，`protected_exists=PASS` |
| Core kill / 中断 | kill 正在执行的 core 后不得伪完成、不得留 shell | 真实 `nexus-agent` PID `8207` 被 `SIGKILL`；事件停留在 `tool_start`，无 `end`；sleep 子进程清理后无残留 | PASS（进程层） | `/tmp/ai-dev-one-crash-final.jsonl`，`core_crash_test=PASS` |
| Checkpoint/rollback | 修改/删除/新增/重命名后真实磁盘恢复 | 扩展、基础、interrupted rollback CJS+Swift harness 全部 PASS，SHA-256 与基线一致 | PASS | `tests/checkpoint-rollback*.cjs`、`tests/interrupted-rollback.cjs` |
| Transaction/secret audit | 审计字段完整且不含凭据 | transaction persistence/redaction PASS；138 个 runtime JSONL 扫描无 credential-shaped 值；本轮 live 日志计数 0 | PASS | `tests/task-transaction.cjs`、`tests/secret-redaction.cjs` |
| Keychain 冷启动 | 不阻塞 Renderer，迟到成功能恢复模型状态 | 最新安装包冷启动后 layout probe：`credential.state=credentials_ready`、`model.hasAPIKey=true`；窗口保持 1440×900，未白屏/重复提示；timeout 后 late-success 回调与合同测试已加入 | PASS | `/tmp/ai-dev-one-layout-probe-keychain-final2.txt`、`/tmp/ai-dev-one-layout-snapshot-keychain-final2.png` |
| DeepSeek live model | 有效凭据可完成协议调用 | 真实 API 任务完成；DeepSeek v4 flash 的会话标题 `tool_choice` 返回 400，runtime 已降级为用户文本标题，主任务不失败 | PASS + WARNING | 各 live stderr；不含密钥 |

### 最后一轮复核备注

- CJS 回归在安装器 Node `v22.23.1`（已注入桌面运行时同一 PATH）下重新执行：`18/18 PASS`。其中 `unknown=SKIPPED` 是 Verification Gate 的预期分支，不是测试失败。
- GUI 离线烟测此前完整完成并记录为 `67/0`。本轮再次启动时，Swift 类型检查与前 50 项合同检查均通过；随后 `nexus-agent worktree list` 在外置盘上进入不可中断 IO 等待，未产生错误输出，已停止该重复复核，不将其计为新的 PASS/FAIL。
- 另一次无安装器 Node PATH 的脚本调用得到 `node: command not found`，属于测试壳环境误调用，已用正确 PATH 重跑，不计入产品失败。

## 2. 发现与修复

| 编号 | 优先级 | 复现 | 根因 | 修复/回归测试 | 状态 |
|---|---|---|---|---|---|
| E2E-001 | P1 | `run_terminal_command`（如网络探测）在桌面任务中产生隐藏权限请求，随后显示“执行失败：执行工具” | Renderer 只处理 streaming-json，不具备 headless runtime 的二次 stdin 权限回复；`acceptEdits` 对 shell gate 仍会等待授权 | 工作区显式批准改用 `bypassPermissions`；保留 Rust policy 与显式 `--deny`；解析 tool_update 真实 detail；失败工具禁止后续 `end` 伪装成 Completed | 已修复并由真实写入任务、Policy deny 复测 |
| E2E-002 | P1 | `--sandbox read-only --permission-mode plan` 的真实只读任务无法访问模型网络 | read-only macOS profile 同时设置 `restrict_network=true`，把模型请求本身挡掉 | 桌面只读语义保留为 `plan`，运行 profile 改为 `workspace`；真实读取任务 `end=1`，无失败工具 | 已修复，回归 PASS |
| E2E-003 | P1 | Finder 启动桌面 App 时模型运行环境找不到 `node/npm`，测试阶段失败 | Finder 进程 PATH 不包含安装器 toolchain | `BackendLocator.processEnvironment()` 注入本机安装器 Node/Cargo PATH；真实 Agent 修改+`npm test` PASS | 已修复，回归 PASS |
| E2E-004 | P1 | Keychain 慢读在 timeout 后返回错误但迟到成功不刷新 UI | `completionDelivered` 阻止了迟到成功回调 | late-success 分支重新投递 `.credentialsReady`，避免 Renderer 卡在配置异常；新增 `desktop-runtime-contract.cjs` 断言 | 已修复；需人工冷启动确认 |

## 3. 未自动化/现场限制

- macOS Accessibility 权限未授予，无法用自动化工具代替用户真实拖动鼠标；Resizable 的代码合同、窗口布局 probe 和 67 项 GUI 烟测已通过，但“快速拖 30 次、多显示器、睡眠/唤醒”仍标为 MANUAL。
- CoreRecoveryCoordinator 的 1s/2s/5s 上限由合同测试覆盖；本轮还真实 kill 了 Agent core 并确认任务没有 `end`/伪完成、子进程清理。未在无障碍权限下自动点击桌面 UI 的“重新启动 Core”按钮。
- DeepSeek `deepseek-v4-flash` 的会话标题请求会出现 `Thinking mode does not support this tool_choice` 400；runtime 已 fallback，不影响主任务，但属于 P2 warning，建议后续改为兼容模型或标题请求禁用 tool choice。

## 4. 最终结论（截至当前）

- P0 remaining：0（未发现 crash、数据丢失、策略绕过或 secret 泄漏）
- P1 remaining：0 个已复现代码问题；2 项发布验证阻塞（Accessibility resize/Core restart 按钮人工验收；Rust doctest 需在本地磁盘或同等稳定构建环境完成一次无混用全量 `cargo test`）
- P2 remaining（当时）：1（DeepSeek v4 flash 标题请求 warning；已在本轮 Final Gate 修复并由 28/28 回归覆盖）
- P3 remaining：0
- 是否建议 v0.4 Beta：建议先完成上述两类验证（尤其是 Rust doctest 和两项人工验收）再进入 Beta；当前构建可作为 Release Candidate 供本机日常试用。

## RC2 Core Recovery 复测（2026-08-17）

本节覆盖此前报告中 Core kill/Restart 的未解决现场项；此前 FAIL 记录属于修复前安装包。RC2 在 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 上重新执行了真实任务、`kill -9`、自动恢复、crash loop、Restart 按钮和恢复后新任务：

| 场景 | 实际结果 | 状态 |
|---|---|---|
| 真实 kill | PID `27128` 被 SIGKILL；任务未伪完成，随后 Core health check 恢复 | PASS |
| 自动恢复 | `disconnected → restarting → ready`，首轮约 1 秒；不自动重发旧 prompt | PASS |
| Crash loop | 临时失败 wrapper 触发 1s/2s/5s，随后 `failed`，无无限重启 | PASS |
| Restart UI | 失败态出现“重新启动 Core”“查看日志”，AXPress 可用 | PASS |
| 手动 Restart | 新健康检查 PID `27368`，状态 `ready`，随后新任务成功 | PASS |
| 进程清理 | 同时 Core 不超过 1 个；退出/恢复后无 zombie | PASS |

RC2 新增回归：`tests/core-supervisor-unit.cjs`。统一 stable 1.97.1 工具链执行 `cargo test -p xai-grok-pager-bin`：两个 binary test suites 各 31 项，0 failed；CJS 19/19，`scripts/test-nexus` 66/0。Resizable 本轮未改代码，真实鼠标拖动与最大化/恢复仍需最终人工验收。

## 5. v0.4 Beta Final Gate（2026-08-17，本轮更新）

本轮关闭了 DeepSeek 会话标题请求的兼容性阻塞，并在本机磁盘以同一 Rust toolchain 完成 workspace doctest：日志中 80 个 `test result:` 块全部为 `ok`，没有 `FAILED`、`error:` 或 failed result。标题请求现在是纯文本请求，不发送 tools/tool_choice；相关 Rust 回归为 28/28 PASS。

| Gate | 实际结果 | 状态 | 证据 |
|---|---|---|---|
| Rust workspace doctest | 本机 `/Users/mac/AI-Dev-One-Build/target`，80 个结果块，无失败 | PASS | `/tmp/ai-dev-one-local-workspace-doctest-final.log` |
| DeepSeek title warning | title request tools 为空、tool_choice=None；标题解析兼容纯文本/旧 JSON | PASS | `/tmp/ai-dev-one-session-title-test.log` |
| CJS regression | 18/18 PASS，0 FAIL | PASS | `/tmp/ai-dev-one-cjs-final.log` |
| Resizable 人工拖拽 | macOS Accessibility 未授权，不能伪造鼠标现场验收 | BLOCKED | `MANUAL_UI_ACCEPTANCE.md` |
| Core Restart 按钮人工点击 | 进程层 kill/清理合同 PASS；按钮点击受同一权限阻塞 | BLOCKED | `MANUAL_UI_ACCEPTANCE.md` |
| Final runtime release build/install/cold start | 本地 target release 编译完成后执行 | PASS（详见第 6 节最终复核） | `/tmp/ai-dev-one-final-runtime-build.log`、`/tmp/ai-dev-one-final-desktop-install.log` |

（该段是 Final Gate 执行中的历史截点；最终 release build、签名安装和冷启动结果已在第 6 节补写。未授权的两项人工验收仍不能写成 PASS。）

## 6. Final Gate 产物复核（2026-08-17）

本轮等待并完成了一次本地磁盘 clean Rust release build，而不是沿用旧产物：

- `cargo build -p xai-grok-pager-bin --bin nexus-agent --release` 使用安装器 Rust 1.97.1，`NEXUS_BUILD_TARGET_DIR=/Users/mac/AI-Dev-One-Build/runtime-target`，`Finished release` 用时 146m36s；生成 x86_64 Mach-O `nexus-agent`（187,276,312 bytes）。日志中只有既有 `xai-grok-tools` 的 4 条 f32 future-incompatible warning，没有 error。
- `scripts/build-nexus-desktop` 与 `scripts/install-nexus-desktop` 均返回 0。`codesign --verify --deep --strict` 通过；安装包 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app/Contents/Resources/nexus-agent` 与 release 二进制 SHA-256 均为 `20d7a521b01818b68e476e844611219ed8dd5c9640dc751320e66f496b76a39d`。
- LaunchServices 从外置盘安装包冷启动实际进程，layout probe 确认窗口 `1780×1224`、pane `260/1150/340`，UI snapshot 成功生成；随后退出检查无 `Nexus`、Runtime `nexus-agent` 或 Core 残留。安装包 Info.plist 的用户可见名称为 `AI Dev One`，文件名仍为历史兼容的 `Nexus.app`。
- 本轮最终 CJS 回归为 18/18 PASS，最终 runtime 日志 Secret scan 的 credential-shaped 文件数为 0。Rust workspace doctest 仍以同一 toolchain 的 80 个 `test result: ok` 记录为 PASS。
- DeepSeek 标题回归 28/28 PASS；title request 不再带 tools/tool_choice。本轮未另发起 live 标题请求，因此 live-warning 结论不超出请求构造与回归测试证据。

最终 Release Gate 仍有两项真实人工前置条件：macOS Accessibility 未授权，无法伪造 Resizable 鼠标拖动和 Core Restart 按钮点击。它们不是代码失败，但按发布规则保留为 P1 阻塞；本构建应标为 RC，不应宣称正式 v0.4 Beta。

## 辅助功能授权后的真实复核（2026-08-17）

本机随后已取得 `AX_TRUSTED=true`，并对安装包进行真实 Composer→审批→Runtime→kill 操作。两次记录的 Core PID 为 `96745`、`97213`；分别 `kill -9` 后，第一次 UI 进入“Agent 失败”，第二次回到“Agent 空闲”，等待 8 秒均没有新的 `nexus-agent` PID，也没有可见的“重新启动 Core”按钮。这与早先基于合同/fixture 的进程层恢复测试不同，属于安装包现场复核的真实失败，不能继续把 Core Restart 记为 PASS。

同时验证了“重置界面布局”菜单（窗口 `1440×900`、pane `260/340`）、窗口下限保护（尝试 `500×300` 后仍保持大于 `1180×720`）以及两个 Divider 的双击恢复。真实 Divider 拖动事件未被当前 NSSplitView 识别，最大化/恢复也未能通过当前自动化通道完成，因此这两项仍需桌面人工复核。

结论：本次 Full E2E 不能宣称 Beta；P0=0，P1=2（Resizable 现场项、Core Restart 现场失败），未创建 `v0.4.0-beta.1`。

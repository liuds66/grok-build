# AI Dev One Route 2 v0.4.0-beta.1 Beta Final Gate

> 本文件记录 v0.4 Beta Final Gate 的真实证据。`BLOCKED` 表示尚未具备现场条件或命令仍在执行，不等同于 PASS。

## 工程身份

| 项目 | 值 |
|---|---|
| Repository root | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座` |
| Branch | `codex/nexus-agent` |
| 旧 RC Git commit SHA | `97893182ec30684c5d4b1c5ed55daa1d4be4d88f` |
| 最终 Beta baseline SHA | 以本地 annotated tag `v0.4.0-beta.1` 指向的提交为准 |
| 版本 | `0.4.0-beta.1` |
| App source | `apps/nexus-desktop/Sources/NexusDesktop` |
| Rust workspace | `Cargo.toml` |
| Installed app | `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` |
| Bundle identifier | `cn.nexus.desktop` |
| Display name | `AI Dev One` |
| App filename | `Nexus.app`（历史兼容名称；本轮不改名，避免破坏 bundle id、Keychain 和旧配置） |

## Rust 工具链

本轮三者来自同一安装器 toolchain：

```text
cargo  /Users/mac/Library/Application Support/AI Dev One Installer/toolchains/rustup/toolchains/stable-x86_64-apple-darwin/bin/cargo
rustc  /Users/mac/Library/Application Support/AI Dev One Installer/toolchains/rustup/toolchains/stable-x86_64-apple-darwin/bin/rustc
rustdoc /Users/mac/Library/Application Support/AI Dev One Installer/toolchains/rustup/toolchains/stable-x86_64-apple-darwin/bin/rustdoc
cargo 1.97.1 (c980f4866 2026-06-30)
rustc 1.97.1 (8bab26f4f 2026-07-14)
rustdoc 1.97.1 (8bab26f4f 2026-07-14)
CARGO_TARGET_DIR=/Users/mac/AI-Dev-One-Build/target
```

## Gate 结果

| 检查项 | 预期 | 真实结果 | 结果 | 证据 |
|---|---|---|---|---|
| Rust 修改 crate doctest | 同版本、本地磁盘、无混用 | `xai_grok_shell`：5 项，0 passed、0 failed、5 ignored；退出码 0 | PASS | `/tmp/ai-dev-one-local-shell-doctest-final.log` |
| Rust workspace doctest | `cargo test --doc --workspace` 完成且无失败 | 同一安装器 toolchain、本地 target；80 个 `test result:` 块全部为 `ok`，未发现 `FAILED`、`error:` 或 failed result | PASS | `/tmp/ai-dev-one-local-workspace-doctest-final.log` |
| Resizable 人工验收 | 220↔420、280↔620、快速拖动、双击重置 | RC3 安装包真实拖动 120 次；边界、最大化/恢复、持久化均通过 | PASS | `RC3_RESIZABLE_REPORT.md`、`MANUAL_UI_ACCEPTANCE.md` |
| Core Restart 按钮人工验收 | kill→UI disconnected/restarting→按钮恢复 | RC2 安装包已真实 kill、自动恢复和 Restart 按钮验收通过 | PASS | `RC2_CORE_RECOVERY_REPORT.md`、`MANUAL_UI_ACCEPTANCE.md` |
| DeepSeek title warning | title request 不发送 tools/tool_choice | Rust 回归 28/28 PASS；请求构造断言 tools 为空、tool_choice=None | PASS | `/tmp/ai-dev-one-session-title-test.log` |
| CJS 回归 | 18/18 | 18 PASS，0 FAIL | PASS | `/tmp/ai-dev-one-cjs-beta-final.log` |
| Secret scan | 不出现 key/Bearer/header | runtime JSONL 与本轮最终日志的 credential-shaped 文件数均为 0 | PASS | `/tmp/ai-dev-one-cjs-beta-final.log`、最终日志扫描输出 |
| 最终 Rust runtime release build | 新源码在本地 target 生成 `nexus-agent` | `Finished release`，用时 146m36s；x86_64 Mach-O，187,276,312 bytes；仅 4 条既有 f32 warning | PASS | `/tmp/ai-dev-one-final-runtime-build.log`、`/Users/mac/AI-Dev-One-Build/runtime-target/release/nexus-agent` |
| 最终 clean desktop build/install | 新 runtime 进入安装包并签名 | Swift desktop build、安装脚本、deep strict codesign 全部返回 0；安装包 runtime 与 release 二进制 SHA-256 相同 | PASS | `/tmp/ai-dev-one-final-desktop-install.log`、`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` |
| 安装包冷启动/退出 | LaunchServices 启动、窗口不白屏/不变窄、退出无 Core 残留 | 实际启动 PID 87102；probe 窗口 1780×1224、pane=260/1150/340；内部 UI snapshot 生成；退出后无 Nexus/nexus-agent 进程 | PASS | `/tmp/ai-dev-one-launchservices-probe2.txt`、`/tmp/ai-dev-one-launchservices-snapshot2.png`、进程快照 |

## 标题请求修复

`crates/codegen/xai-grok-shell/src/session/helpers/session_summary.rs` 现在构造纯文本标题请求：不附加 `ToolSpec`、不附加 `tool_choice`，同时兼容旧 provider 返回的 `{"session_title": ...}`。主 Agent 请求的工具链不变。回归测试覆盖纯文本、旧 JSON、DeepSeek 请求字段。

## 人工现场记录

详细现场证据见 [`MANUAL_UI_ACCEPTANCE.md`](MANUAL_UI_ACCEPTANCE.md) 与 [`RC3_RESIZABLE_REPORT.md`](RC3_RESIZABLE_REPORT.md)。Resizable 和 Core Restart 均已在安装包上完成真实验收。

## Beta 决策规则

只有 workspace doctest PASS、最终 release build/install/cold start PASS 且人工 Resizable/Core Restart 均 PASS，才能把 P1 现场阻塞清零并正式标记 `AI Dev One Route 2 v0.4 Beta`。在此之前，本构建最多标记为 Release Candidate；不把运行中或未授权的现场项宣称为通过。

## 当前优先级计数（最终人工验收前）

- P0：0
- P1：0（Resizable 与 Core Restart 现场项均已关闭）
- P2：0（DeepSeek 标题请求已移除 tools/tool_choice，并由 28/28 回归测试覆盖）
- P3：0

## Final release evidence（2026-08-17）

- Rust：同一安装器 toolchain 的 `cargo/rustc/rustdoc 1.97.1`；本机 target `/Users/mac/AI-Dev-One-Build/runtime-target`；release 二进制已复制进安装包，SHA-256 为 `20d7a521b01818b68e476e844611219ed8dd5c9640dc751320e66f496b76a39d`。
- Desktop：`scripts/build-nexus-desktop` 与 `scripts/install-nexus-desktop` 均返回 0；`codesign --verify --deep --strict` 返回 0。用户可见品牌是 `AI Dev One`，文件名仍为兼容旧配置的 `Nexus.app`。
- Cold start：从 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 经 LaunchServices 启动，实际 probe 窗口为 `1780×1224`，分栏为 `260/1150/340`，生成了 UI snapshot；退出后检查无安装包主进程、Runtime `nexus-agent` 或 Core 残留。启动初期凭据状态为 `loading_credentials` 属于 2.5 秒有界 Keychain 读取窗口；超时/迟到成功由合同测试覆盖，未阻塞 Renderer。
- DeepSeek 标题：最终源码回归 28/28 PASS；标题请求不再发送 tools/tool_choice。本轮没有为了“看起来通过”而伪造一次 live 标题请求，因此该项结论是请求构造/回归层 PASS，live API 观察未单独执行。

## Final gate decision

最终 release build、签名安装、LaunchServices 冷启动、Rust workspace doctest、CJS 回归和 Secret scan 均已完成且通过。RC2 Core 生命周期与 RC3 Resizable 真实安装包验收均通过，P1 已清零；本版本达到 **AI Dev One Route 2 v0.4 Beta** 的功能 Gate。

- P0 remaining：0
- P1 remaining：0
- P2 remaining：0
- P3 remaining：0

## RC2 Core 生命周期修复（2026-08-17；历史记录）

此前记录的“Core kill 后无恢复、无 Restart 按钮”已在 RC2 安装包中复现、修复并重新验收；旧记录保留作为历史证据，不再代表当前构建状态。详细记录见 [`RC2_CORE_RECOVERY_REPORT.md`](RC2_CORE_RECOVERY_REPORT.md)。

| 检查项 | RC2 真实结果 | 状态 |
|---|---|---|
| Core signal 分类 | `terminationReason == .uncaughtSignal` 现在优先于 stderr，kill 进入 `disconnected` | PASS |
| 自动恢复 | 真实安装包 `kill -9` 后日志为 `disconnected → restarting → ready`，退避 1 秒；任务保持 interrupted，不自动续跑 | PASS |
| Crash loop | 真实失败 wrapper 验证 1s/2s/5s，随后 `failed`，无第四次 spawn | PASS |
| Restart 入口 | 失败态 AX/UI 实际显示“重新启动 Core”“查看日志”，按钮可 AXPress | PASS |
| 手动重启 | 点击 Restart 后 `manual restart requested → ready`，单一健康检查 PID；之后新任务完成 | PASS |
| 正常退出 | `shutdown()` 设置 `manualShutdown`，不会由 termination handler 自动拉起 Core | PASS（合同/退出回归） |
| Resizable 真实鼠标 | RC3 安装包真实拖动 120 次，边界与最大化/恢复通过 | PASS |

### RC2 当前优先级（历史快照，已由 RC3 覆盖）

- P0 remaining：0
- P1 remaining：1（仅 Resizable 真实拖动/最大化人工验收）
- P2 remaining：0
- P3 remaining：0

当前仍为 **Release Candidate**，本轮不创建 Beta tag。`RC2_CORE_RECOVERY_REPORT.md` 同时记录统一 Rust 1.97.1 toolchain 的 `cargo test -p xai-grok-pager-bin`：62 tests、0 failed，以及 CJS 19/19、桌面烟测 66/0、Secret scan PASS。

## 真实现场复核（2026-08-17；修复前历史记录）

本机随后已授予 Accessibility（`AX_TRUSTED=true`），并对安装后的 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 做了真实操作尝试，结果覆盖并更新此前的“未授权 BLOCKED”说明：

| 项目 | 真实结果 | 证据 |
|---|---|---|
| 窗口最小尺寸 | PASS；AX 尝试设置 `500×300` 后窗口仍为 `1440×900`，未低于 `1180×720` | System Events window bounds |
| 布局重置 | PASS；菜单“重置界面布局”恢复窗口 `1440×900`、pane `260/340` | `defaults read cn.nexus.desktop`、System Events |
| Divider 双击 | PASS；左侧 `300→260`、右侧 `620→340` | UserDefaults 实测 |
| Divider 拖动 | BLOCKED；AX/cliclick 事件未被 NSSplitView 识别，未冒充 PASS | `MANUAL_UI_ACCEPTANCE.md` |
| 最大化/恢复 | BLOCKED；当前窗口未暴露可操作 AX 缩放按钮，需用户桌面真实点击 | `MANUAL_UI_ACCEPTANCE.md` |
| Core kill / 自动恢复 | FAIL；Core PID `96745` kill 后 Agent=失败、无替代 PID；PID `97213` kill 后 Agent=空闲、等待 8 秒无恢复 | `ps` + System Events 实测 |
| Restart 按钮 | FAIL；安装包 AX/UI 中未找到“重新启动 Core”按钮 | `MANUAL_UI_ACCEPTANCE.md` |
| kill 后清理 | PASS；无 `nexus-agent`/Core 残留 | `ps` 实测 |

RC3 已重新构建并安装 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`，完成真实 Divider 拖动、边界、30 轮快速往返、最大化/恢复、持久化和非法值自愈验收；详见 [`RC3_RESIZABLE_REPORT.md`](RC3_RESIZABLE_REPORT.md)。因此当前 Gate 计数为 P0=0、P1=0、P2=0、P3=0。

## RC3 Resizable 关闭记录（2026-08-18）

旧的 `BLOCKED` 行属于 2026-08-17 修复前现场记录，不代表当前构建。RC3 根因是手动 frame 布局下原生 NSSplitView tracking loop 没有交付可用拖动回调；现已由 `ResizableSplitView` 接管 `mouseDown/mouseDragged/mouseUp`，并将命中区扩大到 10px。真实安装包结果：Sidebar 220↔420、Workspace 280↔620、120 次快速拖动、1440×900↔2560×1330 最大化/恢复、360/500 重启持久化全部 PASS。

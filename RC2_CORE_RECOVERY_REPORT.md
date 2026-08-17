# AI Dev One Route 2 v0.4 RC2 — Core Recovery 验收

日期：2026-08-17
工程：`/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座`
安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
Bundle ID：`cn.nexus.desktop`
产品显示名：`AI Dev One`（`Nexus.app` 仅保留为历史兼容文件名）

## 根因

旧版 `NexusRunner` 在 `Process.terminationHandler` 中先依据 stderr 生成 `failed`，再判断 `terminationReason`。被 `SIGKILL` 的任务通常仍有 stderr，因此 signal 退出没有进入 `disconnected` 分支；旧的 `CoreRecoveryCoordinator` 只会重试原任务，不拥有进程、PID、退出原因、正常退出标志或健康检查，也没有用户可见的重启入口。

## 修复范围

- `apps/nexus-desktop/Sources/NexusDesktop/main.swift`
  - 将桌面端运行时所有权集中到 `CoreSupervisor`。
  - 记录 `process/pid/generation/manualShutdown/restartAttempt`，并绑定唯一 termination handler。
  - signal 退出优先分类为 `disconnected`，将运行中事务标为 `interrupted`，禁止自动续跑旧任务。
  - 自动健康恢复采用 1s、2s、5s 退避，最多三次；失败后进入 `failed`，不形成 crash loop。
  - `manualRestart()` 为 single-flight，重复点击不会产生第二个 Core；正常 Cmd+Q 设置 `manualShutdown`，不会触发重启。
  - 底部状态栏在断开/失败时显示“重新启动 Core”和“查看日志”，日志写入 `~/Library/Logs/AI Dev One/core-supervisor.log`，并经过脱敏。
- `apps/nexus-desktop/Sources/NexusDesktop/CoreRecovery.swift`
  - 补齐 `CoreState.stopped`，保留旧协调器作为兼容状态模型；实际生命周期由 `CoreSupervisor` 唯一管理。
- `tests/core-supervisor-unit.cjs`
  - 覆盖单一所有者、signal 优先级、1/2/5 退避、手动重启入口、无自动重放和日志入口。
- `tests/core-crash-recovery.cjs`
  - 覆盖真实运行链路所需的 disconnected/restart/interrupted 合同。
- `CORE_RECOVERY_ROOT_CAUSE.md`
  - 保存修复前两次真实 kill 复现及代码链分析。

## 自动化结果

| 检查 | 结果 | 证据 |
|---|---|---|
| Swift 类型检查 | PASS | `swiftc -typecheck apps/nexus-desktop/Sources/NexusDesktop/*.swift` |
| 桌面构建/安装 | PASS | `scripts/build-nexus-desktop`、`scripts/install-nexus-desktop`；安装包已更新 |
| CJS 回归 | PASS | 19 个测试，0 失败；`core-supervisor-unit.cjs`、`core-crash-recovery.cjs` 均通过 |
| 离线烟测 | PASS | `scripts/test-nexus`：通过 66，失败 0 |
| Rust 受影响 CLI crate | PASS | 统一 stable 1.97.1 toolchain：`cargo test -p xai-grok-pager-bin`，31+31 tests，0 failed |
| Rust 编译 warning | WARNING | `xai-grok-tools` 既有 4 条 `float_literal_f32_fallback` future-incompatible warning；本轮没有 Rust 源码改动 |
| Secret scan | PASS | `secret-redaction.cjs`：165 个 runtime JSONL，无 credential-shaped 值 |

## 真实 kill 验收

安装包 App PID：`25423`。

| 项目 | 实际结果 |
|---|---|
| kill 前任务 Core PID | `27128`（第二次长任务现场）；另一次真实 kill PID 为 `26061` |
| kill 操作 | `kill -9 27128` |
| 任务状态 | 立即停止，未产生 `end`/Completed；UI 回到 Agent 空闲，旧任务不自动续跑 |
| Core 状态链 | 日志记录 `disconnected → restarting`，第一次退避 1 秒；健康检查通过后 `ready` |
| 恢复 PID | 健康检查 PID `27174`（前一次）/本次对应健康检查由日志记录；健康检查使用 `--version`，成功后短生命周期退出 |
| 新任务 | 恢复后发送“只回复 OK，不修改文件”，真实完成；UI 显示 `Agent 完成` |
| 同时 Core 数 | 0 或 1；每次健康检查结束即清理，不存在并行 Core |
| zombie | 0；`ps` 检查无 `nexus-agent` 残留 |

## Crash loop 与手动重启验收

为避免破坏安装包，临时把本机 Application Support wrapper 替换为退出码 1 的可恢复测试文件；原 wrapper 保存在 `/tmp/ai-dev-one-core-wrapper-backup-20260817-212018/nexus`，测试后已恢复。

| 阶段 | 真实日志/结果 |
|---|---|
| 第一次失败 | `schedule restart attempt=1 delay=1.0s`，健康检查 exit=1 |
| 第二次失败 | `schedule restart attempt=2 delay=2.0s`，健康检查 exit=1 |
| 第三次失败 | `schedule restart attempt=3 delay=5.0s`，健康检查 exit=1 |
| 上限 | `state=failed`、`automatic recovery exhausted`，没有第四次 spawn |
| 失败态 UI | AX 树实际出现 `● Core 失败`、`重新启动 Core`、`查看日志`；两按钮 enabled 且 AXPress 可用 |
| 手动重启 | 点击“重新启动 Core”后 `manual restart requested`，健康检查 PID `27368`，`state=ready` |
| 重复点击保护 | `manualRestartInFlight` single-flight；合同测试通过；本次只产生一个健康检查进程 |
| 重启后任务 | 新的“只回复 OK，不修改文件”任务完成，Agent 回到完成态 |

## Resizable 状态

本轮没有修改 Resizable 架构或相关代码；仅保留既有 5px hit area、`col-resize`、窗口最小尺寸和 pane clamp。代码合同、双击恢复、非法值自愈和窗口下限已通过；真实拖动 30 次、最大化/恢复仍需用户在桌面完成最终人工验收。

## RC2 Gate 计数

- P0：0
- P1：1（仅 Resizable 真实拖动/最大化人工验收未完成；Core 生命周期阻塞已关闭）
- P2：0
- P3：0

本轮不创建 `v0.4.0-beta.1`，版本继续保持 Release Candidate，直到 Resizable 现场验收完成。

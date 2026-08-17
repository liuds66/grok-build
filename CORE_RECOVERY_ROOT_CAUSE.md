# Core Crash Recovery Root Cause

记录时间：2026-08-17

## 现场复现

使用安装包 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 启动真实任务，并在任务运行中终止实际 `nexus-agent` 子进程：

| 复现 | Core PID | 结果 |
| --- | ---: | --- |
| 第一次真实任务 | 96745 | 子进程被 `kill -9` 后退出；没有新的 Core 子进程，任务显示失败 |
| 第二次真实任务 | 97213 | 子进程被 `kill -9` 后退出；约 8 秒内没有替代进程，任务回到空闲 |

两次复现后 `nexus-agent` 子进程数均为 0，界面没有可见的“重新启动 Core”入口。

## 代码链路

1. `NexusRunner.send` 直接创建并保存 `Process`，任务结束时在 `terminationHandler` 中清空引用。
2. 退出处理先根据 stderr/stream error 生成 `failed` 事件，再检查 `terminationReason == .uncaughtSignal`。被 `kill` 的进程通常仍会留下 stderr，因此会先走 `failed` 分支，`disconnected` 分支不可达。
3. 只有 `RunnerEvent.coreState(.disconnected)` 才会触发 `MainViewController` 的 `CoreRecoveryCoordinator`；因此真实 kill 不会进入恢复调度。
4. 旧的 `CoreRecoveryCoordinator` 只调度“重新发送原任务”的闭包，不持有进程、PID、代次或应用关闭状态，也没有健康检查和手动重启入口。
5. `NexusRunner` 在 `Process.run()` 成功后立即发出 `.ready`，没有 ACP/健康检查确认；正常退出、异常退出和应用退出的生命周期也没有统一监督者。
6. `MainViewController` 仅在底部显示状态文字，没有 Core Restart action；`AppDelegate` 退出时只调用 `runner.stop()`，没有 supervisor shutdown 标志来阻止重启。

## 根因结论

这是两个相互放大的生命周期缺陷：

* **事件分类缺陷**：signal termination 被 stderr 错误文本优先级覆盖，导致 Core crash 被误报为普通任务失败。
* **所有权缺陷**：没有唯一的 Core supervisor 管理 `Process`、重启退避、健康检查、正常退出标志和手动重启；现有 recovery coordinator 只能重试任务，不能恢复 Core。

本轮修复将保留现有 Rust Core、ACP 和 Agent 工作流，仅把现有桌面端进程所有权集中到 `CoreSupervisor`，以健康检查进程完成 Core 恢复，不自动续跑已中断任务；用户可在 Core 恢复后重新运行或回滚。

## RC2 修复后证据（2026-08-17）

当前安装包 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 已实际复测：任务 PID `27128` 被 `kill -9` 后，日志记录 `disconnected`、约 1 秒后 `restarting`、健康检查通过后 `ready`；任务没有自动续跑，随后新任务完成。将本机 wrapper 临时替换为退出码 1 的测试文件后，真实日志依次记录 1 秒、2 秒、5 秒退避并进入 `failed/automatic recovery exhausted`，没有无限循环。失败态 UI 实际显示“重新启动 Core”“查看日志”，点击 Restart 后日志记录 `manual restart requested` 和 `ready`，新任务再次完成。完整数据见 [`RC2_CORE_RECOVERY_REPORT.md`](RC2_CORE_RECOVERY_REPORT.md)。

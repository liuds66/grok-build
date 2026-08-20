# AI Dev One Route 2 v0.5 Phase 3.7 — CI Recovery Root Cause

日期：2026-08-19
开发基线：`fbae9c9b54d6c12f94f7fbc20f6c52251e505b73`
Repository：`liuds66/grok-build`
现有 PR：`#2`

## 复现结论

Phase 3.6 在真实 GitHub Actions 运行期间退出并重新启动安装 App 后，远端 run 会继续执行，但桌面端不会恢复 repository、PR、run 或 `waiting_ci`。工具页也没有“停止等待”入口。

## 代码链追踪

| 链路 | 当前实现 | 结果 |
|---|---|---|
| TaskTransaction | 已有可选 `github: GitHubTaskMetadata?` | 结构存在，但桌面任务没有写入 GitHub metadata |
| TaskTransactionStore | 只支持按 taskId 读取和 upsert | 冷启动无法枚举非终态 GitHub 事务 |
| GitHubAutonomousWorkflow | 只在测试 harness 中实例化 | `main.swift` 没有任何实例或长期 owner |
| recoverAfterAppRestart | 依赖当前内存 workflow 的 metadata | 新建实例 metadata 为空，无法定位旧 PR；App 也从未调用该方法 |
| CI polling | `ciPollWorkItem` 只有 cancel，没有创建/调度路径 | 没有实际 poller 生命周期，也没有 single-poller 约束 |
| App lifecycle | `shutdownCore()` 会把活动本地任务写为 `cancelled/app_shutdown` | 没有区分可恢复的 GitHub `waiting_ci` 与用户取消 |
| Workspace GitHub UI | 仅显示静态认证和远程策略文案 | 没有真实 workflow state、PR、CI、Cancel 或 View PR 绑定 |
| cancel() | 只改变内存 metadata | 不写 TaskTransaction、没有 `CancellationSource=user`，重启后无法保持 |

## 根因

根因不是 GitHub Provider、认证、PR 或 Actions 本身，而是 **桌面 Shell 缺少 GitHub workflow 的长期生命周期 owner**：

1. PR/CI identity 从未由桌面端写入 `TaskTransactionStore`。
2. 冷启动没有枚举并恢复 `waiting_ci` 事务。
3. 恢复逻辑没有根据 repository + PR number 重新读取真实 PR/checks。
4. 没有按 taskId 唯一拥有的 CI poller；App 退出与用户 Cancel 也没有分离。
5. 工具页没有订阅 GitHub workflow state，因此用户看不到或取消不了等待流程。

## 修复边界

本轮采用最小修复：复用现有 `TaskTransaction`、`GitHubProvider` 与安全策略，增加一个桌面生命周期级 `GitHubWorkflowCoordinator`，负责 restore / reattach / poll / app-shutdown stop / user-cancel / persist，并把只读状态与两个最小操作入口接到现有工作区工具页。不重做 Provider，不改变 Rust Core、ACP、Agent Pipeline、Policy、Rollback、Keychain 或 Deep Forest 主设计。

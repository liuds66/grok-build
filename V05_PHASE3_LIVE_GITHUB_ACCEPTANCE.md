# AI Dev One Route 2 v0.5 Phase 3.5

## REAL GITHUB LIVE ACCEPTANCE

日期：2026-08-19
基线分支：`v0.5-dev`
基线提交：`9f41bf22ed946da45dbb4aad5fbe78c488c4898c`
Fork 基线远端 SHA：`9f41bf22ed946da45dbb4aad5fbe78c488c4898c`
总体结果：**PARTIAL — PR OPEN；Fork 无 CI workflow；桌面任务恢复/取消尚未接入现场链路**

本轮现场发现 2 个真实 CLI 兼容性问题（`merged` 字段、`pr create --json`），均已修复、加入回归断言并重新构建验证；当前没有遗留 P1。

本报告只记录真实 Fork `liuds66/grok-build` 的现场证据；离线 fixture 结果继续保留在 `V05_PHASE3_GITHUB_AUTONOMOUS_LOOP_REPORT.md`，不替代真实远端结果。

## 0. 仓库与认证

| 项目 | 真实结果 |
|---|---|
| Git root | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座` |
| 当前开发分支 | `v0.5-dev` |
| origin（可写 Fork） | `https://github.com/liuds66/grok-build.git` |
| upstream（只读上游） | `git@github.com:xai-org/grok-build.git` |
| GitHub 账号 | `liuds66` |
| `gh` | `2.96.0`，Keychain 登录，未写入 Token |
| Fork | `liuds66/grok-build`，`isFork=true`，父仓库 `xai-org/grok-build` |
| viewer permission | `ADMIN` |
| Fork 默认分支 | `main`（未修改） |
| Issues | **已启用**（按用户授权） |

未向 `upstream` 写入；未创建 tag、未合并、未 force push、未删除远程分支。

## 1. Issue Intake（真实仓库）

| 项目 | 结果 |
|---|---|
| Issue | [#1 Clarify GitHub remote roles in the AI Dev One tools panel](https://github.com/liuds66/grok-build/issues/1) |
| Issue body / comments | 已读取；无注入标记；作为 `UNTRUSTED_EXTERNAL_CONTENT` 处理 |
| 任务分支 | `ai-dev-one/issue-1-github-remote-roles` |
| 隔离 worktree | `/Users/mac/Library/Application Support/AI Dev One/worktrees/grok-build/task-issue-1` |
| Project Intelligence | PASS（真实工程扫描、上下文、架构桥接均通过） |
| Architect | PASS（Issue intake → planning 状态转换） |
| Builder | PASS（仅修改工具面板远端角色文案） |

Issue 选择的是低风险、可审查的真实产品改进：在 GitHub 自主工程工具面板明确显示 `origin` 为写入目标、`upstream` 为只读上游；不改变 git remote、不改变默认分支、不触碰 CoreSupervisor/ACP/Policy/Rollback/Keychain。

## 2. Builder / Reviewer / 本地验证

| 项目 | 真实结果 |
|---|---|
| 变更文件 | `apps/nexus-desktop/Sources/NexusDesktop/main.swift`；随后修复 `GitHubIntegration.swift` 并补充 `tests/github-autonomous-unit.cjs` |
| 任务提交 1 | `623e61e2efb8f6b8e5942d284d4249f11ec4fee9` |
| 任务提交 2（现场修复） | `21f7c780c969766d95ea2189195c91f60bcb8d27` |
| 任务提交 3（PR 创建兼容性修复） | `f5f47f5a3e3425a580e8574c582c162cb711ad27` |
| `bash scripts/test-nexus` | **PASS：79 通过，0 失败** |
| Swift AppKit typecheck | PASS |
| `bash scripts/build-nexus-desktop` | PASS |
| `codesign --verify --deep --strict dist/Nexus.app` | PASS |
| 安装包（隔离构建） | `/Users/mac/Library/Application Support/AI Dev One/worktrees/grok-build/task-issue-1/dist/Nexus.app` |
| Browser Verification | 本任务为原生 AppKit 工具面板，无浏览器页面；任务级标记 `SKIPPED_WITH_VALID_REASON`。完整烟测中的 Browser Verification 合约与 localhost 视觉 E2E 均 PASS。 |

### 现场复现并修复的问题

首次用真实 `GitHubCLIProvider` 读取 PR #2 时，当前 `gh 2.96.0` 返回：旧字段 `merged` 不支持。随后检查 `gh pr create --help` 又确认 `gh pr create` 不支持 `--json`。根因是两处 CLI 能力假设与实际版本不一致，不是认证或仓库权限问题。

修复：`GitHubIntegration.swift` 的 `pr view` 改为请求支持的 `mergedAt`，模型以 `mergedAt != nil` 计算 `merged`；`pr create` 改为普通 `gh pr create`，解析返回 URL 后再读取 PR 详情；`tests/github-autonomous-unit.cjs` 增加两处回归断言。修复后的真实 Provider 读 harness、离线契约和 release build 已重新通过。

## 3. 真实 GitHub Provider 读链

通过临时只读 harness（不提交、不创建资源）验证：

| 场景 | 结果 |
|---|---|
| `gh auth status` → `github_ready` | PASS |
| `getRepository(liuds66/grok-build)` | PASS；默认分支 `main` |
| `getIssue(#1)` | PASS |
| Issue 外部内容边界 | PASS |
| Workflow `intake` + `planning` | PASS |
| `getPullRequest(#2)` | PASS（修复 `mergedAt` 后） |
| 强推策略 | **DENY** |
| 自动合并策略 | **DENY** |
| Secret 输出 | harness 不打印 Token、Authorization 或 body secret |

## 4. 分支与 PR

| 项目 | 真实结果 |
|---|---|
| 任务分支已推送 | PASS，普通 push；本地/远端 SHA 均为 `f5f47f5a3e3425a580e8574c582c162cb711ad27` |
| PR | [#2 feat: clarify GitHub remote roles in tools panel](https://github.com/liuds66/grok-build/pull/2) |
| PR 状态 | OPEN，非 Draft |
| PR base | `v0.5-dev` |
| open PR 数（同 head/base） | 1（无重复 PR） |
| merge | 未执行；保持人工审核 |
| remote branch delete | 未执行 |

## 5. CI 轮询与边界

真实 Fork 当前没有 `.github/workflows`，GitHub API 返回 workflow 数量 `0`；PR checks 返回 `no checks reported on the ... branch`。因此：

- CI `queued → in_progress → PASS/FAIL`：**NOT AVAILABLE（仓库无 workflow）**；不能伪报 PASS。
- CI Repair：**NOT RUN**；没有真实失败 run 可修复。
- PR 保持 OPEN，等待人工决定是否在 Fork 配置 CI。

### Phase 3.6 CI bootstrap 记录

已在隔离 worktree 本地审计 CI bootstrap 提交 `f05cac81bcf6fbb0a0a1a7cbc3d6d093af50bd0a`；其中 workflow 使用 `pull_request`、`contents: read` 和确定性离线检查。普通推送被 GitHub 以 OAuth token 缺少 `workflow` scope 拒绝，未发生远端 ref 变化，因此本节仍保持 **NOT AVAILABLE / BLOCKED**，详见 [V05_PHASE3_6_LIVE_CI_ACCEPTANCE.md](V05_PHASE3_6_LIVE_CI_ACCEPTANCE.md)。

## 6. 尚未完成的现场项

### 应用进程烟测

隔离构建的 `dist/Nexus.app` 已真实 `open -n` 启动，5 秒后确认进程稳定；随后发送 `SIGTERM`，确认 App 及其子进程均退出。该结果只证明构建包可启动/退出，不等同于 App 内完整 GitHub 任务恢复验收。

这些不是隐藏的 PASS，当前明确标记为 **NOT RUN / BLOCKED BY PRODUCT WIRING**：

1. 通过已安装桌面 App 触发完整 Issue → Builder → commit → push → PR 链，而不是只读 harness + 手动 CLI 建 PR。
2. App 退出/重启后恢复真实 GitHub Task Transaction、已有 PR 和 CI 状态。
3. 在 App 内 Cancel 等待中的 GitHub workflow，并验证不删除远程 branch/PR。
4. 有真实 CI workflow 后再做 CI 轮询与最多 3 轮 repair。
5. Core crash 发生在 GitHub 任务中的现场中断/恢复（现有 Core/离线契约已通过）。

当前桌面端 `GitHubAutonomousWorkflow.recoverAfterAppRestart()`、`cancel()` 等契约存在，但本次现场未伪造“已接入 App 的持久化 UI”结果。

## 7. 主工作树与安全

| 项目 | 结果 |
|---|---|
| 主工作树 HEAD | `9f41bf22ed946da45dbb4aad5fbe78c488c4898c`，未被任务分支改写 |
| 主工作树代码变更 | 无；仅两份验收报告待提交 |
| 隔离 worktree | 保留，供 PR 人工审核；未删除远程分支 |
| Secret scan | 通过；报告、PR body/comment、测试输出均未写入真实 Token/Authorization/API key |
| 上游写入 | 0 |
| force push / auto merge | 0；策略 DENY |

## 8. Gate 状态

P0：0
P1：0（`merged` 字段与 `pr create --json` 两个 CLI 兼容性问题均已修复并有回归测试）
P2：1（CI workflow/真实 PR run 已通过；桌面端完整 GitHub 任务恢复/取消尚未完成现场接入）
P3：0

结论：**真实 Fork、真实 Issue、真实分支、真实 PR、真实 Provider 读链和真实 PR CI 已通过；尚未达到 v0.5 Final Integration Gate。** 剩余工作是把 GitHub workflow metadata 接入桌面任务持久化/恢复与取消链，再进行下一轮现场验收；本 PR 保持 OPEN，不自动合并。

## Phase 3.6 Live CI 更新（2026-08-19）

workflow scope 完成授权后，CI bootstrap 已通过普通 push 进入 `origin/v0.5-dev`。为避免把“无 workflow”误记为通过，实际 run 与边界如下：

| 项目 | 真实结果 |
|---|---|
| Workflow | `Pull Request Verification`（workflow id `337248289`，active） |
| 权限 | `contents: read`；无 secrets、无写权限 |
| Base push run | `32174483792`，`push`，`success` |
| PR #2 run | `32175242337`，`pull_request`，`success` |
| PR job | `Deterministic verification`，Job `95835544939`，`success` |
| PR checks | `gh pr checks 2` = pass；PR #2 仍 OPEN |
| CI bootstrap commits | `f05cac8`、`fbae9c9` |
| 任务分支同步 | 正常 merge commit `7536915`，无空提交、无 force push |
| App restart smoke | PR run in progress 期间 PID `54123 → 54613`；同一 run 最终 success，无残留 Core |
| 完整 App recovery | NOT RUN；当前 App 未接入 GitHub CI metadata 持久化 |
| waiting_ci cancel | NOT RUN；当前 App 无可操作的真实 waiting_ci 入口 |
| CI Repair | live NOT TRIGGERED；fixture PASS |
| Duplicate PR | 1（仅 #2） |
| Force push / auto merge | DENY；PR 保持 OPEN |
| Secret scan | PASS |

因此，Phase 3.6 已证明真实 Fork workflow 与真实 PR CI 可运行并成功，但由于桌面端 recovery/cancel wiring 尚未完成，P2 仍为 1；详见 [V05_PHASE3_6_LIVE_CI_ACCEPTANCE.md](V05_PHASE3_6_LIVE_CI_ACCEPTANCE.md)。

## Phase 3.7 Final Live Update（2026-08-20）

桌面端 recovery/cancel wiring 已完成并通过真实安装包验收。attempt 3 在 CI `in_progress` 期间退出/重启后，同一 `TaskTransaction`、PR #2、run `32175242337` 恢复并最终成功；attempt 5 通过 Workspace → 工具 → “停止等待”真实取消，重启和 CI late-success 后仍保持 `cancelled/user`，远程 PR/分支/CI 未被删除或取消。P2 已关闭为 0。详见 [V05_PHASE3_7_CI_RECOVERY_ACCEPTANCE.md](V05_PHASE3_7_CI_RECOVERY_ACCEPTANCE.md)。

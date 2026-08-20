# AI Dev One Route 2 v0.5 Phase 3

## GitHub Autonomous Engineering Loop（实施阶段报告）

日期：2026-08-18
开发分支：`v0.5-dev`
实施基线：`06f5548f915172403bfc52f4ee1449573ff0b00b`
Gate 状态：**IMPLEMENTED / LIVE GITHUB ACCEPTANCE PARTIAL**

本阶段已完成安全抽象、离线 fixture 闭环和桌面端接入；没有执行真实远程写操作，没有创建 v0.5 tag，也没有 push。

## 1. Architecture

- `GitHubProvider` 是唯一 GitHub 业务入口，当前 backend 为 `gh-cli`，可替换为 API provider。
- `GitHubAutonomousWorkflow` 独立管理 Issue、worktree、验证、Reviewer、commit、push、PR、CI 和恢复状态。
- 现有 CoreSupervisor、ACP、四阶段 Agent Pipeline、Project Intelligence、Verification Gate、Browser Verification 和 runtime finalization 保持不变。
- GitHub workflow state 与原有 `TaskTransactionState` 分离；GitHub 元数据以可选字段保存，兼容旧事务 JSON。

## 2. Authentication / Secret Boundary

- GitHub 状态：`github_not_configured`、`github_authenticating`、`github_ready`、`github_unauthorized`、`github_error`。
- Token 使用 macOS Keychain 服务 `com.ai-dev-one.nexus.github-token`，不会进入源码、配置明文、事务、日志或 PR body。
- `gh` 通过固定 Finder-safe 路径解析，不依赖 Finder 的 login shell PATH。
- 本机检查结果：`gh 2.96.0` 可用，已通过系统 Keychain 登录 `liuds66`；真实 Fork 的 Issue/分支/PR 读链已在 Phase 3.5 执行。

## 3. Repository Binding / Worktree

- 解析 git root、remote URL、owner/repo、remote name 和默认分支。
- 多 remote、非 GitHub remote、无法确认的绑定会进入 `repository_binding_required`，禁止自动 push。
- 每个任务使用 `~/Library/Application Support/AI Dev One/worktrees/<repo>/<task>` 隔离 worktree。
- 不执行 `reset --hard`、`clean`、stash 覆盖或用户 checkout；未提交用户现场不会被覆盖。
- 任务分支格式：`ai-dev-one/issue-<number>-<slug>`。

## 4. Remote Policy

| 操作 | Autonomous Mode 关闭 | Autonomous Mode 开启 |
|---|---|---|
| Issue / PR / CI 读取 | ALLOW | ALLOW |
| 本地 branch / commit（隔离 worktree） | ALLOW | ALLOW |
| push / create PR / update PR / comment | ASK | ALLOW |
| force push / merge / 删除远程分支 / 改 branch protection | DENY | DENY |

Issue、PR comment、CI log 均以 `UNTRUSTED_EXTERNAL_CONTENT` 包裹；其中出现“忽略规则、读取 SSH key、force push”等内容不会改变 Policy。

## 5. CI Monitor / Repair

- CI 状态支持 queued、in_progress、passed、failed、cancelled、timed_out、neutral、skipped。
- `CIFailureClassifier` 分类：test、compile、lint、typecheck、browser、dependency、environment、infrastructure、permission、unknown。
- infrastructure / permission / unknown 不自动改代码。
- 可修复代码失败最多进入 3 轮 CI Repair；每轮必须重新 Local Verification、必要时 Browser Verification、Reviewer，然后追加 commit 普通 push。
- 全部相关检查通过后状态为 `ready_for_human_merge`；不提供 merge、auto-merge 或 close PR 行为。

## 6. Offline Fixture Result

`tests/github-autonomous-unit.cjs` 已通过：

- GitHub fixture provider：PASS
- repository binding：PASS
- isolated worktree：PASS
- Issue intake / untrusted boundary：PASS
- local verify → browser verify → reviewer → commit → push → PR → CI：PASS
- duplicate PR protection：PASS（重复事件只读取原 PR）
- force push / auto merge / prompt injection：PASS（DENY）
- CI repair cap：PASS（最多 3 轮）

## 7. Existing Regression

- Swift desktop typecheck：PASS
- Project Intelligence：PASS
- Browser Verification contract：PASS
- 事务 JSON 兼容与 GitHub metadata 编解码：已纳入回归编译
- 完整 `bash scripts/test-nexus`：PASS（通过 93，失败 0）
- 桌面端 release build：PASS（`dist/Nexus.app`）
- 应用签名校验：PASS（`codesign --verify --deep --strict dist/Nexus.app`）
- GitHub autonomous fixture：PASS（`tests/github-autonomous-unit.cjs`）

## 8. Live GitHub Acceptance

当前为 PARTIAL，不是最终 Gate PASS：真实 Fork 已授权，但 Fork 没有 GitHub Actions workflow，且桌面端完整 GitHub 任务持久化/恢复与取消尚未完成现场接入。以下项目仍待现场执行：

- App 内 GitHub Auth / Issue → Project Intelligence → Architect → task worktree
- App 内 real push / PR creation（当前 PR #2 由授权 CLI 创建，Provider 读链已通过）
- CI monitor / real CI repair
- App restart with existing PR
- live cancel / Core crash during GitHub workflow
- post-live secret scan

## 9. Known Limitations

1. 本轮未新增 GitHub 登录 UI；默认 Autonomous Mode 仍关闭，工具面板显示只读状态和策略。
2. 真实远程 acceptance 已在用户授权的 Fork `liuds66/grok-build` 开始；本轮只向 Fork 写入 Issue/任务分支/PR，未向 upstream 写入。
3. Phase 3 不创建 tag、不 push、不自动 merge；最终 Gate 必须在真实远程 fixture 上重新验证。

## 10. Gate

当前不能标记 Phase 3/3.5 Final PASS。代码、release build 和离线安全闭环已准备好；Phase 3.5 已完成真实 Fork `liuds66/grok-build`、`origin/v0.5-dev` 基线推送、Issues 启用、Issue #1、隔离任务分支和 PR #2。真实 Provider 读链已通过；现场发现并修复了 `gh pr view --json merged` 不兼容，以及 `gh pr create` 错误使用 `--json` 的问题，现使用 `mergedAt` 与 create-then-readback 流程并加入回归断言。Fork 当前没有 GitHub Actions workflow，App 级 GitHub 任务恢复/取消仍未完成现场接入，详情见 `V05_PHASE3_LIVE_GITHUB_ACCEPTANCE.md`。不得修改 upstream，也不进入 v0.5 Final Integration Gate。

## Phase 3.7 状态更新（2026-08-20）

桌面端 GitHub workflow coordinator、`waiting_ci` 冷启动恢复、用户取消持久化和 late-success 防护已完成，并在真实安装 App + 真实 PR #2/run `32175242337` 上通过。旧的“桌面端未接入”描述保留为历史记录；当前 Gate 已由 P2=1 更新为 P0=0、P1=0、P2=0、P3=0。现场证据见 [V05_PHASE3_7_CI_RECOVERY_ACCEPTANCE.md](V05_PHASE3_7_CI_RECOVERY_ACCEPTANCE.md)。

### Verified Baseline Freeze（2026-08-20）

Phase 3.7 的实现、正式回归测试和真实验收证据已完成审计，Phase 3 标记为 **FROZEN**。本次封版不创建 tag、不 push、不合并 PR；后续开发不应直接写入本基线。

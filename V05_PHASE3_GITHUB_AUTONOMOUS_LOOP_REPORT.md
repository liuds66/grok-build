# AI Dev One Route 2 v0.5 Phase 3

## GitHub Autonomous Engineering Loop（实施阶段报告）

日期：2026-08-18
开发分支：`v0.5-dev`
实施基线：`06f5548f915172403bfc52f4ee1449573ff0b00b`
Gate 状态：**IMPLEMENTED / LIVE GITHUB ACCEPTANCE BLOCKED**

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
- 本机检查结果：`gh 2.96.0` 可用，但当前未登录 GitHub；因此真实 Issue/Push/PR/CI acceptance 尚未执行。

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

当前为 BLOCKED，不是代码 PASS：本机 `gh auth status --hostname github.com` 返回未登录。没有安全地替用户登录，也没有猜测测试仓库，因此以下项目待获得测试 GitHub 账号/仓库后现场执行：

- GitHub Auth
- Issue → Project Intelligence → Architect → task worktree
- real push / PR creation
- CI monitor / real CI repair
- App restart with existing PR
- live cancel / Core crash during GitHub workflow
- post-live secret scan

## 9. Known Limitations

1. 本轮未新增 GitHub 登录 UI；默认 Autonomous Mode 仍关闭，工具面板显示只读状态和策略。
2. 真实远程 acceptance 需要用户在 GitHub 测试仓库完成 `gh auth login`，并明确授权测试仓库；本地未执行任何远程写入。
3. Phase 3 不创建 tag、不 push、不自动 merge；最终 Gate 必须在真实远程 fixture 上重新验证。

## 10. Gate

当前不能标记 Phase 3 PASS。代码、release build 和离线安全闭环已准备好，但真实 GitHub Gate 仍待授权后的现场验收。建议下一步只提供隔离测试仓库和 GitHub 登录，然后执行 Live Acceptance，不进入 v0.5 Final Release Gate。

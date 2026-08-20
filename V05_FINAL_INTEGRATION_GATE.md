# AI Dev One Route 2 v0.5 Final Integration Gate

日期：2026-08-21
目标候选：`v0.5.0-beta.1`
结论：`FINAL_INTEGRATION_GATE = PASS`（保持真实 PR OPEN，等待人工合并；本轮不创建 Beta tag）

## Baseline

| 项目 | 结果 |
| --- | --- |
| Repository | `liuds66/grok-build` |
| Local repository | 当前 checkout（本机绝对路径不写入仓库） |
| Branch | `v0.5-dev` |
| Starting baseline | `e2cbdc3250a783f78b3d66aa0e49b9bcce88b707` |
| `origin/v0.5-dev` | `e2cbdc3250a783f78b3d66aa0e49b9bcce88b707`（normal push，非 force） |
| Upstream | `xai-org/grok-build`，仅只读引用，未写入 |
| Main workspace | Final Gate 前后 clean，`Main Workspace Unchanged = YES` |
| App source | `apps/nexus-desktop/Sources/NexusDesktop` |
| Rust workspace | repository root `Cargo.toml` / `crates/` |
| Installed App | `Nexus.app`（本机安装路径不写入仓库） |
| Bundle | display name `AI Dev One`；bundle id `cn.nexus.desktop`；已签名验证 |
| Installed build version | `0.5.0-beta.1`（本轮 release metadata candidate；Bundle ID、Keychain service、Application Support 和 `Nexus.app` 文件名保持兼容） |

> v0.5 Phase 1/2/3 的历史报告保留旧版本字符串作为兼容记录；本候选已在唯一权威 `Info.plist` 元数据中更新为 `0.5.0-beta.1`，没有引入第二套版本系统。

## Real Issue / Task

| 项目 | 结果 |
| --- | --- |
| Issue | [#1 Clarify GitHub remote roles in the AI Dev One tools panel](https://github.com/liuds66/grok-build/issues/1) |
| Issue trust boundary | `UNTRUSTED_EXTERNAL_CONTENT`；正文只作为需求输入，未改变 Policy、Secret Boundary、Git Boundary、Workspace Boundary 或系统指令 |
| Task ID | `2e3f6bea-b8b0-4167-ab64-f141d9667e6a` |
| Session | `final-integration-issue-1` |
| Worktree | PR task worktree（本机绝对路径不写入仓库） |
| Task branch | `ai-dev-one/issue-1-github-remote-roles` |
| Base SHA | `e2cbdc3250a783f78b3d66aa0e49b9bcce88b707` |
| Checkpoint | `32d40a8c-3a59-47f6-994d-f1029159ffdc`；真实 Git-backed snapshot 已落盘（本机存储路径不写入仓库） |

## Pipeline Gate

| 阶段 | 结果 | 证据 |
| --- | --- | --- |
| Project Intelligence | PASS | bounded context、相关文件/符号/测试由 Project Intelligence acceptance/unit 套件验证；未进行 blind 全仓库扫描 |
| Architect | PASS | Transaction pipeline 记录 `Architect → passed`；先于 Builder 执行 |
| Checkpoint | PASS | `CheckpointManager` 真实磁盘快照；本机存储路径不写入仓库 |
| Builder | PASS | 仅在隔离 worktree 修改；最终实现 commit `91b93896d7469ed9aa53ed03b63ec5e3f476e69c` |
| Incremental intelligence | PASS | Project Intelligence incremental/index/context 回归通过 |
| Local Verification | PASS | `scripts/test-nexus` clean run：`74 passed, 0 failed` |
| Browser Desktop | SKIPPED_WITH_VALID_REASON | Issue 是 native AppKit 工具面板，没有浏览器 DOM/页面表面；Browser Verification 本地 live/contract 套件仍 PASS |
| Browser Mobile | SKIPPED_WITH_VALID_REASON | 同上；无可验证的移动 Web 页面表面 |
| Rollback | PASS | 真实磁盘验证：基础 rollback `restored=3 removed=2`；extended modify/delete/add/rename/new-directory SHA-256 验证 PASS；interrupted rollback `interrupted=true rollback=true finalState=rolled_back` |
| Verifier | PASS | Transaction pipeline `Verifier → passed`；Verification Gate/项目测试 PASS |
| Reviewer | PASS | Transaction pipeline `Reviewer → passed`；只有 Verifier + Reviewer 均通过才进入完成态 |

## Core Crash / Recovery

使用实际 `CoreSupervisor` 源码与本机 Runtime wrapper 进行 live harness，未修改 Core Supervisor。为避免 Keychain 首次读取延迟，harness 使用非敏感测试占位环境变量；App 的真实 Keychain 冷启动路径另行完成并通过。

```text
state=starting
state=ready
corePidBeforeKill=22754
killSent=1
state=disconnected
recoveryState=restarting
recoveryState=starting
recoveryState=ready
corePidAfterRecovery=22773
pidChanged=true
coreStateFinal=ready
```

结果：

- Core Recovery：`PASS`
- PID changed：`YES`（`22754 → 22773`）
- duplicate Core：`0`
- zombie Core/agent：`0`（harness 与 App 退出后均用精确进程名确认）
- Core crash interruption contract：`PASS`（`core-crash-recovery.cjs`；旧任务不会被误报为 completed）
- bounded restart/backoff/single-owner/manual-restart contracts：`PASS`

## Commit / Push / PR / CI

| 项目 | 结果 |
| --- | --- |
| Task implementation commit | `91b93896d7469ed9aa53ed03b63ec5e3f476e69c`（包含 RC2/RC3 已验证实现与 Issue #1 实现） |
| Product implementation PR head | `91b93896d7469ed9aa53ed03b63ec5e3f476e69c`（后续为 Gate 报告与 release metadata 提交） |
| Release metadata commit | `bd3b7c1674163a4a2fb9716f8073d41f731b60b0`（`0.5.0-beta.1`） |
| Push | `PASS`；normal push 到 `origin`，无 `--force` / `--force-with-lease` |
| PR | [#2 feat: clarify GitHub remote roles in tools panel](https://github.com/liuds66/grok-build/pull/2) |
| PR state | `OPEN`，`MERGEABLE`，`mergeStateStatus=CLEAN` |
| Implementation CI run | [32391787146](https://github.com/liuds66/grok-build/actions/runs/32391787146)，attempt 1 |
| Final PR-head CI run | [32406138688](https://github.com/liuds66/grok-build/actions/runs/32406138688)，attempt 1；head `bd3b7c1674163a4a2fb9716f8073d41f731b60b0` |
| CI result | `PASS`；最新 Pull Request Verification / Deterministic verification success（`5m45s`） |
| Human merge | required；未自动合并、未关闭 PR、未删除分支 |

没有创建第二个 Issue、Task branch 或 PR；报告文档提交只触发了同一 PR 的一次最终 CI 重跑。现有 PR 保持 OPEN，供用户人工决定是否合并。

## App Restart / CI Recovery

真实安装 `Nexus.app` 的恢复链路使用同一个 task/session/worktree/checkpoint/PR/run：

- App 在 CI `32391787146` 仍为 `in_progress` 时退出；退出后无 App/Core/agent 残留。
- CI 在 App 停止期间完成 `success`。
- 冷启动后恢复同一 Transaction：`finalState=completed`、`workflowState=ready_for_human_merge`、`ciFinalState=passed`、PR `#2`、run `32391787146`；没有重新创建任务、worktree、分支或 PR。
- 最终安装包重新从 task worktree 构建、签名、安装并启动/退出 smoke：codesign `PASS`，退出后 Core/agent 均为 `0`；release metadata candidate 直接读取 Bundle 版本为 `0.5.0-beta.1`。

结果：`App restart during CI = PASS`、`CI Recovery = PASS`、`Duplicate poller = 0`。

## Remote / Safety / Secret Boundary

| 检查 | 结果 |
| --- | --- |
| origin role | writable development remote；本次只做正常 branch push |
| upstream role | read-only；无 upstream push/PR/write |
| Force push | `DENY`；未执行 |
| Auto merge | `DENY`；未执行 |
| Default branch write | `DENY`；未执行 |
| Remote config mutation | `DENY`；Issue #1 仅显示 origin/upstream 角色 |
| Prompt injection | `PASS`；GitHub autonomous policy/issue-intake contract 通过，外部正文未越权 |
| Workspace boundary | `PASS`；Builder 只写 task worktree，main workspace 未变 |
| Secret scan | `PASS`；`secret-redaction.cjs` 扫描 185 个 runtime JSONL，无 credential-shaped 值；Transaction、Core log、报告均无 API key/Bearer/Authorization/password |
| Process cleanup | `PASS`；App Cmd+Q/TERM 后无 `Nexus`、`ai-dev-one-core`、`nexus-agent` 残留 |

## Verification Detail

Clean final regression command：

```text
NEXUS_NODE_BIN="<bundled-node>" CI=true NEXUS_SKIP_AGENT=1 bash scripts/test-nexus
```

结果：`74 passed, 0 failed`。

额外真实回归：

- checkpoint/rollback：PASS（基础、extended、interrupted 三组均验证磁盘内容）
- task transaction：`transaction=PASS redaction=PASS persistence=PASS github-metadata=PASS`
- core supervisor：single-owner/backoff/manual-restart PASS；crash recovery bounded retry/interrupted PASS
- policy：危险命令 deny wiring PASS；GitHub remote/force-push/merge safety contracts PASS
- verification gate：`unknown=SKIPPED node-plan=PASS`
- browser verification driver/security/layout/local-live：PASS（native AppKit UI 依法跳过 desktop/mobile DOM 验证）
- Swift desktop typecheck：PASS
- desktop build：PASS，task worktree 重新构建 `Nexus.app`
- codesign：`codesign --verify --deep --strict` PASS
- installed App launch/quit：PASS

Deterministic regression 的既有提示保持公开记录：

- deterministic mode 跳过本机编码代理/CLI/settings runtime check；
- 当前源码不在外置容器，外置链接测试跳过；
- `scripts/test-nexus` 未指定 `--gui`，不会主动启动桌面进程。

这些 skip 不替代本次已经完成的 live Agent/Core/App/GitHub 验证，因此不降低 Final Integration Gate 结论。

## Final Gate Counts

```text
P0 = 0
P1 = 0
P2 = 0
P3 = 0
```

未发现 Secret leak、错误仓库写入、force push、自动合并、用户工作区污染、rollback corruption、duplicate PR、false CI PASS、Core crash data loss 或 App restart state corruption。

## Result

`Issue → Project Intelligence → Architect → isolated worktree → Checkpoint → Builder → Local Verification → Core Crash/Recovery → Verifier → Reviewer → Commit → Push → PR → real GitHub CI → App restart recovery → READY_FOR_HUMAN_MERGE`：`PASS`。

实现基线 / Product implementation commit：`91b93896d7469ed9aa53ed03b63ec5e3f476e69c`；release metadata commit：`bd3b7c1674163a4a2fb9716f8073d41f731b60b0`。其后仅追加本报告文档提交，未再改变产品代码。本报告是集成 Gate 记录，不创建 `v0.5.0-beta.1` tag，不执行 merge，不向 upstream 写入。

建议：允许进入 `v0.5.0-beta.1 FINAL BASELINE FREEZE` 流程；候选 Bundle 已为目标 v0.5 版本，当前仅等待用户人工合并 PR #2。

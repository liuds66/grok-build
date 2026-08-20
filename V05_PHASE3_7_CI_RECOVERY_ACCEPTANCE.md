# AI Dev One Route 2 v0.5 Phase 3.7

## LIVE CI RECOVERY + CANCELLATION ACCEPTANCE

日期：2026-08-20
分支：`v0.5-dev`
代码基线（Phase 3.6）：`fbae9c9b54d6c12f94f7fbc20f6c52251e505b73`
真实仓库：`liuds66/grok-build`
真实 PR：[#2](https://github.com/liuds66/grok-build/pull/2)
Workflow：`Pull Request Verification`（id `337248289`）
CI run：`32175242337`（同一 run 的多次 rerun attempt；未创建新 run/PR）

本报告是 Phase 3.7 的现场验收记录。所有涉及远程仓库的操作均复用既有 PR #2，未创建专用仓库、未新增 PR、未合并、未关闭 PR、未删除分支、未执行 force push。

安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
Bundle Identifier：`cn.nexus.desktop`
用户可见版本：`0.4.0-beta.1`
签名校验：`codesign --verify --deep --strict` PASS

## 1. 根因与修复范围

根因详见 [V05_PHASE3_7_CI_RECOVERY_ROOT_CAUSE.md](V05_PHASE3_7_CI_RECOVERY_ROOT_CAUSE.md)：桌面端原先没有长期持有 GitHub workflow 的 owner，`TaskTransactionStore` 不能枚举等待中的事务，App 退出与用户取消也没有分离，因此 `waiting_ci` 无法冷启动恢复，工具页没有取消入口。

修复采用既有 `TaskTransaction` 作为唯一持久化记录，新增 `GitHubWorkflowCoordinator` 负责 restore / reattach / poll / cancel / app-shutdown stop，并将真实状态接入现有 Workspace 工具页；没有修改 Rust Core、ACP、Policy、Rollback、Agent Pipeline 或 Deep Forest 主布局。`MainViewController.updateTransaction` 现在会把进入 `waiting_ci` 的同一事务交给 coordinator，避免只恢复测试种子而漏掉真实运行任务。

## 2. 真实身份与安全边界

| 项目 | 实际结果 | 结论 |
|---|---|---|
| PR | #2，`OPEN` | PASS |
| PR head | `ai-dev-one/issue-1-github-remote-roles` @ `753691525e76206c5f4d9092cbd96a6c747def8e` | PASS |
| PR 数量 | 同一 head/base 仍为 1 | PASS |
| CI run identity | `32175242337`，attempt 3/4/5，未产生第二个 run identity | PASS |
| 远程 PR/分支/CI 删除或取消 | 未执行 | PASS（用户取消只停止本地自动处理） |
| Secret 输出 | 事务、报告、UI、CLI 输出均不包含 token、Authorization 或 API key | PASS |

## 3. App Restart / `waiting_ci` 恢复

测试任务：`874cf0aa-8416-444d-a992-d2575b9cd05c`
CI：run `32175242337`，attempt `3`，重启时真实状态 `in_progress`。
PR：仍为 #2；没有创建新 PR。

| 步骤 | 真实观察 | 结果 |
|---|---|---|
| CI 运行期间退出 App | App 进程正常退出；任务持久化为 `reviewing / waiting_ci` | PASS |
| 冷启动安装包 | 新 App 进程启动；coordinator 枚举并重新读取同一 PR/checks/run | PASS |
| 恢复后的身份 | taskId、PR #2、run `32175242337`、attempt 3 保持不变 | PASS |
| CI 完成 | `in_progress → success`；任务变为 `ready_for_human_merge`，外层事务完成 | PASS |
| 远程副作用 | PR 仍 `OPEN`，head SHA 不变，无第二 PR、无自动合并 | PASS |
| 退出清理 | Cmd+Q 后 App/子进程清理，无残留 GitHub poller 进程 | PASS |

`waiting_ci` 不是终态；App shutdown 只停止本地观察，不写入 `cancelled/app_shutdown`，因此该任务可在下次启动继续接管。

## 4. App 内用户取消 / 持久化

测试任务：`727fc9f8-438f-4249-8d22-50afa3a9f0ec`
CI：同一 run `32175242337`，attempt `5`，取消时真实状态 `in_progress`。
App 进程：取消前 `3695`；退出后无残留；随后冷启动进程 `4215`。

| 步骤 | 真实观察 | 结果 |
|---|---|---|
| 打开 Workspace → 工具 | 动态 GitHub 区域显示同一 PR/CI 任务 | PASS |
| 点击“停止等待” | 真实 UI 弹出确认框，明确说明不会删除/取消远程 PR、分支、CI | PASS |
| 确认取消 | `finalState=cancelled`、`githubWorkflowState=cancelled`、`cancellationSource=user` | PASS |
| 远程资源 | PR #2 仍 `OPEN`，分支及 head SHA 不变，CI 仍继续运行 | PASS |
| 退出后重启 | 取消状态从 `TaskTransactionStore` 恢复；没有重新创建 poller | PASS |
| late-success | attempt 5 最终 `success` 后，任务仍保持 `cancelled/user`，没有被改成 completed | PASS |
| 新任务入口 | 取消后不自动重跑旧任务；用户可重新提交新任务 | PASS |

## 5. 单 poller / 幂等契约

| 测试 | 结果 |
|---|---|
| `restore()` 重复调用 | PASS：同一 task 只有一个监控实例 |
| late callback after cancel | PASS：忽略，不重新调度 |
| 同一 task/rerun identity | PASS：taskId/PR 保持不变，run attempt 更新 |
| `TaskTransaction` 强制持久化 | PASS |
| `waiting_ci` 阻止错误 completed | PASS |

## 6. 自动回归

| 命令/场景 | 真实结果 |
|---|---|
| `tests/github-ci-recovery.cjs` | PASS：quit-recovery、downtime-ci-pass、user-cancel-no-remote-mutation、cancel-persistence-late-pass、duplicate-restore-single-poller、rerun-identity-same-task、workflow-run-error-retry |
| `tests/github-autonomous-unit.cjs` | PASS：Provider、worktree、policy、PR readback、CI repair cap |
| `tests/task-transaction.cjs` | PASS：persistence、redaction、GitHub metadata |
| `NEXUS_NODE_BIN=…/node CI=true NEXUS_SKIP_AGENT=1 bash scripts/test-nexus` | **PASS：88 通过，0 失败**（包含 Swift desktop typecheck、Project Intelligence、Browser Verification、GitHub recovery contract 与全部源代码契约） |
| `git diff --check` | PASS |
| Desktop rebuild/install after final coordinator fix | PASS；`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`，签名校验 PASS，1440×900 启动/退出 PASS |
| 真实 GitHub PR CI attempt 3 | PASS（success） |
| 真实 GitHub PR CI attempt 5 | PASS（success；取消任务仍保持 cancelled） |

## 7. Gate

| 优先级 | Phase 3.7 前 | 现场验收后 |
|---|---:|---:|
| P0 | 0 | 0 |
| P1 | 0 | 0 |
| P2 | 1（桌面 waiting_ci 恢复/取消未接入） | **0** |
| P3 | 0 | 0 |

结论：**Phase 3.7 的 App restart recovery、用户取消持久化和 late-success 防护均已在真实安装 App + 真实 PR/CI 上通过。** 本阶段不创建 tag、不合并 PR、不 push 新代码；后续若进入 Phase 3.8，应继续沿用同一 TaskTransaction/Coordinator 边界。

## 8. Phase 3 Verified Baseline Freeze（2026-08-20）

本报告随 Phase 3.7 实现、回归测试和正式验收证据进入冻结基线。冻结动作仅包含审计、精确暂存、提交和本地验证；不创建 tag、不 push、不合并 PR。

| Gate | 冻结前最终结果 |
|---|---:|
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |
| `scripts/test-nexus` | 88 通过 / 0 失败 |
| GitHub recovery contracts | PASS |
| Secret scan | PASS |
| Desktop build / sign / launch / quit | PASS |

**Phase 3 状态：FROZEN（Verified Baseline）。** 后续变更必须进入下一阶段分支或按项目既有开发流程进行，不得回写本冻结基线。

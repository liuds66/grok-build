# AI Dev One Route 2 v0.5 Phase 3.6 — Live CI Acceptance

状态：**未完成（GitHub workflow scope 阻塞）**

本报告记录本轮真实 CI bootstrap 尝试；不把“本地模拟通过”或“no checks reported”记为真实 GitHub CI PASS。

## 远端与基线

| 项目 | 结果 |
|---|---|
| Repository | `liuds66/grok-build` |
| Upstream（只读） | `xai-org/grok-build` |
| Branch | `v0.5-dev` |
| 原始基线 | `9f41bf22ed946da45dbb4aad5fbe78c488c4898c` |
| 真实 PR | [#2](https://github.com/liuds66/grok-build/pull/2)，保持 OPEN |
| Task branch | `ai-dev-one/issue-1-github-remote-roles` |
| CI bootstrap worktree | `/Users/mac/Library/Application Support/AI Dev One/worktrees/grok-build/ci-bootstrap` |

## CI Bootstrap（本地已审计，尚未推送）

本地提交：`f05cac81bcf6fbb0a0a1a7cbc3d6d093af50bd0a`（`ci: add pull request verification`）。

新增内容仅限：

- `.github/workflows/pr-verification.yml`：`pull_request` 到 `v0.5-dev`，`contents: read`，`macos-14`，超时 30 分钟，按 PR 并发取消；无 secrets、无发布/合并/写权限。
- `scripts/test-nexus`：仅在 `CI=true` 且显式 `NEXUS_SKIP_AGENT=1` 时跳过本机编码代理检查；本地默认路径不变。

本地 CI 模拟结果：`CI=true NEXUS_SKIP_AGENT=1 bash scripts/test-nexus` **71/0 PASS**；全部 CJS 回归测试 PASS；YAML 解析 PASS。

## 真实 GitHub 推送阻塞

首次普通推送到 `origin/v0.5-dev` 被 GitHub 拒绝：

> refusing to allow an OAuth App to create or update workflow `.github/workflows/pr-verification.yml` without `workflow` scope

这是当前 `gh` OAuth token 的授权范围问题，不是 workflow 内容或仓库分支保护失败。当前 token scopes 为 `gist`, `read:org`, `repo`；GitHub 连接器也只有 `pull: true`、`push: false`。未进行 force push，`origin/v0.5-dev` 仍为原始基线。

已启动 `gh auth refresh --hostname github.com --scopes workflow` 的设备授权流程，等待已登录 GitHub 用户完成一次授权；未记录 token 或 API key。

## Gate 结果（截至本报告）

| Test | Expected | Actual | Result | Evidence |
|---|---|---|---|---|
| Workflow bootstrap | workflow 可安全推送到 origin/v0.5-dev | 本地提交通过；远端推送被缺少 `workflow` scope 拒绝 | **BLOCKED** | `f05cac8`; push error above |
| Real CI queued → in_progress → completed | 必须观察真实 run | 未触发；origin 尚无 workflow | **NOT RUN** | `gh pr checks 2`: no checks reported |
| App restart during CI | 同一 PR/run 恢复 | 无真实 CI run，未执行 | **NOT RUN** | 依赖上一步 |
| Cancel waiting_ci | cancelled 持久化 | 无真实 waiting_ci，未执行 | **NOT RUN** | 依赖上一步 |
| CI Repair live | 自然失败才触发 | 本轮无真实失败 | **NOT TRIGGERED** | fixture regression 已 PASS |
| Force push policy | DENY | DENY | **PASS** | 既有 provider/contract evidence |
| Auto merge policy | DENY | DENY | **PASS** | 既有 provider/contract evidence |
| Secret scan | 0 real secret leaks | 0 | **PASS** | existing secret-redaction suite |

本机 post-merge `bash scripts/test-nexus` 在 Browser Verification acceptance harness 启动 WebKit 时长时间无输出，因不影响已完成的真实 CI、且避免留下本地测试进程，已终止该本地进程；此前同一脚本与全部 CJS 在隔离构建中通过，且本轮真实 PR CI 的 `scripts/test-nexus` 等价 deterministic smoke 与全部 CJS 均 **PASS**。该本机 GUI harness 行为记录为环境警告，不改写 CI 结论。

## 安全边界

- 未向 `upstream` 写入。
- 未修改 `origin/main`、未创建 tag、未合并 PR、未 force push。
- workflow 不使用仓库 secrets，不打印环境变量，不使用 `pull_request_target`。
- 主工作树代码未被 CI bootstrap 修改；改动在隔离 worktree。

## 当前 Gate

P0 = 0，P1 = 0，P2 = 1，P3 = 0。由于尚未有真实 CI run，不能进入 Phase 3 Final Integration Gate，也不能把 PR #2 标为 `READY_FOR_HUMAN_MERGE`。

## Live Acceptance Update（2026-08-19）

### Workflow 与真实 CI

设备授权完成后，`workflow` scope 已确认到账。CI bootstrap 通过普通 push（没有 force push）进入 `origin/v0.5-dev`：

| 项目 | 结果 |
|---|---|
| 初始 workflow commit | `f05cac81bcf6fbb0a0a1a7cbc3d6d093af50bd0a` |
| push-trigger 增补 commit | `fbae9c9b54d6c12f94f7fbc20f6c52251e505b73` |
| workflow id | `337248289` |
| workflow | `Pull Request Verification`，active |
| 权限 | `contents: read`；无 secrets、无写权限 |
| push run | `32174483792`，`push`，`success` |
| PR #2 run | `32175242337`，`pull_request`，`success` |
| PR job | `Deterministic verification`，`success`，Job `95835544939` |
| PR 检查 | `gh pr checks 2` 显示 `pass`；PR #2 保持 OPEN |

为让同一真实 PR 触发 workflow，在 base 更新后以正常方式同步 `origin/v0.5-dev` 到任务分支，产生合并提交 `753691525e76206c5f4d9092cbd96a6c747def8e`；没有空提交、没有 force push，也没有创建第二个 PR。GitHub run 实际观察到检查 pending/in_progress，最终 completed/success。

### App restart during CI

在 PR run `32175242337` 的 job 处于 `in_progress` 时，对安装包 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 做了真实退出/重启：

| 项目 | 结果 |
|---|---|
| 退出前 App PID | `54123` |
| 重启后 App PID | `54613` |
| 退出期间残留 Core / child | `0` |
| 同一 PR/run 是否继续完成 | 是；同一 run `32175242337` 最终 success |
| App 是否恢复 repository/issue/task branch/PR/run 持久化元数据 | **NOT RUN / PRODUCT WIRING 未接入** |

因此只能把进程级退出/重启烟测记为 PASS，不能把完整 App recovery gate 伪报 PASS。

### Cancel / repair / safety

| Gate | 结果 |
|---|---|
| Cancel waiting_ci 与重启后持久化 | **NOT RUN**；当前桌面端没有可操作的 GitHub waiting_ci 任务入口 |
| CI Repair live | **NOT TRIGGERED**；本轮真实 CI 首次成功 |
| CI Repair fixture | PASS（`ci-repair-cap`） |
| Force push | DENY（`policy-force-push-merge-injection`） |
| Auto merge | DENY；PR #2 保持 OPEN |
| Prompt injection boundary | PASS（Issue/PR/CI 外部内容按 untrusted 处理） |
| Duplicate protection | PASS；同一 head/base 仅 PR #2 一个 |
| Secret scan | PASS；runtime JSONL 185 个文件、报告和 workflow 均无真实凭据 |

当前 Gate 仍为 P0=0、P1=0、P2=1、P3=0；阻塞项仅为桌面端 GitHub CI recovery/cancel 尚未真正接入并现场验证。

## Phase 3.7 Recovery / Cancellation Update（2026-08-20）

Phase 3.7 已完成桌面端长期协调器接入，并在同一真实 PR #2、同一 run `32175242337` 上完成现场验收：

- App 在 attempt 3 `in_progress` 期间退出并重启；同一 task/PR/run 恢复，最终 CI success，事务进入 `ready_for_human_merge`。
- App 内工具页真实点击“停止等待”，attempt 5 任务持久化为 `cancelled/user`；PR 仍 OPEN，远程 CI 未被取消。
- 退出后再次启动、以及 CI late-success 后，取消状态仍保持 `cancelled`，没有重新 poll 或 completed。
- 离线 recovery/cancellation contract、TaskTransaction persistence/redaction、真实 PR CI 均 PASS。

完整证据见 [V05_PHASE3_7_CI_RECOVERY_ACCEPTANCE.md](V05_PHASE3_7_CI_RECOVERY_ACCEPTANCE.md)。因此本报告此前的 P2=1 已由 Phase 3.7 关闭；当前 P0=0、P1=0、P2=0、P3=0。

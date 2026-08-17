# AI Dev One Route 2 v0.4 · Reliable Autonomy QA Report

日期：2026-08-15
范围：桌面端可靠性、恢复、安全策略、checkpoint/rollback、任务审计、Agent 状态机、验证 gate、现有 UI 回归。
明确不在本轮范围：Deep Forest 三栏视觉重设计、Rust Core/ACP 架构重写。

## 执行环境与基线

| 检查 | 真实结果 | 日志 |
| --- | --- | --- |
| Swift Renderer typecheck | PASS，无编译错误/警告 | `/tmp/ai-dev-one-v04/typecheck-final-3.log` |
| 桌面构建 | PASS，生成并签名 `Nexus.app` | `/tmp/ai-dev-one-v04/build-final.log` |
| 桌面安装 | PASS，已安装到外置盘并更新桌面入口 | `/tmp/ai-dev-one-v04/install-final.log` |
| `scripts/test-nexus --gui` | PASS：67 通过，0 失败 | `/tmp/ai-dev-one-v04/test-nexus-final-3.log` |
| 新增 v0.4/既有 CJS + Swift harness | PASS：14 个测试入口全部通过 | `/tmp/ai-dev-one-v04/all-tests-final-2.log` |
| `git diff --check` | PASS | 终端结果，无输出 |
| `npm run typecheck` | WARNING：仓库无 `package.json`，且系统无 npm（exit 127） | `/tmp/ai-dev-one-v04/npm_run_typecheck.log` |
| `npm test` | WARNING：仓库无 `package.json`，且系统无 npm（exit 127） | `/tmp/ai-dev-one-v04/npm_test.log` |
| `npm run build` | WARNING：仓库无 `package.json`，且系统无 npm（exit 127） | `/tmp/ai-dev-one-v04/npm_run_build.log` |

## P0 Critical（4 项）

### P0-1 Keychain cold start

- 测试条件：启动桌面应用并写入 layout probe；当前登录会话没有可读凭据；同时检查安全存储代码的超时、单飞和主线程隔离。
- 预期：Renderer 不等待 Security.framework；状态可落在 `loading_credentials` / `credentials_ready` / `credentials_missing` / `credentials_denied` / `credentials_error`；不重复弹钥匙串请求。
- 真实结果：PASS。启动探针在正常窗口内完成，`model.hasAPIKey=false`，没有白屏；`SecureCredentialStore.load(timeout: 2.5)`、`loadInFlight`、`Thread.isMainThread` 和不可交互 `LAContext` 已接入。
- 日志：`/tmp/ai-dev-one-v04/layout.txt`、`/tmp/ai-dev-one-v04/reliability-tests-2.log`。
- 限制：本机本轮没有执行 macOS 注销/重启用户会话后的人工钥匙串授权流程；该项仍需在有凭据的机器上做一次人工验收。

### P0-2 Core crash recovery

- 测试条件：验证 `CoreState` 转移、1/2/5 秒退避、最大重启次数、任务 `interrupted` 记录；检查 `NexusRunner` 非正常退出路径。
- 预期：`ready → disconnected → restarting → ready`；最多三次自动恢复；失败后显示“Core 无法恢复”；任务不能伪装成 completed。
- 真实结果：PASS（代码路径与状态机 harness）；非零/信号退出会进入 disconnected，重试使用 1/2/5 秒，耗尽后保留 `interrupted`。
- 日志：`/tmp/ai-dev-one-v04/reliability-tests-2.log`、`/tmp/ai-dev-one-v04/test-nexus-final-3.log`。
- 限制：由于当前环境没有有效模型凭据，本轮未在真实运行中的 API 任务上 kill 子进程；建议 v0.4 第二阶段用 Accessibility/测试模型完成一次人工 kill 验收。

### P0-3 Policy Engine real enforcement

- 测试条件：将高风险 deny 规则显式传给现有 Rust runtime：`rm -rf`、`sudo`、force push、reset hard、clean、递归 chmod、`.env`、`.ssh`、`id_rsa` 等；验证 Rust CLI 接受重复 `--deny` 参数。
- 预期：命令/文件操作在真正执行前经过 Rust policy engine；危险项 deny，不依赖 Agent prompt。
- 真实结果：PASS（运行时接线与 CLI 参数解析）；`nexus-agent --deny ... --help` 实际返回 0，所有 deny 规则从桌面端传入 Rust；Rust 仓库已有 `gate_preflight`、Bash command gate 和 shell-file gate。
- 日志：`/tmp/ai-dev-one-v04/policy-cli-help.log`、`/tmp/ai-dev-one-v04/reliability-tests-2.log`。
- 限制：没有执行真实破坏性命令（这是有意的安全约束），也没有 cargo 可用于重跑 Rust 全量测试；危险场景需在隔离 fixture 中补充 live tool-call 验收。

### P0-4 Checkpoint / rollback

- 测试条件：真实临时项目中创建 checkpoint；修改 3 个文件，新增 2 个文件，删除 1 个文件；执行 rollback；读取磁盘内容并比较文件集合和 digest。
- 预期：修改恢复、新文件消失、删除文件恢复，磁盘状态与 checkpoint 一致。
- 真实结果：PASS：`verified=true restored=3 removed=2`；不是 UI 假状态，而是实际磁盘验证。
- 日志：`/tmp/ai-dev-one-v04/all-tests-final-2.log`。

## P1 High（4 项）

### P1-1 Transactional Task

- 测试条件：创建/持久化 `TaskTransaction`，写入 checkpoint、stage、commands、verification、finalState；重载 JSON；检查命令密钥脱敏。
- 预期：状态支持 `created/planning/building/testing/reviewing/completed/failed/cancelled/interrupted/rolled_back`；审计数据可恢复且不泄露 API key。
- 真实结果：PASS。事务落在 `Application Support/Nexus/task-transactions.json`；测试确认 persistence 与 `[REDACTED]`。
- 日志：`/tmp/ai-dev-one-v04/all-tests-final-2.log`。

### P1-2 Agent Pipeline state machine

- 测试条件：Architect→Builder→Verifier→Reviewer 正常转移；尝试并发激活；Architect 失败后检查后续阶段。
- 预期：单一 active；后续阶段 waiting/skipped；只有 Verifier 与 Reviewer passed 才能 completed。
- 真实结果：PASS。harness 输出 `single-active=PASS downstream-skip=PASS`，Renderer 结束路径增加 verification gate 和完成闸门。
- 日志：`/tmp/ai-dev-one-v04/all-tests-final-2.log`。

### P1-3 Verification gate

- 测试条件：Node/Rust/Python/Go/Firmware/未知项目识别；缺少命令或脚本；安全命令按顺序执行并返回 PASS/FAIL/SKIPPED。
- 预期：缺少命令是 SKIPPED，不伪装失败；失败阻止 completed。
- 真实结果：PASS（项目识别、命令计划、未知项目 SKIPPED、Node 脚本计划）；桌面任务结束时异步运行 gate。
- 日志：`/tmp/ai-dev-one-v04/all-tests-final-2.log`。
- 限制：当前仓库没有 Node `package.json`，系统 PATH 没有 cargo；没有对真实项目执行完整编译矩阵。

### P1-4 Resizable validation

- 测试条件：启动自愈、窗口 bounds、默认三栏、Chat 最小宽度；layout probe。
- 预期：BrowserWindow 不受 pane fitting size 影响，至少 `1180×720`；默认 `1440×900`；pane 状态独立持久化。
- 真实结果：PASS（自动探针）：`window={{560,300},{1440,900}}`、Sidebar `260`、Chat `810`、Workspace `340`；`scripts/test-nexus --gui` 67/0。
- 限制：Accessibility 权限不可用，无法用真实鼠标连续拖动 30 次；此前已有 pane clamp/restore 静态与窗口矩阵测试，物理拖拽建议人工补测。

## P2 Medium（3 项）

### P2-1 API error / Composer UX

- 真实结果：PASS。错误卡缩短为紧凑标题+操作按钮；API 配置异常时显示“模型配置异常”，Composer placeholder 为“请先完成模型配置”，发送按钮禁用；配置恢复后重新启用。
- 日志：`/tmp/ai-dev-one-v04/all-tests-final-2.log`、`/tmp/ai-dev-one-v04/test-nexus-final-3.log`。

### P2-2 中文与 Workspace 限制

- 真实结果：PASS。Bottom Bar 使用“模型就绪/模型配置异常/Agent 空闲”等中文；Recent Changes 保持中文；现有 Workspace 首屏限制 50 项与长路径 tooltip 仍通过回归。
- 日志：`/tmp/ai-dev-one-v04/test-nexus-final-3.log`。

### P2-3 npm 命令契约

- 真实结果：WARNING，不是应用失败：当前项目是 Swift/AppKit 原生桌面端，没有 `package.json`，因此用户要求的 npm 三条命令无法执行；对应日志已保存并在上表列明。

## P3 Polish（0 项）

本阶段没有新增视觉重构或低优先级 polish 项，保留 v0.3 Deep Forest UI 不变。

## 未解决问题与风险

1. 没有代码级 P0 阻塞；但真实 API 任务中的 kill/restart、冷启动钥匙串授权、破坏性命令的隔离 live tool-call 仍属于人工/隔离环境验收项。
2. 当前环境没有 cargo/npm，无法声称 Rust 全量测试或 npm 测试通过；本轮没有隐藏这些 warning。
3. 真实鼠标拖拽需要 macOS Accessibility 权限，本轮只完成自动窗口/layout 证据。

## 结论

- Core crash：具备限次自动恢复和 interrupted 语义；代码级 PASS，live kill 仍待人工验收。
- Rollback：已通过真实临时磁盘内容验证，PASS。
- Policy：危险 deny 规则已在真正启动 Rust runtime 前接线并验证 CLI 解析；未执行破坏性命令，隔离 live tool-call 待补。
- Keychain cold start：有超时、单飞、非交互读取和五态模型；启动不阻塞，PASS，重启用户会话待人工验收。
- 未解决 P0：0 个代码级 P0；上述三项环境限制不应被标记为“已完成的现场验收”。
- 是否建议进入 v0.4 第二阶段：建议。在进入前，优先补做真实模型任务 kill/restart、Keychain 冷启动和 Accessibility 拖拽验收；不需要继续重构 UI。

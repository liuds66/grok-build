# AI Dev One Route 2 v0.5 Phase 2.6

## Live Task Finalization / Cancellation Race

日期：2026-08-18
分支：`v0.5-dev`
修复前基线：`f89ecb42e2bedbf7b38151d03fc8507ed0490edf`

## 1. 真实复现与根因

此前的任务结束处理把 `RunnerEvent.failed` 的本地化文本当作取消原因：只要错误文本包含“停止”或 `cancel`，`MainViewController` 就把事务写成 `cancelled`。同时，`CoreSupervisor` 的进程终止回调、用户 Stop、浏览器验证回调和运行时 `end` 没有共享一个终态守卫，因此这些事件可以在不同顺序到达。

真实历史任务 `29e1b0ee-4c5a-43ed-a8f7-d468dbebd455` 的记录是：运行时尚未发出权威 `end`，用户停止路径触发 `CoreSupervisor.stop()`，随后终止回调发出“任务已停止”，事务被标为 `cancelled`。浏览器验证的 `finishResult` 本身没有调用父任务的 `runner.stop()`；问题在于父任务没有显式取消来源和不可逆终态，导致任何类似文本都可能被误判为用户取消。

另外，复跑 live task 时发现一个会放大该问题的阻塞：每个模型 token 都在 AppKit 主线程同步重写完整 `task-transactions.json`。长 Planning 输出时主线程 CPU 达约 94%，任务看起来像卡死。该问题已通过持久化节流与审计数组上限修复，内存中的事务仍保持完整，终态会强制落盘。

## 2. 修复后的事件链

现在的结束链是：

```text
Runtime end (authoritative)
        │
        ├─ Browser PASS（桌面端、移动端，顺序可交换）
        │
        └─ Reviewer PASS
                │
             completed
```

只有显式 `requestCancel(source:)` 才能进入 `cancelled`；Core 进程丢失只进入 `interrupted`；浏览器/开发服务器清理只记录清理事件，不会取消父任务；任何终态之后到达的 `end`、重复回调或 Reviewer 回调都会被忽略。

## 3. 修改文件

- `apps/nexus-desktop/Sources/NexusDesktop/TaskFinalization.swift`
  - 新增独立终态协调器、单调时钟 trace、终态守卫、Reviewer gate。
- `apps/nexus-desktop/Sources/NexusDesktop/TaskTransaction.swift`
  - 增加显式 `TaskCancellationSource`、不可逆终态、旧 JSON 兼容解码。
  - 事务落盘节流（150ms）和每类审计数组最多保留 500 条持久化记录；终态强制写盘。
- `apps/nexus-desktop/Sources/NexusDesktop/main.swift`
  - `RunnerEvent.failed` 携带显式取消来源。
  - 用户 Stop、Core crash、App shutdown 分流。
  - runtime `end` 唯一触发验证；桌面端通过后自动进行移动端 Browser Verification。
  - 浏览器清理与父任务终态解耦。
- `tests/task-finalization-race.cjs`
- `tests/task-finalization-race-harness.swift`
  - 覆盖 A–F 顺序、取消/中断优先级、重复 end、Reviewer gate。
- `tests/core-crash-recovery.cjs`
  - 更新契约匹配显式 `coreCrash` 来源参数。

## 4. 回归测试

`tests/task-finalization-race.cjs`：

```text
PASS task finalization/cancellation race contract:
race=A/B/C/D/E/F PASS reviewer-gate PASS terminal-guard PASS
```

`tests/task-transaction.cjs`：

```text
transaction=PASS redaction=PASS persistence=PASS
PASS task transaction persistence/redaction
```

Swift 全桌面源类型检查：PASS。

`bash scripts/test-nexus`：PASS（通过 82，失败 0）。

全部 CJS 回归：PASS；`tests/secret-redaction.cjs` 扫描 185 个运行时 JSONL 文件无凭据形态值。

## 5. 真实 DeepSeek live task

测试项目：`/tmp/ai-dev-one-live-fixture.xWcP8Z`
任务/事务：`8c254143-d40a-4321-840c-9ab61e2b5b90`
会话：`ab07b2a3-479c-43e1-b522-a31930ba4ef5`
Checkpoint：`4b519a41-5653-4578-afa5-d552bbb6475e`
最终状态：`completed`
运行时间：`2026-08-18T13:47:45Z` → `2026-08-18T13:48:03Z`

事务尾部顺序：

```text
Runtime: end received
Verifier: testing
Browser Verification: passed
Browser Verification 移动端: passed
Reviewer: review passed
```

Pipeline：Architect / Builder / Verifier / Reviewer 全部 passed，且没有重复 Core 或遗留 fixture server。

真实测试项目的 `node tests/test.js` 独立复跑：`fixture tests passed`。

### 浏览器证据

- Desktop：PASS，1440×900，Console 0，Network 0，Layout 0。
  - `~/Library/Application Support/Nexus/browser-verification/8c254143-d40a-4321-840c-9ab61e2b5b90/6c93bee7-6b6a-4701-9f0b-3dc0c85441fb/result.json`
- Mobile：PASS，390×844，Console 0，Network 0，Layout 0。
  - `~/Library/Application Support/Nexus/browser-verification/8c254143-d40a-4321-840c-9ab61e2b5b90/0ef952cf-2582-4173-94bd-f75134d5636c/result.json`

## 6. 最终构建与清理

live acceptance 使用的环境自动提交/批准钩子已从源码移除。最终无钩子构建已完成，`codesign --verify --deep --strict`：PASS；安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`；Bundle ID：`cn.nexus.desktop`；显示名：`AI Dev One`；版本：`0.4.0-beta.1`。二进制字符串扫描确认不含 `NEXUS_PHASE26_AUTOMATION`。

最终安装包冷启动/退出：PASS；退出后 Core、fixture server 和子进程均为 0。用户提供的 API Key 未写入仓库、事务、浏览器 metadata 或运行时日志；LaunchServices 环境变量已清除。

## 7. 当前 Gate 判断

- P0：0（未发现数据丢失、Core 重复启动或密钥泄露）
- P1：0（终态竞态、Reviewer gate、Core crash 分类已修复并通过合约测试）
- P2：0（浏览器桌面/移动验收和事务持久化性能已复跑）
- P3：0

本阶段已移除验收钩子并完成最终无钩子构建、安装、冷启动和退出验证。

本地修复提交：`3d0085b5f8098f5d9aaa006e0b729fb6bd0fc4fd`。

不创建 tag、不 push；建议在该基线之上进入 Phase 3 评审。

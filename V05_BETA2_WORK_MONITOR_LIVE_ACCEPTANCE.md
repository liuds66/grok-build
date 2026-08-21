# AI Dev One Route 2 v0.5.0-beta.2-dev

## Work Monitor Live Model Acceptance

**执行日期**：2026-08-21（Asia/Shanghai）
**安装包**：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
**源码 HEAD**：`29abda8ccddc00232c118e9c73b8e631c8b2d7f1`
**分支**：`v0.5-dev`
**版本 / Build**：`0.5.0-beta.2-dev` / `2`
**Bundle ID**：`cn.nexus.desktop`
**冻结 tag**：`v0.5.0-beta.1` → `ea576b370636bc81758bfaf591b29355d817d0bf`（未移动）

本报告只记录真实安装包现场结果。没有移动 tag、没有创建新 tag、没有 Push、没有 GitHub Release，也没有提交功能代码。

## 结果摘要

**WORK_MONITOR_LIVE_ACCEPTANCE：FAIL（未达到全部 Gate）**

Task A 的自动打开、真实时间线、状态一致性和最终完成已通过；但 Keychain 冷启动读取在本机持续阻塞，且没有完成一个干净的 Task B（手工关闭/重新打开/第二任务隔离等项目无法据此宣称 PASS）。

## Task A

| 项目 | 真实结果 | 证据 |
|---|---|---|
| Task ID | `AF52D3E8-8F0C-45D2-A5D6-BE845C17EFFA` | 安装包写入的 Session store |
| 类型 | 只读项目结构 / 测试命令检查 | 未修改工作树 |
| T0 | 19:13:24（用户消息进入执行） | Session timestamp |
| T1 | 19:13:25（首条时间线可见） | Work Monitor AX 读取 |
| Auto-open latency | ≤ 1000 ms（显示时间精度为 1 秒，未加入单调时钟埋点） | `19:13:24 → 19:13:25` |
| automaticShow count | 1 | 全流程只有一个 Work Monitor window |
| Focus | PASS | Work Monitor 可见；AX focused window 仍为主窗口，没有把输入焦点强行切走 |
| Timeline | PASS | 真实出现任务开始、Checkpoint、Project Intelligence、Core 恢复、Architect、Builder、Verifier、Reviewer、完成 |
| 可见语义事件 | 约 32 条 | AX 时间线快照；包含 4 个验证检查项 |
| Event coalescing | **NOT OBSERVED** | 本轮没有安全的 raw-tool instrumentation，不能声称 raw activity 与语义事件的压缩比例；只确认时间线未暴露原始参数 |
| Current Work 一致性 | PASS | Architect/Builder/Verifier/Reviewer 与 Timeline 同步推进 |
| 内容清晰度 | PASS | 3–5 秒内可回答当前阶段、对象、目的、验证状态 |
| Task completion | PASS | Work Monitor 显示“已完成”；Reviewer 已通过；无文件修改 |
| Secret review | PASS | 时间线未出现 API Key、Bearer、Cookie、隐藏推理或完整绝对路径；`tests/secret-redaction.cjs` 也通过 |

Task A 的验证门显示 Rust 检查为 `SKIPPED · 未找到 cargo`（0 项 PASS），但按当前 Verification Gate 语义，SKIPPED 不等于失败；本次任务仍完成并由 Reviewer 通过。这是环境/验证可用性提示，不应被误报成全部测试通过。

## Task B 与人工交互项目

| 项目 | 结果 | 说明 |
|---|---|---|
| Task B ID | `4A0E8379-EEFA-43B4-81DF-B95643D9AEE7`（尝试） | 一次输入事件串入了测试剪贴板内容，随后已终止；不作为有效 Task B |
| Task B auto-open / latency / count | **NOT VALIDATED** | 没有干净的第二任务，不能伪造 PASS |
| Manual close during Builder/Verifier | **NOT OBSERVED** | Task A 未在该阶段执行关闭 |
| Same-task reopen suppression | **NOT OBSERVED** | 未完成有效 Task B |
| Manual reopen / continuity | **NOT OBSERVED** | 不能仅用既有契约测试代替现场验收 |
| Singleton | PARTIAL | 现场菜单打开/关闭曾确认单窗口；未在有效 Task B 中重复验证 |
| Pin | NOT OBSERVED | 本轮未在真实任务中切换置顶 |
| Main-window close/reopen | NOT OBSERVED | 本轮未在有效任务执行中关闭主窗口 |
| Waiting state | NOT OBSERVED | Task A 未自然停留在等待状态 |
| Natural model error | NOT OBSERVED | 未人为制造模型失败 |

## Keychain / Model 状态阻塞

冷启动使用真实安装包、未注入环境变量时，启动探针在约 5 秒后仍记录：

```text
credential.state=loading_credentials
model.hasAPIKey=false
```

设置页显示“尚未保存密钥”，主窗口显示“模型配置异常”。同时，系统钥匙串项目存在（仅记录退出码，不输出密钥），DeepSeek `/v1/models` 返回 HTTP 200 且列出 3 个模型。独立的 Security.framework 查询在本机同样持续阻塞；这与 `SecureCredentialStore` 的 `loadInFlight` 路径一致。为完成 Task A 的模型链路，仅在本次进程中临时注入 `OPENAI_API_KEY` 环境变量，未写入配置、日志或报告；这**不构成 Keychain 冷启动通过**。

因此本轮 Keychain/Model Ready 现场 Gate 为 **FAIL / BLOCKED**，需要单独修复或在同一环境完成真实钥匙串恢复后再重测。

## 性能观察

Task A 读取外置盘大项目期间，安装包进程峰值约 **84% CPU / 380 MB RSS**；采样栈显示主要时间在 `ProjectContextProvider.findRelevantFiles` 和 AppKit/CoreGraphics 绘制。任务最终完成，但本轮未进行长时间 soak，不能把该数值判为稳定性能 PASS；建议作为 P2 观察项继续跟踪。

## 回归与构建

### 本轮实际通过

使用项目已安装 Node（v22.23.1）直接运行：

- `tests/work-monitor-unit.cjs` — PASS
- `tests/work-monitor-timeline-unit.cjs` — PASS
- `tests/secret-redaction.cjs` — PASS（199 个 runtime JSONL，无 credential-shaped 值）
- `tests/keychain-cold-start.cjs` — PASS（静态契约）
- `tests/resizable-layout-unit.cjs` — PASS

安装包元数据和签名检查：

- `0.5.0-beta.2-dev` / Build `2` / Display brand `AI Dev One` — PASS
- `codesign --verify --deep --strict` — PASS
- 安装包启动、退出 — PASS（任务结束后无 Nexus/Core/agent 子进程残留）

### 本轮未完成或未重新执行

- `scripts/test-nexus`：曾启动，但因重复并发编译与外置盘 Swift 编译长时间阻塞而终止；不能把它报告为本轮 PASS。冻结基线已有记录为 `101 passed / 0 failed`。
- Swift 全量 typecheck：同样在外置盘源文件编译阶段超过本轮现场窗口，已停止；没有代码变更，不能用此次未完成命令覆盖历史 PASS。
- 本轮没有重新 build/install/sign；现场使用的是已安装的 `Nexus.app`，其签名和元数据已单独核验。

## 隐私与误触发处理

测试过程中发现 Quartz/剪贴板自动化会把旧剪贴板内容串入自定义 Composer。一次误触发任务立即被终止；随后检查确认没有 `nexus-agent`、`ai-dev-one-core` 或其他子进程残留，Git 工作树仍干净。该尝试不计入 Task B，不把它包装成成功验收。

## 最终判定

本轮不能标记 `WORK_MONITOR_LIVE_ACCEPTANCE = PASS`。阻塞原因不是 Work Monitor Task A 的自动打开/时间线实现，而是：

1. 本机真实 Keychain Security.framework 冷读持续阻塞，导致无环境注入时模型状态不稳定。
2. 没有完成一个干净的第二真实任务，因此手动关闭抑制、连续性、Task B 隔离、Pin 和主窗口关闭/重开不能宣称通过。
3. 外置盘编译在本轮现场耗时过长，`scripts/test-nexus`/全量 Swift typecheck 未形成新的 PASS 证据。

**Resulting commit：NONE**
**Working tree：报告文件新增，其余源码无改动**
**Tag：未创建 / 未移动**

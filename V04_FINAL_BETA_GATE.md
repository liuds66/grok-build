# AI Dev One Route 2 v0.4.0-beta.1 最终 Beta Gate 记录

日期：2026-08-18
安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
Bundle Identifier：`cn.nexus.desktop`
用户可见名称：`AI Dev One`（文件名 `Nexus.app` 为历史兼容名称）
旧 RC 验证基线：`97893182ec30684c5d4b1c5ed55daa1d4be4d88f`
最终 Beta 基线：以本地 annotated tag `v0.4.0-beta.1` 指向的提交为准
版本：`0.4.0-beta.1`
本轮仅完成发布审计、版本元数据核对、精确暂存与最终封版；不改变已经验收通过的产品行为。

## 历史记录：Resizable Manual Acceptance（2026-08-17 修复前）

| 场景 | 真实结果 | 结论 |
|---|---|---|
| Sidebar 最小/最大（220–420px） | 源码约束与非法值自愈保持有效；本轮实际拖拽不能改变持久化宽度 | BLOCKED |
| Workspace 最小/最大（280–620px） | 源码约束与非法值自愈保持有效；本轮实际拖拽不能改变持久化宽度 | BLOCKED |
| 快速拖动 30 次 | 已授予 Accessibility；在真实 divider 坐标发送超过 30 组鼠标按下/拖动/释放事件，`NSSplitView` 未改变宽度。没有把事件注入结果冒充人工鼠标 PASS | BLOCKED |
| 双击恢复 | 左侧 `300 → 260` 已实测；右侧 `620 → 340` 有现场记录 | PASS |
| 最大化/恢复 | 当前安装包没有可操作的 AX 缩放动作；坐标尝试未形成可判定的最大化/恢复结果 | BLOCKED |
| Cmd+Q / reopen | 本轮冷启动循环每次退出后进程清零，再由 LaunchServices 重开 | PASS |
| 布局持久化 | UserDefaults 当前已恢复为 `sidebar=260`、`workspace=340`；代码合同测试通过。由于拖动未改变宽度，改变后宽度的现场持久化未判定 | BLOCKED |
| BrowserWindow 最小尺寸 | AX 尝试设置 `500×300` 后仍为 `1440×900`，未低于 `1180×720` | PASS |

**Resizable 最终结论：BLOCKED（计入 1 个 P1，不能作为 Beta Gate 通过）。**

说明：Accessibility 已开启，双击 divider 和窗口下限均可验证；但当前可用的系统鼠标事件注入无法让已安装包的 `NSSplitView` 接受拖动，仍需要用户在真实物理鼠标下完成一次最终验收，或后续单独修复/验证该交互。因本轮明确不改 Resizable 代码，不能宣称通过。

证据：`MANUAL_UI_ACCEPTANCE.md` 的辅助功能现场记录、`/tmp/axfinal-window.txt`、`/tmp/axfinal-window-small.txt`、UserDefaults `cn.nexus.desktop`。

## 2. Keychain 5x Cold Start Stability

测试方式：每轮先完整退出并确认 `Nexus` 进程清零，再使用 LaunchServices `open /Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 冷启动。凭据最终状态通过设置页的非敏感提示“已安全保存；留空不会修改”确认；未读取、打印或记录 API Key。模型状态通过主窗口底部状态胶囊确认。

| 轮次 | 凭据加载观测耗时* | credentials final state | ModelState | 钥匙串提示次数 | 完整退出/重开 |
|---:|---:|---|---|---:|---|
| 1 | 2,776 ms | `credentials_ready` | `模型就绪` | 0 | PASS |
| 2 | 4,450 ms | `credentials_ready` | `模型就绪` | 0 | PASS |
| 3 | 2,488 ms | `credentials_ready` | `模型就绪` | 0 | PASS |
| 4 | 2,857 ms | `credentials_ready` | `模型就绪` | 0 | PASS |
| 5 | 3,032 ms | `credentials_ready` | `模型就绪` | 0 | PASS |

\*耗时从 LaunchServices `open` 到首次观察到设置页凭据状态；它是端到端可观察耗时，不是把密钥写入日志的内部计时。

5 轮均未要求重新保存 API Key；未出现钥匙串提示、超时后错误停留或需要用户干预的恢复。**Keychain 最终结论：PASS。**

## 历史 Gate 决策（修复前）

- P0 remaining：0
- P1 remaining：1（Resizable 真实拖动/最大化现场验收）
- P2 remaining：0
- P3 remaining：0
- `V04_BETA_GATE_REPORT.md`：本轮不改为 Beta 通过状态
- `v0.4.0-beta.1`：不创建
- 功能代码冻结：不宣称，等待唯一剩余 P1

结论：**当前仍是 Release Candidate，不满足 AI Dev One Route 2 v0.4 Beta 的正式收口条件。** Keychain 5x 已通过；需要在真实物理鼠标下完成 Resizable 拖动/最大化验收并确认 P1=0 后，才允许更新 Beta 报告、创建 tag 和输出新的 Beta baseline commit。

## 最终封版 Gate（2026-08-18）

以下结果来自 RC3 安装包的最终现场验收；上方的 BLOCKED/Release Candidate 内容是修复前历史记录，保留用于审计，不代表最终基线。

| Gate | 最终结果 | 证据 |
|---|---|---|
| Resizable Sidebar | 220–420px，边界与 clamp PASS | `RC3_RESIZABLE_REPORT.md` |
| Resizable Workspace | 280–620px，边界与 clamp PASS | `RC3_RESIZABLE_REPORT.md` |
| 快速拖动 | 30 轮 / 120 次真实拖动 PASS | `RC3_RESIZABLE_REPORT.md` |
| 最大化/恢复 | 1440×900 → 2560×1330 → 1440×900 PASS | `RC3_RESIZABLE_REPORT.md` |
| 布局持久化 | 360/500 重启后保持 PASS | `RC3_RESIZABLE_REPORT.md` |
| 非法状态自愈 | 0/99999 → 260/340 PASS | `RC3_RESIZABLE_REPORT.md` |
| BrowserWindow 保护 | 始终不低于 1180×720 PASS | `RC3_RESIZABLE_REPORT.md` |
| Core Recovery / Restart | 自动恢复、Crash Loop 上限、手动 Restart PASS | `RC2_CORE_RECOVERY_REPORT.md`、`MANUAL_UI_ACCEPTANCE.md` |
| Keychain 冷启动 | 5/5，credentials_ready，0 次重复提示 PASS | 本报告上方 Keychain 表 |
| Rust / Policy / Rollback / Secret scan | 最终 Gate 均 PASS | `V04_BETA_GATE_REPORT.md` |

最终计数：P0 = 0，P1 = 0，P2 = 0，P3 = 0。

发布状态：`AI Dev One Route 2 v0.4.0-beta.1` 正式封版；本地 annotated tag 指向本次最终 Beta baseline commit，未推送远端。

# AI Dev One Route 2 v0.4 Beta — 人工验收记录

日期：2026-08-17
应用：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
工程：`/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座`
窗口契约：默认 `1440×900`，最小 `1180×720`

## 现场前置条件

（历史记录）本机最初未授予 Codex/自动化进程 macOS Accessibility 权限，因此早期现场项曾被标为 BLOCKED。后续已在系统设置中授予权限；真实复核结果见文末“辅助功能已授权后的现场验收”。

## Resizable 三栏

| 场景 | 操作 | 预期 | 证据/结果 |
|---|---|---|---|
| 左栏最小 | Sidebar 拖到 `220px` | Chat ≥ `520px`，Composer 保留 | MANUAL BLOCKED（Accessibility） |
| 左栏最大 | Sidebar 拖到 `420px` | Chat 不溢出 | MANUAL BLOCKED（Accessibility） |
| 右栏最小 | Workspace 拖到 `280px` | Chat 不被压坏 | MANUAL BLOCKED（Accessibility） |
| 右栏最大 | Workspace 拖到 `620px` | BrowserWindow 不缩小 | MANUAL BLOCKED（Accessibility） |
| 快速拖动 | 左右各连续拖动 30 次 | 不丢拖拽、不横向滚动 | MANUAL BLOCKED（Accessibility） |
| 双击恢复 | 双击两个 Divider | Sidebar=260，Workspace=340 | MANUAL BLOCKED（Accessibility） |
| 重启恢复 | 退出、重新打开 | 上次宽度恢复 | 代码合同 PASS；鼠标现场 BLOCKED |
| 非法 local state | 写入 `0/-1/99999/NaN` 后重启 | 自动恢复 260/340 | `resizable-layout-unit.cjs` PASS |
| 窗口边界 | 最大化、还原、缩小 | 永远 ≥1180×720 | layout probe PASS |

## Core Restart

| 场景 | 操作 | 预期 | 证据/结果 |
|---|---|---|---|
| 任务中 kill Core | 记录 before PID 后发送 SIGKILL | 任务 `interrupted`，不显示 Completed | 真实进程层 PASS（见 `FULL_E2E_REPORT.md`） |
| 自动恢复 | 观察 1s/2s/5s 重启 | `disconnected → restarting → ready` | `core-crash-recovery.cjs` PASS；UI 现场 BLOCKED |
| 手动恢复按钮 | 失败后点击“重新启动 Core” | 只启动一个 Core、Agent 回 idle | MANUAL BLOCKED（Accessibility） |
| 残留检查 | 退出应用并检查进程 | 无 zombie / shell 子进程 | 真实退出检查 PASS |

## 现场结论

当前自动化/进程证据：PASS。当前人工 UI 结果：`BLOCKED — Accessibility 未授予`，不是产品 FAIL。完成上述现场操作后，将本文件中的对应行更新为 `PASS/FAIL`，再决定是否把 Beta Gate 的 P1 现场阻塞清零。

## Final Gate 安装包复核（2026-08-17）

本轮最终安装包 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 已通过 `codesign --verify --deep --strict`。LaunchServices 冷启动 probe 实测窗口 `1780×1224`，Sidebar/Chat/Workspace 为 `260/1150/340`，内部 UI snapshot 成功生成；退出后未发现 Nexus、Runtime `nexus-agent` 或 Core 残留。以上只证明启动、窗口边界和进程清理，不替代下表中的鼠标/按钮人工操作，因此 Resizable 与 Core Restart 仍保持 `MANUAL BLOCKED`。

## 辅助功能已授权后的现场验收（2026-08-17）

本机 `AX_TRUSTED=true`，使用已安装的 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`，未修改产品代码。

### Resizable / Window

| 项目 | 实际操作 | 结果 |
|---|---|---|
| 重置界面布局 | 通过 AI Dev One 菜单执行“重置界面布局” | PASS；窗口回到 `1440×900`，UserDefaults 为 `sidebar=260`、`workspace=340` |
| 非法/过小窗口保护 | Accessibility 尝试把窗口设为 `500×300` | PASS；窗口保持 `1440×900`，未低于 `1180×720` 合同 |
| 左 Divider 双击 | 先写入 `sidebar=300`，在真实 divider 位置双击 | PASS；恢复为 `260` |
| 右 Divider 双击 | 先写入 `workspace=620`，在真实 divider 位置双击 | PASS；恢复为 `340` |
| 左右 Divider 拖动 | AX 已授权后用 CGEvent/cliclick 在真实 divider 坐标执行多次拖动 | BLOCKED；事件未被 AppKit NSSplitView 识别，存储值没有变化；未把代码探针或注入失败冒充人工 PASS |
| 最大化/恢复 | 当前安装包窗口未暴露可操作的 AX 全屏/缩放按钮，鼠标坐标点击也未改变尺寸 | BLOCKED；需用户在当前桌面用绿色按钮完成一次真实验收 |

### Core Restart

| 项目 | 实际证据 | 结果 |
|---|---|---|
| 第一次真实 kill | 只读任务启动后记录 Core PID `96745`，`kill -9`；+0.5s 至 +8s UI 为“Agent 失败”，无替代 Core PID | FAIL |
| 第二次真实 kill | 只读任务记录 Core PID `97213`，立即 `kill -9`；UI 回到“Agent 空闲”，等待 8s 仍无新 Core PID | FAIL |
| 自动恢复状态 | 未观察到 `disconnected → restarting → ready`；没有自动重启进程 | FAIL |
| Restart 按钮 | AX 树与可见按钮中没有“重新启动 Core”按钮，无法完成按钮点击验收 | FAIL |
| 残留进程 | 两次 kill 后 `ps` 均无 `nexus-agent`/Core 子进程残留 | PASS（仅清理） |

现场结论：Resizable 拖动与最大化仍需真实鼠标/桌面验收；Core Restart 在已安装包上已被真实 kill 场景复现为失败。因此本轮不能把 P1 清零、不能创建 `v0.4.0-beta.1` 标签。

## RC2 Core Supervisor 复核（2026-08-17）

以上 Core FAIL 记录属于修复前构建。RC2 已重新构建、安装并在同一安装包上复测：

| 项目 | RC2 结果 | 证据 |
|---|---|---|
| 真实 kill | `nexus-agent` PID `27128` 被 `kill -9`；任务没有 Completed/end，恢复后 Agent 空闲 | `ps`、Core supervisor log |
| 自动恢复 | `disconnected → restarting → ready`；第一次延迟约 1 秒，健康检查通过 | `~/Library/Logs/AI Dev One/core-supervisor.log` |
| Crash loop | 失败 wrapper 真实验证 1/2/5 秒后进入 `Core 失败`，没有第 4 次启动 | 同一日志 |
| Restart 入口 | 失败态 AX 树实际出现“重新启动 Core”“查看日志”，两者 enabled | AX inspection |
| 手动 Restart | AXPress 点击“重新启动 Core”；日志记录 `manual restart requested`、健康 PID `27368`、`ready` | AXPress + supervisor log |
| 重启后任务 | 新任务“只回复 OK，不修改文件”真实完成，Agent 显示完成 | AX snapshot |
| 重复 Core/zombie | 恢复与退出检查中同时 Core 数 ≤1；`ps` 无 `nexus-agent` 残留 | process snapshot |

因此 Core 生命周期 P1 已关闭。Resizable 本轮没有改代码；真实拖动 30 次、最大化/恢复仍需在当前桌面由用户完成，当前唯一剩余 P1 为 Resizable 人工验收。

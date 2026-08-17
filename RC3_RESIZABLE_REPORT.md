# AI Dev One Route 2 v0.4 RC3 — Resizable Pane 报告

日期：2026-08-18
基线 commit：`97893182ec30684c5d4b1c5ed55daa1d4be4d88f`
分支：`codex/nexus-agent`
真实安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
Bundle Identifier：`cn.nexus.desktop`

## 结论

RC3 的 Resizable P1 已修复并通过真实安装包验收：

- Sidebar：最小 220px、最大 420px：PASS
- Workspace：最小 280px、最大 620px：PASS
- 两个 Divider 快速往返 30 轮（120 次真实拖动）：PASS
- 双击恢复默认值：PASS
- 最大化/恢复：PASS
- 退出重启后的宽度持久化：PASS
- 非法持久化值自愈：PASS
- BrowserWindow 最小尺寸保护：PASS（任何实测结果均未低于 1180×720）

当前 RC3 状态：P0 = 0，P1 = 0，P2 = 0，P3 = 0。

## 根因

桌面端实际使用的是 AppKit `NSSplitView`，不是旧版 React/Electron Pointer Events。`ResizableSplitView` 设置了 `arrangesAllSubviews = false`，并通过 `setPaneFrames` 手动布局三栏；旧实现仍调用 `super.mouseDown(with:)`，依赖 NSSplitView 的内部 tracking loop。该 loop 能收到按下/双击，但在手动 frame 布局下没有稳定交付可用的拖动/resize 回调，因此真实鼠标拖动后宽度不变。

同时，旧的 divider 命中区域只有约 5px，pane 子视图可能先于 divider 拿到 hit-test；这会让问题更难以复现和操作。

## 修复

### `apps/nexus-desktop/Sources/NexusDesktop/main.swift`

1. `ResizableSplitView` 增加固定拖动起点：`dragStartX`、`dragStartSidebarWidth`、`dragStartWorkspaceWidth`。
2. Divider 命中区域扩大到 10px，覆盖 `hitTest`、effective rect、tracking area 与 cursor rect；视觉线仍为 1px。
3. `mouseDown` 不再交给原生 tracking loop；`mouseDragged` 按“拖动开始时的宽度 + 当前位移”计算候选值。
4. 左侧公式为 `startSidebar + translation`，右侧公式为 `startWorkspace - translation`；每帧 clamp，并保证 Chat 最小宽度 520px。
5. `mouseUp` 只在拖动结束时写入 UserDefaults，避免每个鼠标采样同步磁盘；双击 reset 行为保留。
6. AppKit 窗口缩放恢复增加 `sender.isZoomed` 分支：允许合法的恢复 frame 通过最小尺寸保护，不再把最大化尺寸返回给恢复操作。
7. 诊断日志仅由 `ai-dev-one.resizable-diagnostics` 控制，验收结束后已关闭；默认不输出。

### `tests/resizable-layout-unit.cjs`

增加 Resizable 合约断言：拖动事件覆盖、10px hit area、固定 drag origin、Chat 最小宽度约束、左右边界 clamp、非法数值拒绝，以及 zoom restore 分支。

## 事件、状态与持久化路径

```text
AppKit hitTest(10px divider)
  → ResizableSplitView.mouseDown
  → 保存 startX/startPaneWidth
  → mouseDragged: translation + clamp + setPaneFrames
  → mouseUp: 最终采样 + persistCurrentWidths
  → UserDefaults
```

持久化键保持不变：

- `ai-dev-one.sidebar-width`（默认 260，范围 220–420）
- `ai-dev-one.workspace-width`（默认 340，范围 280–620）

启动时仍会规范化异常、非有限或越界值；窗口 resize 不会改写用户保存的 pane 宽度。

## 真实安装包验收记录

所有动作均在 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` 上执行，非 Preview、非开发窗口；拖动使用已获 Accessibility 的 macOS CGEvent/HID 指针事件，完整经过 AppKit hit-test、`mouseDown`、`mouseDragged`、`mouseUp` 路径，不是只调用 clamp 函数的模拟测试。

| 场景 | 实际结果 | 结果 |
|---|---|---|
| 左拖 260 → 360 | `sidebar=360` | PASS |
| 右拖 340 → 500 | `workspace=500` | PASS |
| Sidebar 下限 | 220 | PASS |
| Sidebar 上限 | 420 | PASS |
| Workspace 下限 | 280 | PASS |
| Workspace 上限 | 620 | PASS |
| 双击两个 Divider | 回到 260 / 340 | PASS |
| 快速往返 30 轮 | 120 次真实拖动，最终 260 / 340 | PASS |
| 重启持久化 | 360 / 500 → 退出 → 重开仍为 360 / 500 | PASS |
| 最大化/恢复 | 1440×900 → 2560×1330 → 1440×900；pane 宽度保持 | PASS |
| 非法值自愈 | `0` / `99999` → 重开后 260 / 340 | PASS |
| 窗口下限 | 请求 500×300 后实际仍为 2560×1330，未低于 1180×720 | PASS |

安装脚本同时完成签名校验：`codesign --verify --deep --strict` PASS。安装前旧包备份为：`/Volumes/AI-DEV/Nexus项目/应用/Nexus-旧版-20260818-023744.app`。

## 自动回归结果

使用工作区已安装 Node 运行：

```text
tests/resizable-layout-unit.cjs       PASS
tests/ui-state-unit.cjs               PASS
tests/desktop-runtime-contract.cjs    PASS
git diff --check                       PASS
scripts/build-nexus-desktop            PASS
scripts/install-nexus-desktop          PASS
```

本轮没有修改 Rust Core、ACP、Core Supervisor、Keychain、Policy、Rollback、Agent Pipeline 或 Verification Gate。

## Beta Gate 说明

Resizable 现场 P1 已关闭，当前验收数字为 P0=0、P1=0、P2=0、P3=0。Beta 发布标签/基线提交应在包含本轮源代码、回归测试和 RC3 报告的发布提交上执行；当前工作树仍含有本轮之前的用户未提交改动，因此不能把仅指向旧 HEAD 的标签误当作本次安装包基线。

# AI Dev One · Global Intelligence Center V1.2R1

## ARRANGED-SUBVIEW FULL-WIDTH REMEDIATION

日期：2026-08-27
工程：`/Users/mac/Documents/grok Build底座`
安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`

## 根因

上一版已经把 `mainGrid` 固定为 58/42 两列，但 `dashboardCard` 创建的右列卡片没有统一关闭 `translatesAutoresizingMaskIntoConstraints`，也没有把 arranged subview 的宽度硬绑定到右列。AppKit 因此可能按 intrinsic/autoresizing 宽度求解，表现为右侧 Sources、Risk、AI Insight 变成窄的浮动卡片。左列虽然已有 Auto Layout，但也缺少防止未来 intrinsic-size 回归的显式宽度契约。

本轮没有修改 58/42 数学、颜色、字体、背景、数据或网络路径。

## 修复内容

文件：`apps/nexus-desktop/Sources/NexusDesktop/IntelligenceDashboard.swift`

1. `dashboardCard(...)` 创建时统一设置：
   - `translatesAutoresizingMaskIntoConstraints = false`
   - 水平方向低 hugging、required compression resistance。
2. 右列四个 arranged card 显式添加：
   - `card.widthAnchor == insightBoards.widthAnchor`
3. 左列 Globe / Realtime 两个 arranged card 显式添加：
   - `globeCard.widthAnchor == leftColumn.widthAnchor`
   - `feedCard.widthAnchor == leftColumn.widthAnchor`
4. 增加仅在 `AI_DEV_ONE_INTELLIGENCE_DEBUG_FRAMES=1` 时生效的运行时 frame dump；正常产品启动不会写入任何诊断文件。该 dump 在 LaunchServices 启动的签名 App 中可通过 `AI_DEV_ONE_INTELLIGENCE_DEBUG_PATH` 收集。

回归测试：`tests/intelligence-dashboard-unit.cjs`

- 锁定右列 card 的 Auto Layout / full-width contract。
- 锁定左列 card 的 full-width contract。
- 锁定 frame dump 仅为显式验收开关。

## 运行时 Frame 证据

证据文件：`/tmp/ai-dev-one-v12r1-frames.log`
坐标为 `IntelligenceDashboardView` 根视图坐标；窗口标题栏造成的 y 偏移不影响宽度 gate。

### 1260×760

```text
mainGrid       w=1240.0
leftColumn     x=10.0  w=712.0
globeCard      x=10.0  w=712.0
realtimeCard   x=10.0  w=712.0
rightColumn    x=734.0 w=516.0
eventSummary   x=734.0 w=516.0
sourcesCard    x=734.0 w=516.0
riskCard       x=734.0 w=516.0
aiInsightCard  x=734.0 w=516.0
```

### 1100×680

```text
mainGrid       w=1080.0
leftColumn     x=10.0  w=619.0
globeCard      x=10.0  w=619.0
realtimeCard   x=10.0  w=619.0
rightColumn    x=641.0 w=449.0
eventSummary   x=641.0 w=449.0
sourcesCard    x=641.0 w=449.0
riskCard       x=641.0 w=449.0
aiInsightCard  x=641.0 w=449.0
```

### 1440×900

```text
mainGrid       w=1420.0
leftColumn     x=10.0  w=817.0
globeCard      x=10.0  w=817.0
realtimeCard   x=10.0  w=817.0
rightColumn    x=839.0 w=591.0
eventSummary   x=839.0 w=591.0
sourcesCard    x=839.0 w=591.0
riskCard       x=839.0 w=591.0
aiInsightCard  x=839.0 w=591.0
```

结论：

- Globe fills left column：PASS
- Realtime fills left column：PASS
- Event Summary fills right column：PASS
- Sources fills right column：PASS
- Risk fills right column：PASS
- AI Insight fills right column：PASS
- Main grid starts at leading edge（x=10）：PASS
- 三个窗口尺寸的宽度相等性：PASS

## 验证结果

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| `node tests/intelligence-dashboard-unit.cjs` | PASS | `global intelligence center contract: ok` |
| Swift AppKit typecheck | PASS | `swiftc -typecheck -framework AppKit apps/nexus-desktop/Sources/NexusDesktop/*.swift` |
| `scripts/test-nexus` | PASS | `/tmp/ai-dev-one-v12r1-regression.log`；通过 131，失败 0 |
| Desktop build | PASS | `./scripts/build-nexus-desktop` |
| Install | PASS | `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` |
| Code signature | PASS | `codesign --verify --deep --strict` |
| Secret scan | PASS | `tests/secret-redaction.cjs`；扫描 208 个 runtime JSONL，无 credential-shaped values |
| Network calls | 0 | V1 fixture refresh path 未调用 `IntelligenceServiceController` / `URLSession` |
| Launch / quit cleanup | PASS | 安装包启动后 `Cmd+Q` 语义退出；无 Nexus/Core 子进程残留 |

安装包元数据：

- Display brand：`AI Dev One`
- Bundle identifier：`cn.nexus.desktop`
- Marketing version：`0.5.0-beta.2-dev`
- Build：`2`
- 文件名：`Nexus.app`（兼容现有 Bundle/Keychain/config，不在本轮改名）

## 变更边界

本轮只修改情报中心 Renderer/AppKit 布局约束与验收诊断，以及对应回归断言。没有修改 Rust Core、ACP、Agent Runtime、Policy、Session、数据源或视觉主题；没有创建 commit、tag、release 或 push。

当前工作树仍包含此前 dogfood/v0.5 改动，提交前应按仓库既有审计流程精确 stage，不要使用 `git add -A`。

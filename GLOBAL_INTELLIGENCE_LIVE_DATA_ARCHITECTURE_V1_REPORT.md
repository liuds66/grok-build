# AI Dev One 全球情报中心 Live Data Architecture V1

日期：2026-08-27

分支：`v0.5-dev`

视觉基线：`GLOBAL_INTELLIGENCE_CENTER_V1_2R1_LAYOUT = PASS`

架构开始前 HEAD：`822591d4ca3008e4fdbe6848338ea532b9066ae9`

安装包：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`

用户可见品牌：AI Dev One（文件名仍为兼容性的 `Nexus.app`）

## 范围与冻结边界

本阶段实现的是可验证的实时数据架构，不是 Live API 接入。默认运行模式为 `.fixture`：不访问外部网络、不读取 API 凭据、不启动 OSIRIS、不启动 Runner，也不改变已冻结的 V1.2R1 三栏/全球情报中心视觉布局。

实现只位于数据契约和 Fixture 适配层；Rust Core、ACP、Agent Pipeline、Policy、Rollback、Session backend 以及 V1.2R1 的面板几何没有重构。

## 实现内容

### Provider contract 与数据模型

`apps/nexus-desktop/Sources/NexusDesktop/IntelligenceDataArchitecture.swift` 提供：

- `IntelligenceDataProvider` 统一契约：provider、类别、来源类型、刷新策略、可用性、数据模式和异步 snapshot。
- `IntelligenceDataMode`：`fixture`、`live`、`mixed`，并提供中文显示名。
- `NormalizedIntelligenceEvent`：稳定 ID、类别、标题、摘要、严重度、位置、来源事件 ID、时间戳、置信度、metadata 和完整 provenance。
- `IntelligenceSourceProvenance`：来源名称/URL 或 canonical ID、获取/源/标准化时间、质量分类、`isLive`/`isFixture`。
- `FlightProvider`、`SatelliteProvider`、`EarthquakeProvider`、`DisasterProvider`、`NewsProvider`：仅为禁用的 descriptor，调用时 fail-closed，不执行网络。

### 聚合、失败隔离和新鲜度

- `IntelligenceSnapshotAggregator` 对多个 provider 合并、按 provider+event ID 去重、按来源时间排序，并计算事件总数、来源/类别统计和风险计数。
- 每个 provider 都有独立 `idle/loading/ready/stale/failed/rateLimited/disabled` 状态、错误分类、刷新时间、下次刷新时间和 stale 截止时间。
- `IntelligenceProviderStatusRecord.status(at:)` 在超过 `staleAfter` 后派生 `.stale`，不篡改历史记录。
- `IntelligenceRefreshCoordinator` 是唯一调度者：actor 串行（并发上限 1）、刷新合并、取消、最小刷新间隔、隐藏窗口暂停和 provider 失败隔离。
- disabled/unavailable provider 在进入 `fetchSnapshot` 前被拦截；速率限制、malformed、timeout、cancelled 和 unknown 均保留在 telemetry 中。

### 缓存与网络/凭据边界

- `IntelligenceCacheEntry` + `IntelligenceCacheStore` 只定义轻量 snapshot cache/TTL；当前测试实现为进程内 store，不产生持久化网络缓存。
- 序列化前后执行 `IntelligenceCacheSecurity`，拒绝 authorization、bearer、cookie、password、API key 等凭据标记。
- `IntelligenceNetworkAccessPolicy` 默认 `allowedHosts = []`、HTTPS-only、超时、最大响应体、JSON content type 和 redirect policy；没有显式 host 时始终拒绝。
- `IntelligenceCredentialProvider` 只有受控接口，V1 不读取任何凭据；未来 credential provider 必须接现有 Keychain approved store。

### 不可信文本与 AI 边界

`IntelligenceAnalysisContextSanitizer` 会清理控制字符、常见 prompt delimiter、事件/来源/metadata 字段，并只把清理后的 normalized events 交给分析上下文。外部标题和摘要不会被当作 system prompt、工具命令或 Agent 指令。

### 现有 Fixture 兼容

`IntelligenceDataArchitectureFixture.swift` 将既有 `FixtureIntelligenceDataProvider` 适配为正式 provider，并在 `IntelligenceFixtureSnapshotBridge` 中经过 normalize/aggregate 路径后返回原有 `GlobalIntelligenceSnapshot`。因此 V1.2R1 的计数、洞察、交互和布局保持兼容；UI `refresh()` 不创建网络请求。

## 本地夹具覆盖

`tests/intelligence-live-data-architecture-harness.swift` 覆盖成功、空数据、失败、限流、格式错误、禁用、慢 provider、重复事件、过期状态、刷新合并、取消、隐藏窗口暂停、TTL、凭据污染拒绝、网络策略、内容类型/响应体上限和 prompt 注入清理。所有夹具均为本地 Swift 类型，无网络。

## 验证记录

| 检查 | 真实结果 | 证据 |
| --- | --- | --- |
| Provider contract / normalized model / provenance | PASS | `tests/intelligence-live-data-architecture-unit.cjs` |
| Aggregation / deduplication / risk & source totals | PASS | architecture harness |
| Provider failure isolation / status / staleness | PASS | architecture harness |
| Cache TTL / unsafe payload rejection | PASS | architecture harness |
| Refresh coalescing / cancellation / hidden pause | PASS | architecture harness |
| Network default deny / HTTPS / host / content-type / size | PASS | architecture harness |
| Credential boundary / untrusted input sanitization | PASS | architecture harness + static contract |
| Fixture compatibility / V1.2R1 refresh path | PASS | `tests/intelligence-dashboard-unit.cjs` |
| Swift architecture harness | PASS | `intelligence live-data architecture harness: ok` |
| Swift desktop typecheck | PASS | `swiftc -typecheck ... Sources/NexusDesktop/*.swift` |
| Full offline regression | PASS | `scripts/test-nexus`：132 passed / 0 failed |
| Secret scan | PASS | `tests/secret-redaction.cjs`：208 runtime JSONL，无 credential-shaped value |
| Desktop build | PASS | `scripts/build-nexus-desktop` |
| Install / signature | PASS | `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`，`codesign --verify --deep --strict` |
| Installed launch / global panel / quit | PASS | 菜单打开 `AI Dev One · 全球情报中心`；退出后无 Nexus/Core/Runner/OSIRIS 残留 |
| Feature network activity | PASS | 新架构无 `URLSession`；面板验证期间无 OSIRIS/Runner 子进程和网络 socket |

## 明确未做的事情

- 没有授权任何真实 host，没有抓取 NASA/USGS/GDELT/GDACS 或新闻网页。
- 没有读取 API key、Keychain、环境变量中的 provider secret。
- 没有把 raw provider JSON 暴露给 View，也没有启动 OSIRIS。
- 没有移动/创建 tag，也没有 push 或 GitHub Release。

## 结果与下一阶段

`GLOBAL_INTELLIGENCE_LIVE_DATA_ARCHITECTURE_V1 = PASS`。当前架构已经为真实 provider、来源追溯、失败隔离、缓存 TTL、刷新生命周期和 AI 安全上下文预留了可测试边界，但仍保持完全离线的 Fixture 默认行为。

下一推荐阶段：`GLOBAL INTELLIGENCE · EARTHQUAKE LIVE PROVIDER V1`。该阶段应在单独的显式网络授权和人工验收下接入公开地震源，不能改变本报告所述默认拒绝策略。

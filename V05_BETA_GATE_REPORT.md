# AI Dev One Route 2 v0.5.0-beta.1 Final Beta Gate

日期：2026-08-21
状态：`FINAL BASELINE FREEZE = PASS`

本报告记录合并后的 `v0.5-dev` 最终候选。报告不包含本机绝对路径、用户数据或凭据；安装产物统一记为 `Nexus.app`。

## 基线与版本

| 项目 | 结果 |
| --- | --- |
| Branch | `v0.5-dev` |
| Merge commit | `a9e4764f3afc8c0fec3b54d21433d661cc927e15` |
| Final verified code before report | `3739d4e9b3b4bc961c620881cd2b3d265203d8c4` |
| PR #2 | `MERGED` |
| Version | `0.5.0-beta.1` |
| Build version | `1` |
| Display brand | `AI Dev One` |
| Bundle filename | `Nexus.app` |
| Bundle identifier | `cn.nexus.desktop`（未修改） |
| Final baseline SHA | 本报告提交后的最终 `HEAD`；Tag target 与 `HEAD` 逐字一致 |

唯一权威版本来源为 `apps/nexus-desktop/Info.plist`。桌面顶栏和底部状态栏的用户可见版本也已统一为 `v0.5.0-beta.1`。历史报告中的 `0.4.0-beta.1` 保留为兼容/历史记录，不属于当前产品元数据。

## Phase Gate

| 阶段 | 结果 |
| --- | --- |
| Phase 1 — Project Intelligence | PASS |
| Phase 2 — Browser Visual Verification | PASS |
| Phase 2.6 — Runtime Finalization | PASS |
| Phase 3 — GitHub Autonomous Engineering Loop | PASS |
| Final Integration | PASS |
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |

## Final Release Regression

| 检查 | 结果 | 真实证据/说明 |
| --- | --- | --- |
| `bash scripts/test-nexus` | PASS | 合并后主分支重新执行：`88 passed, 0 failed` |
| CJS regression / autonomous contracts | PASS | Project Intelligence、Browser Verification、GitHub workflow recovery、TaskTransaction、状态/布局契约均通过 |
| Swift full typecheck | PASS | 桌面端与 Project Intelligence 类型检查通过 |
| Desktop build | PASS | 从最终 `v0.5-dev` 构建 `Nexus.app` |
| Bundle metadata | PASS | `CFBundleShortVersionString=0.5.0-beta.1`；`CFBundleVersion=1`；Display Name=`AI Dev One` |
| Code signing | PASS | `codesign --verify --deep --strict` |
| App launch / quit | PASS | 最终安装候选启动并退出；无 Nexus、nexus-agent、ai-dev-one-core 残留 |
| Secret Scan | PASS | `secret-redaction.cjs` 扫描 185 个 runtime JSONL，无 credential-shaped 值；产品源代码无旧版本元数据或真实凭据 |

脚本公开保留以下非失败提示：deterministic 模式跳过本机编码代理/CLI/settings 运行时检查；未指定 `--gui` 时不主动启动桌面进程。桌面安装包、签名和启动/退出 smoke 已单独完成，因此这些提示不改变 Gate 结论。

## Reliability / Safety Smoke

| 能力 | 结果 | 证据 |
| --- | --- | --- |
| Core Recovery | PASS | 已验收的真实安装包链路 `ready → disconnected → restarting → ready`、PID 变化、单 Core、无 zombie；合并后 `core-supervisor-unit` 与 `core-crash-recovery` 回归再次通过 |
| Keychain | PASS | 既有 5/5 cold-start Gate 保持通过；本轮最终候选冷启动/退出无重复 prompt；`keychain-cold-start.cjs` 再次通过 |
| Resizable | PASS | RC3 真实安装包验收已覆盖 Sidebar `220–420`、Workspace `280–620`、快速拖动、最大化/恢复、持久化；合并后 `resizable-layout-unit.cjs` 通过 |
| Project Intelligence | PASS | acceptance gate、增量索引、敏感文件边界、项目切换和大仓库基准均通过 |
| Browser Verification | PASS | driver、安全、布局、localhost 视觉 E2E 与 acceptance fixture 通过；native AppKit 无 DOM 的 desktop/mobile 项目按有效原因跳过 |
| GitHub Loop | PASS | PR #2 已合并；waiting-ci 恢复/取消、late success、single poller、duplicate PR protection、Force Push DENY、Auto Merge DENY 均通过 |
| Rollback | PASS | 真实磁盘 checkpoint/rollback、extended modify/delete/add/rename、新目录和 interrupted rollback 均通过 SHA-256/磁盘验证 |
| Policy | PASS | Rust deny wiring、危险命令和 GitHub remote 安全契约通过 |
| Task Transaction | PASS | persistence、redaction、GitHub metadata 和 finalization race 契约通过 |

## Release Blocker 修复

合并后版本审计发现桌面 UI 仍显示旧的 `v0.4.0-beta.1`。已在 `3739d4e` 中修复顶栏和底部状态栏两个显示点；修复后重新执行完整 `scripts/test-nexus`、重新构建、签名、安装并读取 Bundle 元数据，全部通过。

## Tag Gate

创建 Tag 前已确认：

- `v0.5.0-beta.1` 不存在；
- 工作树 clean，staged=0；
- Final Integration、版本元数据、UI 版本一致性修复和本报告均在最终 ancestry；
- Final Regression、Secret Scan、Build/Sign、Launch/Quit 全部 PASS。

本地创建 annotated tag：

```text
v0.5.0-beta.1
```

Tag 创建后将再次验证 `git rev-parse HEAD == git rev-list -n 1 v0.5.0-beta.1`。本轮不推送 Tag、不创建 GitHub Release、不删除 PR task branch。

## Freeze Decision

`AI Dev One Route 2 v0.5.0-beta.1` 达到正式 Beta 封版条件：P0/P1/P2/P3 全部为 0，最终候选构建与回归通过，Tag 仅保留本地。后续普通功能进入下一开发线；v0.5 Beta 仅接受 P0/P1、安全、数据损坏或严重兼容性修复。

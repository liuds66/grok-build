# AI Dev One Route 2 v0.5.0-beta.1 Dogfood Issue Ledger

本台账用于本地真实使用期间记录 Beta 缺陷。每个问题必须经过：

`REPRODUCE → ROOT CAUSE → MINIMAL FIX → REGRESSION TEST → BUILD → REAL RETEST`

## 冻结基线

| 项目 | 值 |
| --- | --- |
| Version | `v0.5.0-beta.1` |
| Immutable tag target | `ea576b370636bc81758bfaf591b29355d817d0bf` |
| Tag type | annotated |
| Working branch | `v0.5-dev` |
| Rule | 不移动、删除或重建 `v0.5.0-beta.1`；修复只进入新 commit |

## 严重级别

- **P0**：数据损坏、Secret 泄露、错误远程写入、workspace corruption、安全边界突破
- **P1**：Core 无法恢复、Task 状态损坏、false-complete、Rollback 失败、错误 Push/PR、严重串库、无法继续工作
- **P2**：明显功能缺陷、恢复体验问题、错误提示、性能退化
- **P3**：视觉、文案、低影响 UX

## Issue Ledger

| ID | Date | Version | Baseline | Severity | Scenario | Reproduction | Expected | Actual | Root Cause | Fix Commit | Regression | Live Retest | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| — | — | `v0.5.0-beta.1` | `ea576b370636bc81758bfaf591b29355d817d0bf` | — | 初始 Dogfood 基线检查 | 尚未发现已确认缺陷 | 真实使用持续稳定 | 当前无已确认缺陷 | — | — | 启动/退出与回归基线已通过 | 待真实用户场景 | OPEN（无已确认问题） |

## 记录规则

1. 不在此文件或任何日志中记录 API Key、Authorization、Cookie、密码、Keychain 内容或完整环境变量。
2. 不直接修改冻结 Tag；修复使用 `v0.5-dev` 新 commit，并保留回归测试与真实复测证据。
3. 不为了 Dogfood 制造垃圾 Issue、PR、Push 或自动合并。
4. 只有重复任务后出现持续单调增长，才登记内存、文件描述符、Transaction 或索引持久化泄漏。
5. 关闭问题前必须填写 Fix Commit、Regression、Live Retest 和 Status。

# AI Dev One Route 2 v0.5.0-beta.2-dev

## Stable Local Code Signing / Keychain Build Continuity

执行日期：2026-08-21（Asia/Shanghai）
源码分支：`v0.5-dev`
开始时 HEAD：`d74c5cb3bb48e58d9ed1417150e6026f822b0cf2`
冻结标签：`v0.5.0-beta.1` → `ea576b370636bc81758bfaf591b29355d817d0bf`（未移动）
安装包路径：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
Bundle ID：`cn.nexus.desktop`
用户可见版本：`0.5.0-beta.2-dev` / Build `2`

本轮没有创建/移动 tag、没有 Push、没有 GitHub Release。没有输出 API key、钥匙串值、私钥、登录密码或完整个人证书信息。

## 结论

**STABLE_SIGNING_IDENTITY：BLOCKED**
**BUILD_TO_BUILD_CONTINUITY：NOT RUN**
**COLD_START 5/5：NOT RUN**
**CI / 无证书环境 ad-hoc 回退：PASS**

本机没有可用的 Apple Development 或 Developer ID Application identity。按照验收要求，停止稳定签名现场 Gate；没有用 ad-hoc 伪造 Keychain build continuity 或 Live Model PASS。

## 1. 身份预检

执行：

```text
security find-identity -v -p codesigning
     0 valid identities found
```

因此本轮没有自动创建证书、修改信任设置、放宽钥匙串 ACL、导出 `.p12` 或读取私钥。需要用户/机器管理员在本机安装并授权一个现有 Apple Development 或 Developer ID Application identity 后，才能继续 A/B/C 稳定签名与 Keychain 连续性验收。

## 2. 已实施的最小构建改动

文件：`scripts/build-nexus-desktop`

- 新增 `AI_DEV_ONE_CODESIGN_IDENTITY` 环境变量；值存在时传给现有 nested-code signing 流程。
- 未设置时保留 `codesign --force --deep --sign -`，保证 CI 和无 Apple identity 环境仍可构建。
- 构建结束明确输出 `SIGNING_MODE=APPLE_DEVELOPMENT`、`SIGNING_MODE=DEVELOPER_ID_APPLICATION` 或 `SIGNING_MODE=AD_HOC`。
- 没有硬编码姓名、Team ID、证书 hash、Keychain 密码或私钥；没有新增 `--deep`，保留现有签名顺序。

回归契约：`tests/local-signing-contract.cjs`，确认 identity 注入、ad-hoc 回退、模式输出及无敏感签名材料。

## 3. 无证书回退构建证据

使用同一源码、未设置 identity 的候选构建：

| 项目 | 实际结果 |
|---|---|
| 构建命令 | `NEXUS_DESKTOP_BUILD_DIR=<temporary> bash scripts/build-nexus-desktop` |
| 输出 | `SIGNING_MODE=AD_HOC` |
| Bundle ID | `cn.nexus.desktop` |
| 版本 / Build | `0.5.0-beta.2-dev` / `2` |
| Display brand | `AI Dev One` |
| `codesign --verify --deep --strict` | PASS |
| Team ID | not set（ad-hoc 的预期结果） |

该构建仅证明 CI 回退没有被破坏；它不满足稳定 Keychain Gate。

## 4. 未执行的稳定 Gate

| Gate | 结果 | 原因 |
|---|---|---|
| Apple Development / Developer ID identity | BLOCKED | 本机 `security find-identity` 为 0 |
| Build A/B/C stable designated requirement | NOT RUN | 没有稳定 identity |
| Legacy Keychain migration prompt | NOT RUN | 前置 stable identity 未满足 |
| Build-to-build continuity 3/3 | NOT RUN | 不得用 ad-hoc 冒充通过 |
| Candidate C cold start 5/5 | NOT RUN | 不得在不稳定身份上宣称 `credentials_ready` |
| Real Keychain Model Task A/B | NOT RUN | 前置 Keychain Gate 未满足 |
| Work Monitor live acceptance | BLOCKED | 依赖真实 Keychain credentials_ready |

## 5. 回归结果

- `scripts/test-nexus`（签名脚本改动后）：**110 passed / 0 failed**。
- `tests/local-signing-contract.cjs`：PASS。
- `bash -n scripts/build-nexus-desktop scripts/test-nexus`：PASS。
- `git diff --check`：PASS。
- 回退构建 `codesign --verify --deep --strict`：PASS（ad-hoc 仅作 CI 兼容证据）。
- 未覆盖用户安装包；未修改当前 `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`。

## 6. 后续解锁条件

1. 在本机登录钥匙串中安装并授权现有 Apple Development 或 Developer ID Application identity。
2. 重新执行 `security find-identity -v -p codesigning`，记录不含私钥的必要元数据。
3. 使用同一 identity 构建 Candidate A/B/C，比较 Team/authority/designated requirement/entitlements。
4. 仅在 A 一次迁移授权、B/C 零提示且 `credentials_ready` 时，执行正式 Dogfood 安装和 Work Monitor Live Acceptance。

在此之前，`WORK_MONITOR_LIVE_ACCEPTANCE` 不得标记为 PASS，`v0.5.0-beta.1` 不得移动，也不创建 beta.2 tag。

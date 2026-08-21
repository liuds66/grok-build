# AI Dev One Route 2 v0.5.0-beta.2-dev

## Keychain Cold-start Remediation / Work Monitor Retry

执行日期：2026-08-21（Asia/Shanghai）
源码分支：`v0.5-dev`
修复提交：`35e117e`（`fix: clarify keychain cold-start states`）
安装包路径：`/Volumes/AI-DEV/Nexus项目/应用/Nexus.app`
Bundle ID：`cn.nexus.desktop`
当前版本：`0.5.0-beta.2-dev` / Build `2`
Keychain service：`com.ai-dev-one.nexus.api-key`
Keychain account：`openai-coding`
冻结标签：`v0.5.0-beta.1` → `ea576b370636bc81758bfaf591b29355d817d0bf`（未移动）

本轮没有创建/移动 tag、没有 Push、没有 GitHub Release。没有把 API key、钥匙串密码或 Secret 内容写入报告。

## 结论

**KEYCHAIN_COLD_START_REMEDIATION：部分完成**
**WORK_MONITOR_LIVE_ACCEPTANCE：FAIL / BLOCKED**

已修复产品层状态语义：钥匙串读取期间、访问被拒绝、读取错误不再全部显示为“模型配置异常”。但是本机没有任何可用的稳定 codesigning identity，构建脚本仍使用 ad-hoc signing；因此无法完成要求的 build-to-build Keychain continuity，也不能安全地把新构建安装后作为最终 Live Model Gate 通过。

## 1. 现场证据（修改前）

### 签名与构建链

| 项目 | 实际结果 |
|---|---|
| `security find-identity -v -p codesigning` | `0 valid identities found` |
| `scripts/build-nexus-desktop` | 固定执行 `codesign --force --deep --sign -` |
| 当前安装包签名 | `Signature=adhoc` |
| Team ID | `not set` |
| 当前安装包 designated requirement | 绑定 `cdhash H"9bfd8df90940eff07099f0ec4fe4e921b498384c"` |
| Keychain access group | 源码未设置 `kSecAttrAccessGroup`；使用默认登录钥匙串归属 |
| 自定义 ACL / `SecAccessControl` | 未发现 |

当前可用签名身份不是 Apple Development、Developer ID 或其他稳定证书，而是**没有可用稳定身份**。按照安全要求，没有自动创建证书、修改信任链、执行 partition-list 放宽或导出私钥。

### Keychain 条目元数据

使用 `security find-generic-password -s ... -a ...`（未使用 `-w`）确认：

- 条目位于当前用户 login keychain；
- class 为 `genp`；
- service/account 与产品约定一致；
- 没有把 Secret 值输出到终端或报告。

代码路径只使用 `SecItemCopyMatching`、`SecItemUpdate`、`SecItemAdd`、`SecItemDelete`；新增条目使用 `kSecAttrAccessibleAfterFirstUnlock`，没有人为固定旧 executable 的 ACL。

### 同源码 Build A / B

Build A 与 Build B 均从源码 HEAD `29abda8ccddc00232c118e9c73b8e631c8b2d7f1` 构建，未改源码：

| 项目 | Build A | Build B |
|---|---|---|
| 产物 | `/tmp/ai-dev-one-build-A.iX1snz/Nexus.app` | `/tmp/ai-dev-one-build-B.JIhwOl/Nexus.app` |
| Identifier | `cn.nexus.desktop` | `cn.nexus.desktop` |
| 签名 | ad-hoc | ad-hoc |
| Team ID | none | none |
| CDHash | `9bfd8df90940eff07099f0ec4fe4e921b498384c` | `9bfd8df90940eff07099f0ec4fe4e921b498384c` |
| designated requirement | `cdhash H"9bfd8df..."` | `cdhash H"9bfd8df..."` |
| entitlements | empty | empty |

同源码、同产物内容时 CDHash 一致，但 requirement 仍然是 ad-hoc CDHash 绑定，不是稳定证书身份。

### beta.1 对照构建

在隔离 worktree `/tmp/ai-dev-one-beta1-worktree` 中 checkout 冻结提交 `ea576b370636bc81758bfaf591b29355d817d0bf` 并成功构建：

- 版本 / Build：`0.5.0-beta.1` / `1`；
- Identifier：`cn.nexus.desktop`；
- 签名：ad-hoc；
- Team ID：none；
- CDHash：`07d2d8ef26cfec79696113159420475cc214f267`；
- designated requirement：绑定该 CDHash；
- entitlements：empty。

因此 beta.1 历史的 Keychain 5/5 只能证明当时同一 binary 的连续启动，不能证明重新 build/reinstall 后的身份连续性。

## 2. 根因

根因是**构建签名身份缺失**：构建脚本用 `-s -` 进行 ad-hoc 签名，应用没有 Team ID，Keychain 对应用身份的信任无法跨代码变化稳定继承。Build C（加入本轮状态修复后）CDHash 已变为 `53e02d513bc337ecc922e8286c158726e925d369`，证明代码变化会产生新的 ad-hoc designated requirement。

本机没有可用稳定证书，所以不能在本轮通过自动生成或安装证书解决。需要用户/机器管理员提供现有 Apple Development 或 Developer ID Application identity 后，才能重新执行 build-to-build continuity。

## 3. 已实施的最小产品修复

提交 `35e117e` 只修改 3 个文件：

- `apps/nexus-desktop/Sources/NexusDesktop/main.swift`
  - 增加 `credentialsLoading`、`credentialsDenied`、`credentialsError` ModelState；
  - 根据 `SecureCredentialStore.loadState` 映射真实钥匙串状态；
  - UI 分别显示“等待钥匙串授权”“钥匙串访问被拒绝”“钥匙串读取失败”，并保持 Composer 禁用、Agent 空闲。
- `apps/nexus-desktop/Sources/NexusDesktop/WorkMonitor.swift`
  - Work Monitor 的模型状态标签同步使用上述中文状态。
- `tests/keychain-cold-start.cjs`
  - 增加状态映射与中文提示的回归契约。

没有修改 Keychain service、Bundle ID、Keychain ACL、Agent、Core、ACP、Work Monitor 架构或 UI 设计。

## 4. 实际回归结果

### 通过

- `scripts/test-nexus`：**109 passed / 0 failed**；
- Swift desktop typecheck：**PASS**；
- Project Intelligence typecheck：**PASS**；
- Keychain cold-start contract：**PASS**；
- Work Monitor / timeline contracts：**PASS**；
- Secret redaction：**PASS**（199 个 runtime JSONL，无 credential-shaped 值）；
- Build C（本轮修复代码）：**PASS**，桌面包成功生成；
- `codesign --verify --deep --strict`：**PASS**（但仍是 ad-hoc，不代表稳定身份）；
- 安装包元数据：`AI Dev One`、`cn.nexus.desktop`、`0.5.0-beta.2-dev` / `2`：**PASS**。

### 状态现场重测

候选 Build C 在无 `OPENAI_API_KEY` 环境注入下启动后，AX UI 真实显示：

```text
等待钥匙串授权
Agent 空闲
```

这证明状态语义修复生效；本轮没有把环境变量注入当成 Keychain 成功，也没有执行真实模型 Task A/B。

## 5. 尚未通过 / 阻塞

| Gate | 结果 | 原因 |
|---|---|---|
| Stable signing identity | **BLOCKED** | `security find-identity` 为 0；不能自动创建证书 |
| Build-to-build continuity 3/3 | **NOT RUN / FAIL** | 没有稳定 signing identity，不能宣称跨安装连续 |
| Keychain cold start 5/5（新候选安装包） | **NOT VALIDATED** | 未在不稳定 ad-hoc 身份上伪造通过 |
| `credentials_ready` 无环境注入 | **FAIL / BLOCKED** | 当前登录钥匙串读调用在该 ad-hoc 身份下可能等待 SecurityAgent |
| Real Keychain model Task A | **NOT RUN** | 前置 Keychain Gate 未通过 |
| Task B manual live | **NOT RUN** | 前置 Keychain Gate 未通过 |
| Task B auto-open / manual close / reopen / Pin / main-window close | **NOT RUN** | 没有有效 Task B |
| Work Monitor final live acceptance | **FAIL / BLOCKED** | 必需前置 Gate 未满足 |

前一份 Task A（环境临时注入凭据）证据仍保留在 `V05_BETA2_WORK_MONITOR_LIVE_ACCEPTANCE.md`，但不被本轮当作 Keychain-loaded model PASS。

## 6. 性能与安全

- 延续前次现场观察：大项目扫描约 84% CPU / 380 MB RSS，分类为 P2 observation，未进行足够长的 soak 以升级为 leak；
- 本轮未写入或打印 API key、Authorization、钥匙串密码；
- 发现的测试 fixture 中的 `sk-test-*` / `sk-live-*` 是脱敏回归样本，不是真实凭据；secret-redaction 契约通过；
- 本轮测试结束后无 Nexus/Core/Agent 残留进程。

## 7. 最终版本与 Git 状态

```text
Current version: 0.5.0-beta.2-dev
Fix commit: 35e117e
Frozen tag target: ea576b370636bc81758bfaf591b29355d817d0bf
v0.5.0-beta.1 moved: NO
New tag: NONE
Push: NONE
GitHub Release: NONE
```

下一步必须先提供稳定的 Apple Development / Developer ID signing identity；在此之前，不应标记 `WORK_MONITOR_LIVE_ACCEPTANCE = PASS`，也不应创建 beta.2 tag。

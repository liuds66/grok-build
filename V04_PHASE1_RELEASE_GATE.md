# AI Dev One Route 2 v0.4 Phase 1.5 · Release Gate

日期：2026-08-16
验收对象：外置盘上的 `Nexus.app`（应用内显示名为 **AI Dev One**）
结论：**BLOCKED — 现场 Gate 尚未满足进入 Phase 2 的条件**

本轮只验收可靠性、恢复、安全、回滚、审计和布局自愈；不改变 Deep Forest 三栏 UI 主设计，不修改 ACP、Rust Core 架构或工具后端。

## 发布工程身份

| 项目 | 实际值 |
| --- | --- |
| Project absolute path | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座` |
| Git repository root | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座` |
| Git commit SHA | `a5727c5960452e7527a154b25cb5bf00cda0545e` |
| Current branch | `codex/nexus-agent` |
| App source path | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/apps/nexus-desktop/Sources/NexusDesktop` |
| Rust source path | `/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/crates/codegen` |
| Built application path | `/Volumes/AI-DEV/Nexus项目/应用/Nexus.app` |
| Bundle Identifier | `cn.nexus.desktop` |
| App display name | `AI Dev One` |
| App version | `0.3.0` |
| App file name | `Nexus.app` |

`Nexus.app` 是保留的上游/兼容包文件名；用户可见品牌已经是 AI Dev One。桌面入口 `/Users/mac/Desktop/Nexus.app` 指向外置盘的上述应用。`/Applications/AI Dev One.app` 是旧的 0.1.0 副本，本轮没有使用它。

## 本轮 DeepSeek 配置

已将外置盘应用使用的 OpenAI-compatible 模型配置切换为：

- endpoint：`https://api.deepseek.com`
- model：`deepseek-v4-flash`
- backend：`chat_completions`
- 凭据位置：macOS Keychain（服务 `com.ai-dev-one.nexus.api-key`，账户 `openai-coding`）

配置文件只保存地址、模型和协议，不保存 API Key；运行日志和审计记录也未写入凭据。模型/接口选择依据 DeepSeek 官方文档：<https://api-docs.deepseek.com/zh-cn/guides/function_calling/>。

## Release Gate 现场结果

| Test | Expected | Actual | PASS/FAIL | Evidence |
| --- | --- | --- | --- | --- |
| Swift 桌面编译 | 外置盘源码可编译 | DeepSeek 文案/默认配置改动后重新编译并签名成功 | PASS | `/tmp/ai-dev-one-v04/install-deepseek-final.log` |
| 安装/启动正确应用 | 启动外置盘 `Nexus.app` | 当前外置盘进程 PID 19422；显示名 AI Dev One | PASS | `/tmp/ai-dev-one-v04/install-deepseek-final.log`、`/tmp/ai-dev-one-v04/release-metadata.txt` |
| Swift/AppKit 离线回归 | 无失败 | 67 通过，0 失败 | PASS | `/tmp/ai-dev-one-v04/test-nexus-deepseek-final.log` |
| CJS 状态回归 | 状态、错误卡、布局、脱敏均通过 | 14 个脚本全部退出 0 | PASS | `/tmp/ai-dev-one-v04/cjs-deepseek-final.log` |
| Checkpoint 基础回滚 | 磁盘内容恢复 | `verified=true restored=3 removed=2` | PASS | `/tmp/ai-dev-one-v04/rollback-phase15-final.log` |
| Checkpoint 扩展回滚 | 修改/删除/新增/重命名/目录变化按 SHA-256 恢复 | `verified=true sha256=true restored=3 removed=5` | PASS | `/tmp/ai-dev-one-v04/rollback-phase15-final.log` |
| Interrupted Task + Rollback | Core 中断后真实磁盘回滚 | `interrupted=true rollback=true finalState=rolled_back` | PASS | `/tmp/ai-dev-one-v04/rollback-phase15-final.log` |
| Transaction 审计/脱敏 | 状态持久化，不能写入凭据 | 离线 harness persistence/redaction 通过；运行时 JSONL 60 个文件无凭据形态 | PASS（离线） | `/tmp/ai-dev-one-v04/cjs-phase15-final.log`、`tests/secret-redaction.cjs` |
| 旧会话错误卡清理 | 同根因只保留一个主错误 | 重启前 `model=1,cancel=1`；重启后 `model=1,cancel=0` | PASS | `desktop-sessions.json` 计数探针、`tests/error-card-dedup.cjs` |
| Keychain 无凭据冷启动 | 不白屏、不阻塞、不重复弹窗，可进入设置 | 真实启动 probe 完成，`model.hasAPIKey=false`，UI/窗口正常 | PASS（missing-key 场景） | `/tmp/ai-dev-one-v04/layout-self-heal-*.txt` |
| Keychain 有效凭据冷启动 | 读取一次并进入 Model Ready | 首轮发现旧 ACL 条目解密超时；已重建为仅信任外置盘 AI Dev One 主程序的条目，修复后非交互读取退出 0，应用重启正常 | PASS（修复后复测） | `/tmp/ai-dev-one-v04/qa-run2-fixed-1786825663.log` |
| DeepSeek Keychain 配置 | 密钥只进钥匙串，配置不落明文 | `com.ai-dev-one.nexus.api-key/openai-coding` 存在；`~/.nexus/config.toml` 无 `api_key`；运行日志无凭据形态 | PASS | `/tmp/ai-dev-one-v04/qa-run1-full.log`、`/tmp/ai-dev-one-v04/qa-run2-fixed-1786825663.log` |
| DeepSeek 模型列表 | endpoint/key 可用，模型存在 | `GET https://api.deepseek.com/models` 返回 HTTP 200，2 个模型，`deepseek-v4-flash` 可用 | PASS | 现场终端结果（不输出密钥） |
| DeepSeek Chat Completions | OpenAI-compatible 请求有可见回复 | `POST /chat/completions` HTTP 200，模型 `deepseek-v4-flash`，finish=stop，content 2 字符，reasoning 101 字符 | PASS | 现场终端结果（不输出响应正文/密钥） |
| Core Crash Recovery | 真实任务中 `ready→disconnected→restarting→ready`，任务 interrupted | 仅完成状态机/退避静态 harness；当前无可用模型任务，未 kill 真实任务 | NOT RUN / BLOCKED | `tests/core-crash-recovery.cjs`、`V04_QA_REPORT.md` |
| Crash Loop | 连续失败后有限重启并进入 failed | 仅完成 bounded-retry harness，未现场制造真实 Core crash loop | NOT RUN / BLOCKED | `tests/core-crash-recovery.cjs` |
| Policy Live Sandbox | Agent→Tool→Policy→Execution 实链，危险命令不执行 | deny 规则接线、Rust actor policy 测试待最终编译；未用真实模型启动工具链 | NOT RUN / BLOCKED | `tests/policy-enforcement.cjs`、Rust policy test log |
| Rust Policy compile | cargo check/test 实际通过 | 安装器 Rust 构建产物已运行 policy 集成测试：17 通过、0 失败 | PASS | `/tmp/ai-dev-one-v04/cargo-test-policy-live.log`、`/tmp/ai-dev-one-v04/policy-test-binary.log` |
| Verification Gate | Node/Rust/Python/Go 输出 PASS/FAIL/SKIPPED | 项目识别和缺命令 SKIPPED contract 通过 | PASS（contract） | `/tmp/ai-dev-one-v04/cjs-phase15-final.log` |
| Resizable / Window self-heal | 异常 pane/frame 自动恢复，BrowserWindow 不变窄 | 注入 sidebar=99999、workspace=0、frame=28×28 后恢复为窗口 1440×900、pane 260/340；窗口 probe 正常 | PASS（自动） | `/tmp/ai-dev-one-v04/layout-self-heal-*.txt` |
| 真实鼠标拖拽 | 220↔420、280↔620，快速拖 30 次 | Accessibility 未授权，本轮未完成物理鼠标验收 | NOT RUN | 需要用户现场拖拽记录 |
| 签名/桌面入口 | 外置 app 可验证，桌面链接正确 | `codesign --verify` 通过，桌面链接指向外置 app | PASS | `/tmp/ai-dev-one-v04/install-phase15-redaction.log` |

## 已修复的发布问题

1. Rust sampler 不再记录 `api_key`、Authorization 前缀或 `x-api-key` 前缀；结构化上游 401 文案会先脱敏。
2. Rust auth 诊断的历史 token suffix 改为固定 `[REDACTED]`，不再把凭据尾部写入日志/telemetry。
3. Swift 错误脱敏覆盖 `sk-*`、`xai-*`、Bearer 和掩码尾部。
4. 已清理已有运行日志中的凭据形态；当前 60 个 runtime JSONL 文件扫描为 0 命中。文档示例中的 `sk-` 不属于运行日志。
5. 旧会话中“任务已停止”与“API 配置异常”并存的问题已在加载时自愈，重启后只保留可操作的主错误。
6. 外置盘应用已重新构建、签名、安装并启动；没有再启动 `/Applications` 下的同名旧副本。
7. 本轮按用户要求切换到 DeepSeek；实测模型列表和 Chat Completions 均返回 HTTP 200。密钥只保存在 macOS Keychain。
8. 修复了旧钥匙串条目的 ACL 解密阻塞：删除不可读旧条目后，按外置盘 AI Dev One 主程序路径重新建立受限访问条目；修复后 `security` 非交互读取和 DeepSeek 请求均通过。

## Gate 阻断项

### P0 Critical

| 问题 | 影响 | 当前状态 |
| --- | --- | --- |
| 有效 Key 的 Keychain 冷启动未现场证明 | 不能确认解锁钥匙串后一次读取即可进入 Model Ready | BLOCKED |
| 真实模型任务 Core kill/recovery 未现场证明 | 不能把代码级退避逻辑等同于现场恢复 | BLOCKED |
| Policy Live Sandbox 未走 Agent→Tool→Execution 实链 | 不能把静态 deny 接线等同于真实危险命令阻断 | BLOCKED |

### P1 High

| 问题 | 影响 | 当前状态 |
| --- | --- | --- |
| 真实任务中的 Agent 四阶段推进未现场执行 | 目前只有状态机和离线 harness 证据 | 待有效模型/隔离测试项目 |
| 真实鼠标拖拽 30 次未自动化 | 只能证明 pane/frame 自愈，不能证明 Accessibility 事件链 | 待人工 |

## Gate 规则结论

本轮 **P0 未解决不为 0**，因此不批准进入 v0.4 Phase 2。已通过的回滚、日志脱敏、窗口自愈、Swift 构建和离线状态机测试可以保留；下一步应只补齐上表三个现场阻断项，不要继续增加新功能。

## 建议的下一次现场验收顺序

1. 在钥匙串已解锁且有有效测试凭据的 macOS 会话中冷启动一次，确认只读取一次并进入 Model Ready。
2. 在完全隔离的临时 Git 项目中，用可控测试模型启动真实任务，kill 外置盘应用所启动的 Core/agent，确认 interrupted、1/2/5 秒退避、恢复后不重复任务。
3. 走真实 Tool Execution Chain 验证 `echo`、`git status`、危险命令 deny/ask，确认磁盘保护文件未被改变。
4. 获得 Accessibility 权限后，手工完成两侧 pane 的最小/最大/快速拖拽和重启恢复。

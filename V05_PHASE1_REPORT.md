# AI Dev One Route 2 v0.5 Phase 1

## Project Intelligence / 项目智能

开发线：`v0.5-dev`
基线：`v0.4.0-beta.1` / `07e6dfe78cabcdac6086bfabf1d4edfbf0310bff`

本阶段保持 Deep Forest UI、Rust Core、ACP、Policy、Checkpoint、Agent Pipeline 和验证门不变，加入本地优先的 Project Intelligence Layer。

### 已实现

- `Project`、`FileNode`、`SymbolNode`、`DependencyEdge`、`ModuleNode`、`TestNode`、`TaskKnowledge` 数据模型，带 `indexVersion`。
- 项目 fingerprint：规范化路径 + Git root + 本地 repository identity 的确定性摘要。
- 扫描器：文件系统结构、`.gitignore`、语言/栈/框架置信度、入口、Git branch/HEAD/dirty files、模块、测试和依赖。
- TypeScript/JavaScript、Rust、Python、Swift、Go 的轻量 symbol/import/export 解析；未知语言仍保留 `FileNode`。
- 默认排除 `.git`、`node_modules`、`target`、构建产物、虚拟环境、缓存等目录；跳过项目外符号链接、二进制内容和超大依赖目录。
- `.env`、凭据、私钥等只记录存在性和元数据，不读取内容、不生成内容 hash。
- Application Support 本地持久化；已有 `Application Support/Nexus` 数据根优先复用，新安装使用 `Application Support/AI Dev One/project-intelligence`。
- 增量索引基于 path/mtime/size/hash，未变化文件直接复用；目录变化使用 debounce watcher。
- `ProjectContextProvider` 提供 bounded、确定性相关性查询：overview、files、symbols、relations、related tests、modules、recent task knowledge。
- Agent 任务启动前附加小型项目上下文；索引不可用时透明回退到传统 search/read/grep 工具。
- Task Transaction 完成/失败/中断后回写 `TaskKnowledge`，摘要、命令和验证信息脱敏并限制长度。
- Checkpoint 真实磁盘回滚后发布通知，Project Intelligence 自动强制重建受影响项目索引。
- 知识库 Tab 展示索引状态、文件/模块/符号/测试计数、栈、增量统计、更新时间和重新索引入口，同时保留 MCP/插件/技能产品化状态。

### 回归测试

`tests/project-intelligence-unit.cjs` 会创建隔离临时项目，验证：

- `.gitignore` / 依赖目录排除；
- 敏感文件标记和内容不读取；
- symbol、import/dependency、test intelligence、React/Vite stack detection；
- 增量复用和变更重解析；
- 本地持久化、确定性 relevance ranking、bounded context；
- TaskKnowledge 写回。

运行：

```text
~/Library/Application Support/AI Dev One Installer/toolchains/node/bin/node tests/project-intelligence-unit.cjs
```

### 明确边界

- 第一阶段不引入 embedding、向量数据库、外部服务或网络依赖。
- 解析器是轻量分层解析，不替代完整 AST；后续 v0.5.x 再增强。
- 目录 watcher 是最小本地 watcher；Agent 始终保留传统工具回退路径。

### Acceptance Gate / QA / 构建结果（2026-08-18）

#### 基线与工作树

| 项目 | 结果 |
| --- | --- |
| 分支 | `v0.5-dev` |
| v0.4 基线提交 | `07e6dfe78cabcdac6086bfabf1d4edfbf0310bff` |
| `v0.4.0-beta.1` tag 指向 | `07e6dfe78cabcdac6086bfabf1d4edfbf0310bff`（未修改） |
| Phase 1 变更 | 仅 Project Intelligence、Checkpoint 回滚通知、Workspace 接入、测试和本报告 |
| Rust Core / ACP / Agent Runtime | 未修改 |

#### 真实项目与索引验收

`tests/project-intelligence-acceptance.cjs` 编译并运行真实 Swift harness；fixture 全部是真实临时 Git 项目，另外扫描仓库内实际的 `apps/nexus-desktop` Swift 子项目。最终输出：

```text
REAL_PROJECT swift-subproject files=8 modules=2 symbols=400 tests=0 languages=Swift branch=v0.5-dev seconds=1.751
REAL_PROJECT typescript files=10 symbols=2 tests=1 branch=main
REAL_PROJECT rust files=5 symbols=3 tests=1 branch=main
REAL_PROJECT python files=5 symbols=2 tests=1 branch=main
INCREMENTAL first=10 secondReused=10 modifiedChanged=1 added=1 deleted=1 renamed=1 testChanged=1
PERSISTENCE cachedLoad=0.006947s files=10
INDEX_VERSION invalid=rejected rebuild=PASS
SENSITIVE_BOUNDARY fileMetadata=PASS contentHash=nil taskKnowledgeRedaction=PASS
CONTEXT overviewFiles=10 relevantFiles=2 symbols=1 relatedTests=1 serialized=237 architectBridge=PASS
PROJECT_SWITCH callbacks=3 acceptedFinal=C requestToken=PASS
ROLLBACK_REINDEX disk=PASS files=4 hashes=PASS dependencies=PASS relatedTests=PASS
WATCHER event=PASS debounce=PASS incremental=PASS
BENCH files=100 first=0.657s cached=0.574s incremental=0.624s reused=100 changed=1
BENCH files=1000 first=1.803s cached=0.874s incremental=0.913s reused=1000 changed=1
BENCH files=5000 first=7.957s cached=2.354s incremental=2.412s reused=5000 changed=1
PASS project intelligence acceptance gate
```

覆盖结论：

- TypeScript、Rust、Python、Swift 均通过真实磁盘索引；Git branch/HEAD、文件、模块、symbol、依赖和测试元数据均有断言。
- `.gitignore` 与默认排除目录（`.git`、`node_modules`、`target`、`dist`、`build`、`DerivedData`、虚拟环境、coverage）均未进入索引。
- 修改、新增、删除、rename、测试文件变更均只产生单文件增量变更；无变化扫描复用全部 10 个文件。
- 冷缓存 JSON 载入实测 `0.006947s`；非法 `indexVersion` 被拒绝后安全重建，没有 crash 或静默使用旧 schema。
- 项目 A→B→C 异步切换只接受 C 的回调；旧 request 不会覆盖当前项目。
- Checkpoint 回滚后实际磁盘 hash、文件集合、依赖和 related tests 全部重新验证。
- watcher 事件、debounce 与增量重建均通过；5000 文件压力测试没有横向溢出或崩溃。

#### Sensitive Boundary

fixture 包含 `.env`、`.env.local`、`credentials.json`、假私钥和假 `~/.ssh/id_rsa`。结果：

- `FileNode` 只保留 `sensitive` 与元数据；`hash=nil`，不提取 symbol，不读取 secret 内容。
- `TaskKnowledge` 在 service `record`、store `save`、store `load` 三层脱敏；假 `sk-`、Bearer、token 内容均未进入 JSON。
- 运行 `tests/secret-redaction.cjs`：扫描 165 个 runtime JSONL 文件，未发现 credential-shaped value；同时加入了对 `xai-grok-*`、`task-transaction-*` 路径误报的回归断言，并验证真实形态的 synthetic `sk-`/`xai-`/`Bearer` token 仍会被捕获。

#### Agent / Architect / Verifier 证据

| 检查 | 结果 | 证据与边界 |
| --- | --- | --- |
| ProjectContextProvider 查询 | PASS | bounded context 237 字符、2 个相关文件、1 个 symbol、1 个 related test；`promptContext` bridge 合约通过 |
| Architect 入口 | PASS | `MainViewController.beginTask` 在 `runner.send` 前调用 `ProjectContextProvider.promptContext`；索引未就绪时明确 fallback 到传统 search/read/grep |
| 真实 Agent 运行 | PASS | 安装构建的 App 通过真实模型执行只读任务；Transaction `bfa2ba8e-a5ae-4679-bdbb-9ededa628b9f` 最终 `completed`，Core/Model 均 ready，实际 tool call 完成 |
| 冷启动降级 | PASS | 真实大仓库首次扫描尚未就绪时，Agent 仍完成只读任务；未把索引暂不可用升级为 Agent 失败 |
| Verifier related-tests | PASS | 索引层将 `src/math`→`tests/math.test.ts` 关联并在 harness 断言；Verifier 仍运行项目定义的验证门，未知/缺失命令明确 SKIPPED |
| TaskKnowledge | PASS | 完成/失败/中断路径均回写；本次真实只读任务的 audit 不含 key、Bearer 或 Authorization |

注：真实大仓库任务是在索引冷启动期间执行，因此该次 audit 记录的是“传统工具 fallback”，不是强行伪造的 indexed-context 注入；这是设计中允许的降级路径。indexed-context 的查询与注入契约由真实 Swift harness 和源码 typecheck 覆盖。

#### v0.4 回归、构建与运行

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `bash scripts/test-nexus` | PASS | 79 项通过，0 项失败（包含 Project Intelligence Acceptance Gate） |
| 全部 CJS 回归 | PASS | 21 个 `tests/*.cjs`，`CJS_TOTAL=21 CJS_FAILED=0` |
| Swift 桌面端类型检查 | PASS | AppKit/Foundation 全量源码 typecheck |
| Project Intelligence 独立类型检查 | PASS | `ProjectIntelligence.swift` Foundation typecheck |
| 桌面应用构建 | PASS | `scripts/build-nexus-desktop` |
| Bundle / 签名 / 资源 | PASS | `dist/Nexus.app`，`codesign --verify --deep --strict` |
| Launch / Quit smoke | PASS | 安装构建启动、窗口可见、正常退出；无残留 Core/child process |
| v0.4 状态/策略/回滚/Keychain/Resizable 回归 | PASS | 既有 CJS contract tests 全部通过 |
| Secret scan | PASS | 165 个 runtime JSONL；无真实 key、Bearer、Authorization 或密码；修复了路径名造成的 detector false positive |

构建产物：`/Volumes/AI-DEV/Nexus项目/源代码/grok Build底座/dist/Nexus.app`。Bundle ID 仍为 `cn.nexus.desktop`，显示名为 `AI Dev One`，版本元数据仍是 `0.4.0-beta.1`（Phase 1 不引入第二套 v0.5 版本机制）；`v0.4.0-beta.1` tag 未修改。该构建未复制到外置盘安装目录，`dist/Nexus.app` 是本轮签名验证的真实产物。

### 本轮边界修复

- 空项目路径不再启动 watcher 或索引任务，避免首次启动时扫描错误目录。
- 项目切换或清空时先失效旧 request ID；知识库生态查询也携带 request ID，避免旧项目异步结果串写。
- 敏感文件在 mtime/size 未变化时仅复用元数据，不读取内容、不生成内容 hash。
- `TaskKnowledge` 在写入和读回边界均脱敏，避免历史 index 中的旧 secret 重新出现。
- MCP/插件的空状态与 CLI help/error 经过产品化映射，不把 Grok 原始英文帮助直接暴露到中文知识库页。
- Checkpoint 的真实磁盘 rollback 完成后发送唯一通知，触发受影响项目的强制 reindex。

### 已知限制与后续边界

- 解析器是轻量分层解析，不替代完整 AST；后续 v0.5.x 再增强。
- watcher 是最小本地目录 watcher，不承诺递归 FSEvents 级别的全仓库实时性。
- 当前安装构建仍沿用 v0.4 bundle 版本字符串；正式 v0.5 版本号应在发布阶段按仓库既有机制更新。
- 完整上游 monorepo 的一次性扫描属于外置盘 endurance 场景，实测耗时明显高于 bounded 子项目；应用仍在后台扫描且 Agent 可走 fallback。Phase 1 gate 使用真实 Swift 子项目 + 多语言真实 Git fixture + 100/1000/5000 文件压力数据，未把外置盘 endurance 当作逻辑失败。

### Phase 1 Gate 结论

| 优先级 | 未解决数 | 结论 |
| --- | ---: | --- |
| P0 | 0 | 安全边界、索引数据完整性、rollback reindex、启动稳定性均 PASS |
| P1 | 0 | 增量、持久化、race、context bridge、fallback、Verifier related-test 合约均 PASS |
| P2 | 0 | 本轮未引入可见 P2 回归 |
| P3 | 0 | 本轮未引入 P3 回归 |

**结论：Phase 1 Acceptance Gate PASS，允许提交为 `v0.5-dev` Project Intelligence baseline；不创建 v0.5 tag，不修改 `v0.4.0-beta.1`。**

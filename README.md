# Nexus（中文版）

**Nexus** 是一个本地优先、自己选择模型的中文桌面编码代理。它基于开源的
Grok Build runtime，提供接近 Codex 的工作方式和桌面界面：左侧管理任务，中间查看
对话，底部输入需求，并在设置页管理模型与 API Key。终端命令也继续保留。

- 使用 OpenAI、Anthropic、OpenRouter 或本地 Ollama；密钥由你自己保管；
- 会话、授权、技能、MCP、hooks 与 worktree 都放在 `~/.nexus`，不会混入已有的
  Grok 安装；
- 默认关闭遥测和自动更新，默认逐次确认高风险操作；
- 提供中文命令帮助、中文配置预设和中文使用文档。

## 对齐 Codex，同时保留 Nexus 优势

Nexus 对齐成熟编码代理的核心工作流：任务会话、项目上下文、流式对话、工具过程、
文件更改、终端、权限确认、MCP、技能和插件生态。它保留自己的产品取向：

- 中文优先：界面、设置、权限提示和常用错误均以中文呈现；
- 模型可替换：支持 OpenAI、Anthropic、OpenRouter 和本地 Ollama，不绑定单一模型服务；
- 本地可控：会话、配置、技能和插件保存在本机，可审查、备份和迁移；
- 外置便携：项目可以完整放在 EAGET-A，源码、会话、缓存和桌面 App 一起迁移；
- 生态兼容：读取 `.codex/skills`、MCP、插件、hooks 和 worktree，并保留终端入口。

因此 Nexus 的目标是“工作方式对齐、产品选择自主”，而不是复制任何专有客户端的内部实现。

Nexus 与 OpenAI、Codex、xAI 均没有隶属或授权关系；不会使用 Codex 服务、凭据或
专有实现。

## 一键安装

在 macOS 上可直接在 Finder 中双击 [安装Nexus.command](安装Nexus.command)，它会打开终端并执行安装。
也可以在本仓库根目录运行：

```sh
./install.sh
```

安装器会在 macOS/Linux 上自动完成以下事项：

1. 若缺少 Rust，则通过官方 rustup 安装最小 Rust 工具链；
2. 安装构建上游 runtime 所需的 DotSlash；
3. 构建经过 Nexus 品牌化的 `nexus-agent`；
4. 在 `~/.local/bin/nexus` 创建命令入口，且绝不覆盖同名的非 Nexus 文件；
5. 在 macOS 上构建并安装桌面 App；如果源码位于 EAGET-A 外置容器，会自动安装到该容器，桌面入口保持不变。

安装器不会主动索取或保存 API Key。安装后的设置中心可将密钥保存到仅当前用户可读的
`~/.nexus/config.toml`。若 `~/.local/bin` 不在 `PATH` 中，安装器会输出应加入 shell
配置的命令。可先安全预演：

```sh
./install.sh --dry-run
```

其他可选参数：

```sh
./install.sh --prefix "$HOME/.local"  # 指定命令入口目录
./install.sh --skip-deps              # 已有 Rust 和 DotSlash 时跳过检查
./install.sh --skip-build             # 仅创建命令入口
```

Intel Mac 在上游 DotSlash 缺少对应 `protoc` 时，会自动下载官方 protobuf 到
`~/.cache/nexus`，只作为本地构建工具使用。

## 启动桌面版

安装完成后双击桌面的 `Nexus.app`。桌面版包括：

- Codex 风格的任务侧边栏、聊天内容区和底部输入框；
- 每个任务独立的上下文与项目目录，可连续追问；
- 流式回复、运行状态和停止按钮；
- 全中文设置页，可安全保存 OpenAI API Key、模型和接口地址；
- 会话保存在 `~/Library/Application Support/Nexus`，API Key 仍只保存在
  `~/.nexus/config.toml`。

如果使用 EAGET-A 外置盘，桌面启动器会在启动时自动挂载 `AI-DEV.sparsebundle`，并修复项目、配置、缓存和会话的兼容链接。
运行或编译 Nexus 时不要直接拔出外置盘。

左下角打开“设置”，填写有效的 OpenAI API Key 后即可使用。不要把密钥发送到聊天中。

## 使用终端版

```sh
nexus init openai
nexus settings set-key openai
nexus
```

首次运行 `nexus init` 会把配置写到 `~/.nexus/config.toml`，文件权限为仅当前用户可读。
`nexus settings set-key openai` 会以隐藏输入方式保存 API Key，之后无需再 `export`。
环境变量 `OPENAI_API_KEY` 仍然可用，适合 CI 等临时场景。可选模型预设：

```sh
nexus init anthropic
nexus init openrouter
nexus init ollama
```

在任意目标仓库中执行下列命令即可工作：

```sh
nexus plan "重构支付模块，先列出风险和实施步骤"
nexus review "重点检查权限绕过和测试遗漏"
nexus run -p "运行测试并修复失败" --output-format json
nexus resume
```

## 功能

| 需求 | Nexus 命令 |
| --- | --- |
| 交互式编码会话 | `nexus` 或 `nexus run` |
| 修改前先规划 | `nexus plan "任务"` |
| 只读代码审查 | `nexus review` |
| CI/自动化 | `nexus run -p "任务" --output-format json` |
| 恢复本地会话 | `nexus resume [会话 ID]` |
| MCP、skills、hooks、worktree、子代理 | 由底层 runtime 提供 |

`nexus help` 显示中文命令帮助。底层终端 runtime 的部分深层提示仍沿用上游英文文案；
这能使我们持续合并上游运行时和安全修复，而无需维护大规模的本地 fork。

设置中心不会显示已保存密钥的内容：

```sh
nexus settings
nexus settings set-key openai
nexus settings clear-key openai
```

## 安全默认值

Nexus 默认用 `workspace` sandbox 启动：允许写入当前项目，但限制项目外、Nexus 状态目录
与临时目录之外的写入。普通会话默认逐次确认；`nexus review` 使用只读 sandbox；不可信
仓库可显式使用 `--sandbox strict`。

沙箱只是保护层之一。任何命令执行或文件写入授权前，仍应仔细检查具体操作。

## 开发与验证

```sh
./scripts/test-nexus --gui
./scripts/build-nexus
./bin/nexus help
bash -n bin/nexus scripts/build-nexus scripts/install-nexus install.sh
cargo fmt --check
```

`scripts/test-nexus` 是不调用真实模型 API 的离线回归烟测：会检查桌面端类型、输入框和搜索入口、编码代理命令、MCP/插件/worktree、外置盘兼容链接、App 签名与启动器自愈。日常改 UI 或迁移外置盘后先运行它；不带 `--gui` 时不会要求 Nexus 进程已启动。

构建产物默认位于 `~/.cache/nexus/target/release/nexus-agent`。Nexus 只额外维护品牌入口、
模型预设、私有状态目录和安全默认值；低层 Rust crate 继续使用 `xai-grok-*` 名称，以便
稳妥地同步上游更新。

详细说明请见：[中文使用指南](docs/GETTING_STARTED_CN.md)、
[设计边界](docs/NEXUS-DESIGN.md)。

## 上游与许可证

Nexus 基于 [xai-org/grok-build](https://github.com/xai-org/grok-build)，其第一方源码采用
Apache-2.0 发布。本仓库保留上游 `LICENSE` 和 `THIRD-PARTY-NOTICES`；分发 Nexus 构建时
必须一并保留这些许可证与第三方声明。

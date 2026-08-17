# Nexus 使用指南

Nexus 是一个基于 Grok Build 开源 runtime 的本地优先编码代理。它的交互方式接近
Codex：先理解仓库、必要时先给计划、经确认后修改代码、执行测试，并保留会话和 diff。

## 1. 一键安装

在本仓库根目录运行：

```sh
./install.sh
```

它会自动安装缺失的 Rust 与 DotSlash、构建 Nexus，并创建 `nexus` 命令入口。默认入口是
`~/.local/bin/nexus`；若该目录不在 `PATH`，安装器会给出添加方式。可用下面的命令预览，
不会修改系统：

```sh
./install.sh --dry-run
```

在 macOS 上也可直接双击仓库根目录的 `安装Nexus.command`，它会在终端中运行同一个安装器。

生成的二进制默认放在 `~/.cache/nexus/target/release/nexus-agent`。日常使用 `nexus`，
它会自动选择该二进制。若你只想在当前仓库中构建，也可使用 `./scripts/build-nexus`。

## 2. 选择模型提供商

下面示例创建配置，配置统一保存在 `~/.nexus/config.toml`，与已有的
`~/.grok` 隔离。设置中心会把 API Key 写入该文件中对应模型的 `api_key` 设置。

```sh
./bin/nexus init openai
nexus settings set-key openai
```

其他可选预设：

```sh
./bin/nexus init anthropic
./bin/nexus init openrouter
./bin/nexus init ollama
```

预设中的模型名称只是可编辑起点；请换成你的账号或本地服务实际提供的、支持工具调用的模型。

`nexus settings set-key openai` 会以不回显的方式读取密钥，并保存到权限为 `600` 的
`~/.nexus/config.toml`。之后正常运行 `nexus` 即可，无需重复设置 `OPENAI_API_KEY`。
在 CI 中仍可使用环境变量作为临时备用方式：

```sh
export OPENAI_API_KEY="你的密钥"
```

## 3. 在目标项目中工作

```sh
cd /path/to/your/project
nexus
```

常用命令：

```sh
nexus plan "重构支付模块，先给出风险和实施计划"
nexus review "重点检查权限绕过和测试遗漏"
nexus run -p "运行测试并修复失败" --output-format json
nexus resume
```

`plan` 会以计划模式启动：除计划文件外不允许修改项目文件。`review` 使用只读
sandbox。普通 `nexus` 默认使用 `workspace` sandbox；它可以写当前项目，但不应依赖它
获得系统级隔离，仍应仔细审查授权请求。

## 4. 扩展能力

上游 runtime 已带有 MCP、skills、hooks、worktree、headless 模式、ACP 和子代理能力。
从 Nexus 启动时，它们的全局目录会落到 `~/.nexus`。项目级指令和规则继续放在目标项目中，
这样可以与 Git 一起评审和管理。`nexus help`、安装器、配置预设和默认审查指令均已中文化；
底层 runtime 的部分深层提示仍沿用上游英文，以便及时合并上游安全修复。

如果你已有 Grok Build，请放心：Nexus 只在自己启动的进程中设置兼容变量，不会改写已有
`~/.grok` 的会话、配置或密钥。

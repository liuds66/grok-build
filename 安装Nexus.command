#!/usr/bin/env bash
# macOS Finder 双击安装入口。
set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
printf '\n正在安装 Nexus 中文版……\n\n'

if "${script_dir}/install.sh"; then
  printf '\n安装完成。\n'
  printf '现在可以双击桌面的 Nexus.app 启动图形版。\n'
  printf 'API Key、模型和接口地址可直接在应用左下角“设置”中管理。\n'
  exit_code=0
else
  exit_code=$?
  printf '\n安装未完成，错误代码：%s\n' "${exit_code}" >&2
fi

printf '\n按任意键关闭此窗口……'
read -r -n 1
printf '\n'
exit "${exit_code}"

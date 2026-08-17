#!/usr/bin/env bash
# 不依赖 macOS 自动化授权的 Finder 双击启动器。
set -u

script_path="${BASH_SOURCE[0]}"
while [[ -L "${script_path}" ]]; do
  link_dir="$(cd -P -- "$(dirname -- "${script_path}")" && pwd)"
  script_path="$(readlink "${script_path}")"
  if [[ "${script_path}" != /* ]]; then
    script_path="${link_dir}/${script_path}"
  fi
done
script_dir="$(cd -P -- "$(dirname -- "${script_path}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
nexus_bin="${HOME}/.local/bin/nexus"

if [[ ! -x "${nexus_bin}" ]]; then
  printf '未找到 Nexus。请先双击 安装Nexus.command，或在仓库中运行 ./install.sh。\n' >&2
  printf '按任意键关闭此窗口……'
  read -r -n 1
  printf '\n'
  exit 127
fi

clear
if [[ -d "${repo_root}/.git" ]]; then
  cd "${repo_root}" || exit 1
fi
printf 'Nexus 中文版正在启动……\n'
printf '当前项目目录：%s\n\n' "${PWD}"
"${nexus_bin}"
exit_code=$?

if [[ "${exit_code}" -ne 0 ]]; then
  printf '\nNexus 已退出（代码：%s）。按任意键关闭此窗口……' "${exit_code}"
  read -r -n 1
  printf '\n'
fi

exit "${exit_code}"

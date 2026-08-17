#!/usr/bin/env bash
# 从本仓库一键安装 Nexus。
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/scripts/install-nexus" "$@"

dry_run=false
skip_build=false
for argument in "$@"; do
  case "${argument}" in
    --dry-run) dry_run=true ;;
    --skip-build) skip_build=true ;;
  esac
done

if [[ "${dry_run}" == true ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "+ 构建并安装 Nexus.app，在桌面创建 Nexus.app 启动入口"
  fi
  exit 0
fi

if [[ "$(uname -s)" == "Darwin" && "${skip_build}" == false ]]; then
  "${script_dir}/scripts/install-nexus-desktop"
fi

#!/usr/bin/env bash
# 外置盘版 Nexus 的启动器：挂载容器、修复兼容链接并启动桌面 App。
set -euo pipefail

external_image="/Volumes/EAGET-A/AI-DEV.sparsebundle"
external_volume="/Volumes/AI-DEV"
project_root="${external_volume}/Nexus项目"

if [[ ! -d "${project_root}" ]]; then
  /usr/bin/hdiutil attach "${external_image}" -nobrowse >/dev/null
fi

[[ -d "${project_root}" ]] || {
  echo "未找到 EAGET-A 上的 Nexus 项目容器。" >&2
  exit 1
}

ensure_link() {
  local link_path="$1"
  local target_path="$2"
  if [[ -L "${link_path}" ]]; then
    [[ "$(readlink "${link_path}")" == "${target_path}" ]] || {
      echo "已有链接指向其他位置：${link_path}" >&2
      exit 1
    }
    return
  fi
  if [[ -e "${link_path}" ]]; then
    echo "为保护现有文件，未覆盖：${link_path}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${link_path}")"
  ln -s "${target_path}" "${link_path}"
}

ensure_link "${HOME}/Documents/grok Build底座" "${project_root}/源代码/grok Build底座"
ensure_link "${HOME}/.nexus" "${project_root}/数据/.nexus"
ensure_link "${HOME}/.cache/nexus" "${project_root}/缓存/nexus"
ensure_link "${HOME}/Library/Application Support/Nexus" "${project_root}/数据/Library/Application Support/Nexus"

real_app="${project_root}/应用/Nexus.app"
[[ -d "${real_app}" ]] || {
  echo "未找到外置盘中的 Nexus.app。" >&2
  exit 1
}

if [[ "${NEXUS_LAUNCHER_SKIP_OPEN:-0}" == "1" ]]; then
  exit 0
fi

exec /usr/bin/open -n "${real_app}"

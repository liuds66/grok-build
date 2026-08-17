-- Nexus macOS 桌面启动器：以独立终端窗口运行已安装的 Nexus。
on run
  set nexusPath to POSIX path of (path to home folder) & ".local/bin/nexus"
  set shellCommand to "clear; if [ -x " & quoted form of nexusPath & " ]; then exec " & quoted form of nexusPath & "; else echo \"未找到 Nexus。请先运行安装Nexus.command 或 ./install.sh。\"; fi"
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run

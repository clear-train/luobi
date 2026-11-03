#!/bin/bash
# 卸载「Codex 5h 额度唤醒器」
# 用法: bash codex_poke/uninstall.sh [--purge]
set -uo pipefail

BASE="$HOME/Library/Application Support/CodexPoke"
PLIST="$HOME/Library/LaunchAgents/com.liqinkai.codex-poke.plist"
LABEL="com.liqinkai.codex-poke"
UID_N="$(id -u)"

launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
echo ">> 已停止并移除 LaunchAgent."

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$BASE"
  echo ">> 已删除 $BASE (含日志与状态)。Codex 里的那个对话不会被删除。"
else
  echo ">> 状态与日志保留在: $BASE"
fi

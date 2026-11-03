#!/bin/bash
# 安装「Codex 5h 额度唤醒器」——用户级 LaunchAgent, 每 3 分钟检查一次。
# 用法: bash codex_poke/install.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
BASE="$HOME/Library/Application Support/CodexPoke"
LA="$HOME/Library/LaunchAgents"
PLIST="$LA/com.liqinkai.codex-poke.plist"
LABEL="com.liqinkai.codex-poke"
PY="${PYTHON_BIN:-$(command -v python3 || echo /usr/bin/python3)}"
CODEX="${CODEX_BIN:-/opt/homebrew/bin/codex}"
UID_N="$(id -u)"

echo ">> 目标目录: $BASE"
mkdir -p "$BASE/work" "$LA"
cp "$SRC/poke.py" "$BASE/poke.py"

if [ -f "$SRC/thread_id" ] && [ ! -s "$BASE/thread_id" ]; then
  cp "$SRC/thread_id" "$BASE/thread_id"
fi

if [ ! -s "$BASE/thread_id" ]; then
  echo ">> 未发现对话 ID, 正在创建专用对话..."
  ( cd "$BASE/work" && "$CODEX" exec --json --skip-git-repo-check -C "$BASE/work" \
      -s read-only -c approval_policy=never \
      "唤醒：只回复 OK，不要使用任何工具。" < /dev/null \
      > "$BASE/thread_create.jsonl" 2> "$BASE/thread_create.err" ) || true
  TID="$("$PY" - "$BASE/thread_create.jsonl" <<'PYEOF'
import json, sys
tid = ""
for line in open(sys.argv[1], encoding="utf-8"):
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("type") == "thread.started":
        tid = ev.get("thread_id", "")
print(tid)
PYEOF
)"
  if [ -z "$TID" ]; then
    echo "!! 创建对话失败, 见 $BASE/thread_create.err"
    exit 1
  fi
  printf '%s' "$TID" > "$BASE/thread_id"
  printf '%s' "$TID" > "$SRC/thread_id"
  echo ">> 已创建对话: $TID"
fi

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>$BASE/poke.py</string>
  </array>
  <key>WorkingDirectory</key><string>$BASE</string>
  <key>StartInterval</key><integer>180</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$BASE/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$BASE/launchd.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
</dict>
</plist>
PLISTEOF

launchctl bootout "gui/$UID_N/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_N" "$PLIST"
launchctl enable "gui/$UID_N/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$UID_N/$LABEL" 2>/dev/null || true
sleep 2

echo ">> 自检:"
"$PY" "$BASE/poke.py" --selftest
echo ">> 当前状态:"
"$PY" "$BASE/poke.py" --status
echo ">> launchd:"
launchctl print "gui/$UID_N/$LABEL" 2>/dev/null | grep -E 'state =|last exit code|program =|pid =' | head -5 || true
echo ">> 日志:"
tail -6 "$BASE/poke.log" 2>/dev/null || echo "(暂无日志)"
echo ">> 安装完成。日志: $BASE/poke.log"

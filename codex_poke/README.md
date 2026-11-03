# Codex 5h 额度唤醒器

每天 **08:00 / 13:00 / 18:00 / 23:00** 附近，在指定的 Codex 对话里自动发一条极小提示，把 Codex 的
5 小时额度窗口「锚定」到那一刻，保证刷新时间落在你希望的时刻，而不是被你第一次用 Codex 的时间拖走。

## 原理

Codex 的 5 小时额度窗口 **从「窗口空闲后的第一条请求」开始计时**，`重置时间 = 该请求时刻 + 5h`，
窗口一旦锚定，重置时间固定（可用 CodexMeter 的本地采样库验证）。

所以真正的「刷新」只需要一条请求，不需要生成内容：

- 窗口空闲时唤醒 → 窗口锚定在 08:00 → 13:00 整点刷新 → 再锚定 → 18:00 …… 
- 00:00–08:00 静默，避免夜里把第二天算成 09/14 点的错位节奏。

## 它怎么工作

`LaunchAgent`（用户级，登录自启）每 **3 分钟**执行一次 `poke.py`：

1. 从 `~/Library/Application Support/CodexMeter/UsageHistory.sqlite` 读 5h 窗口状态；
2. 判定是否「窗口空闲」= 剩余 100% 且重置时间随采样滚动（已锚定的窗口重置时间固定，差值会递减）；
3. 空闲 + 非静默时段 → 用 `codex exec resume <对话ID> "唤醒：只回复 OK…"`
   发一条极小请求（默认 `gpt-6-luna` + low 推理，最省钱；同属账号级 5h 额度桶）；
4. 不满足条件只写一行日志，不发请求。

安全阀：

- 失败 10 分钟后重试；成功后 15 分钟内不重复；
- 每天最多 8 次；
- 单实例锁（不会并发重复唤醒）；
- 唤醒后自动校验「窗口是否真的锚定」：若采样显示窗口仍空闲，自动把模型换回 `gpt-6.1-sol` 兜底。

## 文件

| 路径 | 说明 |
| --- | --- |
| `~/Library/LaunchAgents/com.liqinkai.codex-poke.plist` | LaunchAgent 定义 |
| `~/Library/Application Support/CodexPoke/poke.py` | 运行时脚本（由本目录 `poke.py` 复制） |
| `~/Library/Application Support/CodexPoke/thread_id` | 目标对话 UUID |
| `~/Library/Application Support/CodexPoke/state.json` | 状态（上次唤醒时间、当日次数、模型） |
| `~/Library/Application Support/CodexPoke/poke.log` | 运行日志（超过 1MB 自动轮转） |
| `codex_poke/quota_probe.py` | 直读 Codex 官方 5h/每周额度快照的探针（不依赖 CodexMeter） |

当前目标对话：`唤醒：只回复 OK，不要使用任何工具。`
（`01a163b7-004c-7d71-a8f9-111fbbdb121c`，位于 `~/Library/Application Support/CodexPoke/work`）

## 常用命令

```bash
BASE="$HOME/Library/Application Support/CodexPoke"

# 看状态（窗口空闲/锚定、下次该不该唤醒、当前模型）
/usr/bin/python3 "$BASE/poke.py" --status

# 直读官方额度快照（无需 CodexMeter，独立校验锚定结果）
/usr/bin/python3 codex_poke/quota_probe.py

# 立刻强制唤醒一次（测试用，会消耗一条消息额度）
/usr/bin/python3 "$BASE/poke.py" --force

# 看日志
tail -30 "$BASE/poke.log"

# 卸载（--purge 连状态和日志一起删）
bash codex_poke/uninstall.sh
```

## 修改

- **换对话**：把新对话 UUID 写进 `~/Library/Application Support/CodexPoke/thread_id` 和本目录 `thread_id`。
- **换模型**：改 `poke.py` 里的 `DEFAULT_MODEL` / `FALLBACK_MODEL`，重新执行 `install.sh`。
- **改静默时段/节奏**：改 `poke.py` 里的 `QUIET_FROM` / `QUIET_TO`（当前 00:00–08:00），重新执行 `install.sh`。
  唤醒间隔由「5h 窗口 + 2 分钟余量」决定，固定 5 小时。
- **重装**：`bash codex_poke/install.sh`（会自动重启 LaunchAgent）。

## 前提与限制

- 依赖 **CodexMeter** 在跑（它每分钟采样一次额度）。若 CodexMeter 不在，脚本退化为纯计时：
  上次唤醒 + 5h + 2min 后唤醒一次，仍然可用，只是可能多走一次空唤醒。
- Mac 必须处于唤醒/登录状态才会执行；睡眠期间错过的唤醒，会在唤醒后由 launchd 立即补跑一次
  （因此开机/醒来后窗口会重新锚定）。
- 若你在窗口刷新后自己先用 Codex，窗口会被你的使用锚定，脚本检测到「窗口已活跃」就不会再发，
  不会浪费额度。
- LaunchAgent 登录自启；彻底停用请用 `uninstall.sh`。

## 已验证

- 2026-10-27 20:02:53 首次自动唤醒：`gpt-6-luna`，12.9s，输出 10 tokens；
  官方 `account/rateLimits/read` 显示 5h 窗口重置时间为 2026-10-28 01:02:50（= 唤醒时刻 + 5h），锚定成功。
- 同一份快照显示 luna 的小请求在该窗口只占 0%（四舍五入），即唤醒本身几乎不吃额度。

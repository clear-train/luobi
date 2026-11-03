#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Codex 5h 额度窗口锚定器.

背景
----
Codex 的 5 小时额度窗口从「窗口空闲后的第一条请求」开始计时,
重置时间 = 该请求时刻 + 5 小时; 窗口一旦锚定, 重置时间固定。
所以只要在窗口空闲时发一条极小请求, 就能把刷新节奏钉在 08:00 / 13:00 / 18:00 / 23:00。

行为
----
每 3 分钟由 LaunchAgent 唤醒一次:
  1. 从 CodexMeter 的本地采样库读 5 小时窗口状态(数据过期则退化为纯计时);
  2. 若窗口已空闲(100% 且重置时间随采样滚动), 且当前不在 04:00-08:00 静默时段,
     就向指定 Codex 对话 resume 一条极小提示("唤醒：只回复 OK"), 把窗口锚到此刻;
  3. 其余情况只写一行日志, 不发请求。

省钱: 默认用最便宜的 gpt-6-luna + low 推理(同属账号级 5h 额度桶),
并用 gpt-6.1-sol 作兜底 —— 若唤醒后采样显示窗口仍空闲(说明没锚住), 自动换回 sol。
安全阀: 失败 10 分钟后重试; 成功 15 分钟内不重复; 每天最多 8 次; 单实例锁。
"""
import datetime
import fcntl
import json
import os
import sqlite3
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
BASE = os.path.join(HOME, "Library", "Application Support", "CodexPoke")
WORK = os.path.join(BASE, "work")
THREAD_FILE = os.path.join(BASE, "thread_id")
STATE_FILE = os.path.join(BASE, "state.json")
LOG_FILE = os.path.join(BASE, "poke.log")
LOCK_FILE = os.path.join(BASE, "poke.lock")
METER_DB = os.path.join(HOME, "Library", "Application Support", "CodexMeter", "UsageHistory.sqlite")
CODEX_BIN = "/opt/homebrew/bin/codex"

PROMPT = "唤醒：只回复 OK，不要使用任何工具。"
DEFAULT_MODEL = "gpt-6-luna"          # 最便宜, 用来锚定窗口
FALLBACK_MODEL = "gpt-6.1-sol"        # 兜底: 若 luna 没锚住 5h 窗口则自动换回
QUIET_FROM, QUIET_TO = 0, 8          # 00:00-08:00 不唤醒, 让 08:00 成为每天唯一的夜间后锚点
WINDOW_SEC = 5 * 3600
SLACK_SEC = 120                        # 窗口过期后再等 2 分钟才唤醒, 避开边界竞态
RETRY_BACKOFF = 600                    # 失败后 10 分钟再试
MIN_GAP = 900                          # 成功唤醒后 15 分钟内不重复
MAX_POKES_PER_DAY = 8                  # 安全阀
QUOTA_FRESH_SEC = 1800                 # 采样超过 30 分钟视为不可用
TIMEOUT = 240


SILENT = False                        # 自检时静音, 不污染正式日志


def now_str(ts=None):
    return datetime.datetime.fromtimestamp(
        ts if ts is not None else time.time()).strftime("%Y-%m-%d %H:%M:%S")


def log(msg):
    if SILENT:
        return
    try:
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 1_000_000:
            os.replace(LOG_FILE, LOG_FILE + ".1")
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write("[%s] %s\n" % (now_str(), msg))
    except Exception:
        pass


def load_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(st):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)
    os.replace(tmp, STATE_FILE)


def read_thread():
    try:
        with open(THREAD_FILE, encoding="utf-8") as f:
            return f.read().strip()
    except Exception:
        return ""


def quota():
    """从 CodexMeter 采样库读 5 小时窗口; 不可用/过期返回 None。"""
    if not os.path.exists(METER_DB):
        return None
    try:
        con = sqlite3.connect("file:" + METER_DB + "?mode=ro", uri=True, timeout=3)
        row = con.execute(
            "select sampled_at, remaining_percent, resets_at from quota_samples "
            "where window_duration_mins=300 order by sampled_at desc limit 1").fetchone()
        con.close()
    except Exception as e:
        log("quota read error: %s" % e)
        return None
    if not row:
        return None
    sampled_at, pct, resets_at = row
    if resets_at is None or time.time() - (sampled_at or 0) > QUOTA_FRESH_SEC:
        return None
    # 空闲窗口: 重置时间跟着采样时间滚动(重置时间-采样时间 ≈ 5h);
    # 已锚定窗口: 重置时间固定, 差值随时间递减。
    idle = (resets_at - sampled_at) >= (WINDOW_SEC - 90)
    return {"idle": idle, "pct": pct, "resets_at": resets_at,
            "sampled_at": sampled_at, "age": time.time() - sampled_at}


def decide(now, st, q, force=False):
    """返回 (是否该唤醒, 原因)。"""
    lt = datetime.datetime.fromtimestamp(now)
    if force:
        return True, "forced"
    if QUIET_FROM <= lt.hour < QUIET_TO:
        return False, "quiet hours %s" % lt.strftime("%H:%M")
    day = lt.strftime("%Y-%m-%d")
    if st.get("day") == day and int(st.get("day_pokes") or 0) >= MAX_POKES_PER_DAY:
        return False, "daily cap reached"
    last_poke = float(st.get("last_poke_at") or 0)
    last_attempt = float(st.get("last_attempt_at") or 0)
    if last_attempt and now - last_attempt < RETRY_BACKOFF:
        return False, "retry backoff"
    if last_poke and now - last_poke < MIN_GAP:
        return False, "min gap"
    if q is not None:
        if q["idle"]:
            return True, "window idle (pct=%s)" % q["pct"]
        return False, "window active, resets %s (pct=%s)" % (
            now_str(q["resets_at"]), q["pct"])
    due = last_poke + WINDOW_SEC + SLACK_SEC if last_poke else 0
    if now >= due:
        return True, "time-based due (quota unavailable)"
    return False, "time-based due %s (quota unavailable)" % now_str(due)


def poke(thread, model):
    """在指定对话里 resume 一条极小提示; 成功返回 True。"""
    # 注意: codex exec resume 子命令不支持 -C/-s, 工作目录靠 subprocess cwd,
    # 沙箱与审批策略走 -c 覆盖。
    common = ["--skip-git-repo-check", "--json",
              "-c", 'approval_policy="never"', "-c", 'sandbox_mode="read-only"']
    variants = [
        ["--ignore-user-config", "-m", model, "-c", 'model_reasoning_effort="low"'] + common,
        ["--ignore-user-config", "-m", model] + common,
        ["-m", model, "-c", 'model_reasoning_effort="low"'] + common,
        ["-m", model] + common,
        common,
    ]
    env = dict(os.environ)
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    for i, extra in enumerate(variants, 1):
        cmd = [CODEX_BIN, "exec", "resume", thread, PROMPT] + extra
        t0 = time.time()
        try:
            r = subprocess.run(cmd, cwd=WORK, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=TIMEOUT, env=env)
        except subprocess.TimeoutExpired:
            log("poke variant%d timeout after %ss" % (i, TIMEOUT))
            continue
        except Exception as e:
            log("poke variant%d exec error: %s" % (i, e))
            continue
        if r.returncode == 0:
            usage = ""
            for line in r.stdout.splitlines():
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                if ev.get("type") == "turn.completed":
                    u = ev.get("usage") or {}
                    usage = "in=%s cached=%s out=%s" % (
                        u.get("input_tokens"), u.get("cached_input_tokens"),
                        u.get("output_tokens"))
            log("POKE OK variant%d model=%s %.1fs %s" % (i, model, time.time() - t0, usage))
            return True
        lines = [l.strip() for l in (r.stderr or "").strip().splitlines()
                 if l.strip() and "rmcp::transport" not in l]
        if not lines:                       # 有些错误只出现在 --json 事件流里
            for line in (r.stdout or "").splitlines():
                try:
                    ev = json.loads(line)
                except Exception:
                    if line.strip():
                        lines.append(line.strip())
                    continue
                if ev.get("type") in ("error", "turn.failed"):
                    msg = ev.get("message") or ev.get("error") or ev
                    lines.append(json.dumps(msg, ensure_ascii=False)[:300])
                    break
                item = ev.get("item") or {}
                if item.get("type") == "error":
                    lines.append(str(item.get("message") or item)[:300])
                    break
        brief = " | ".join(lines[:2])[:400] or "(无错误输出)"
        log("poke variant%d failed rc=%s %s" % (i, r.returncode, brief))
    return False


def check_expectation(st, q):
    """事后校验: 上一次唤醒后, 5h 窗口是否真的按预期锚定了。

    采样显示窗口仍空闲 -> 这次唤醒没锚住(例如模型属于别的额度桶) -> 自动换兜底模型。
    采样显示窗口已锚定但重置时间偏差 >15 分钟 -> 同样换兜底模型。
    """
    expect = st.get("expect_resets_at")
    if not expect or q is None:
        return st
    last_poke = float(st.get("last_poke_at") or 0)
    if q["sampled_at"] <= last_poke:
        return st                      # 采样还早于唤醒时刻, 等下次
    used = st.get("model") or DEFAULT_MODEL
    if q["idle"]:
        log("WARN 未锚定: 唤醒后窗口仍空闲 (模型 %s) -> 换回 %s" % (used, FALLBACK_MODEL))
        st["model"] = FALLBACK_MODEL
    else:
        drift = abs(q["resets_at"] - float(expect))
        if drift > 900:
            log("WARN 锚定校验: 期望重置 %s, 实际 %s (偏差 %d 分钟, 模型 %s) -> 换回 %s" % (
                now_str(expect), now_str(q["resets_at"]), int(drift / 60), used, FALLBACK_MODEL))
            st["model"] = FALLBACK_MODEL
        else:
            log("锚定校验通过: 重置时间 %s (模型 %s)" % (now_str(q["resets_at"]), used))
    st.pop("expect_resets_at", None)
    return st


def selftest():
    global SILENT
    SILENT = True

    def ts(H, M=0):
        return datetime.datetime(2026, 10, 23, H, M).timestamp()

    def idle(t):
        return {"idle": True, "pct": 100, "resets_at": t + WINDOW_SEC, "sampled_at": t}

    def active(t):
        return {"idle": False, "pct": 60, "resets_at": t + 9000, "sampled_at": t}

    t9, t5 = ts(9), ts(5)
    cases = [
        ("空闲+白天 -> 唤醒", decide(t9, {"last_poke_at": t9 - 5 * 3600}, idle(t9))[0], True),
        ("窗口活跃 -> 不唤醒", decide(t9, {}, active(t9))[0], False),
        ("静默时段 -> 不唤醒", decide(t5, {"last_poke_at": t9 - 12 * 3600}, idle(t5))[0], False),
        ("失败退避 -> 不唤醒", decide(t9, {"last_attempt_at": t9 - 60}, idle(t9))[0], False),
        ("最小间隔 -> 不唤醒", decide(t9, {"last_poke_at": t9 - 3600}, None)[0], False),
        ("纯计时到期 -> 唤醒", decide(t9, {"last_poke_at": t9 - 5 * 3600 - 200}, None)[0], True),
        ("强制 -> 唤醒", decide(t5, {"last_poke_at": t9 - 12 * 3600}, active(t5), force=True)[0], True),
        ("每日上限 -> 不唤醒",
         decide(t9, {"day": "2026-10-23", "day_pokes": MAX_POKES_PER_DAY}, idle(t9))[0], False),
    ]
    for name, got, want in cases:
        assert got is want, "自检失败: %s (got=%r want=%r)" % (name, got, want)

    # 锚定校验: 正常锚定保持 luna; 唤醒后仍空闲则自动换兜底模型
    base = {"expect_resets_at": t9 + WINDOW_SEC, "last_poke_at": t9, "model": DEFAULT_MODEL}
    q_ok = {"idle": False, "pct": 99, "resets_at": t9 + WINDOW_SEC, "sampled_at": t9 + 60}
    q_idle = {"idle": True, "pct": 100, "resets_at": t9 + 60 + WINDOW_SEC, "sampled_at": t9 + 60}
    assert check_expectation(dict(base), q_ok).get("model") == DEFAULT_MODEL, "锚定通过时不该换模型"
    assert check_expectation(dict(base), q_idle).get("model") == FALLBACK_MODEL, "未锚定时应换兜底模型"
    print("SELFTEST OK (%d 决策用例 + 2 锚定校验用例)" % len(cases))


def main():
    force = "--force" in sys.argv
    status_only = "--status" in sys.argv
    if "--selftest" in sys.argv:
        selftest()
        return
    lf = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("skip: another instance running")
        return
    thread = read_thread()
    st = load_state()
    now = time.time()
    q = quota()
    st = check_expectation(st, q)
    if status_only:
        print(json.dumps({"now": now_str(now), "thread": thread, "state": st,
                          "model": st.get("model") or DEFAULT_MODEL,
                          "quota": q, "quiet": QUIET_FROM <= datetime.datetime.fromtimestamp(now).hour < QUIET_TO,
                          "codex_bin": os.path.exists(CODEX_BIN)}, ensure_ascii=False, indent=2))
        return
    if not os.path.exists(CODEX_BIN):
        log("codex not found: %s" % CODEX_BIN)
        return
    if not thread:
        log("no thread id in %s" % THREAD_FILE)
        return
    day = datetime.datetime.fromtimestamp(now).strftime("%Y-%m-%d")
    if st.get("day") != day:
        st["day"] = day
        st["day_pokes"] = 0
    go, why = decide(now, st, q, force)
    if not go:
        log("skip: %s" % why)
        save_state(st)
        return
    model = st.get("model") or DEFAULT_MODEL
    log("due: %s | 模型 %s" % (why, model))
    ok = poke(thread, model)
    if ok:
        st["last_poke_at"] = now
        st["last_attempt_at"] = 0
        st["pokes"] = int(st.get("pokes") or 0) + 1
        st["day_pokes"] = int(st.get("day_pokes") or 0) + 1
        st["expect_resets_at"] = now + WINDOW_SEC
    else:
        st["last_attempt_at"] = now
        st["failures"] = int(st.get("failures") or 0) + 1
    st["updated_at"] = now
    save_state(st)


if __name__ == "__main__":
    main()

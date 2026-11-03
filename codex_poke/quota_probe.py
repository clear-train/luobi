#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""直接通过 Codex app-server 的 JSON-RPC 读取 5h 额度快照（不依赖 CodexMeter）。

用法: python3 quota_probe.py
输出: 200 字符以内的关键字段 + 完整 JSON。
"""
import json
import os
import select
import subprocess
import sys
import time

CODEX = "/opt/homebrew/bin/codex"


def main():
    env = dict(os.environ)
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    proc = subprocess.Popen(
        [CODEX, "app-server", "--listen", "stdio://"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1, env=env)
    pending_notifications = []

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    def recv_until(id_, timeout=25):
        end = time.time() + timeout
        while time.time() < end:
            left = end - time.time()
            r, _, _ = select.select([proc.stdout], [], [], max(0.0, left))
            if not r:
                break
            line = proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
            except Exception:
                continue
            if msg.get("id") == id_:
                return msg
            if "id" not in msg:
                pending_notifications.append(msg)
        return None

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"clientInfo": {"name": "quota-probe", "version": "0.1.0"}}})
        init = recv_until(1)
        if init is None:
            print("initialize 无响应; stderr:", (proc.stderr.read() or "")[:500])
            return 1
        send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        # 优先 v2 方法名; 失败再退回 app-server 旧名
        for method in ("account/rateLimits/read", "account/rateLimits/read",
                       "account/usage/read"):
            send({"jsonrpc": "2.0", "id": 2, "method": method,
                  "params": {"supportsLunaReserve": True,
                             "excludeResetCreditDetails": False}})
            resp = recv_until(2)
            if resp is not None:
                break
        if resp is None:
            print("rateLimits 无响应")
            return 1
        if "error" in resp:
            print("RPC 错误:", json.dumps(resp["error"], ensure_ascii=False)[:500])
            return 1
        result = resp.get("result") or {}
        rl = result.get("rateLimits") or {}
        now = time.time()
        summary = {}
        for name in ("primary", "secondary"):
            w = rl.get(name) or {}
            if w:
                resets = w.get("resetsAt")
                summary[name] = {
                    "usedPercent": w.get("usedPercent"),
                    "windowDurationMins": w.get("windowDurationMins"),
                    "resetsAt": resets,
                    "resetsAt_local": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(resets)) if resets else None,
                    "minutes_to_reset": round((resets - now) / 60, 1) if resets else None,
                }
        print("NOW", time.strftime("%Y-%m-%d %H:%M:%S"))
        print("SUMMARY", json.dumps(summary, ensure_ascii=False))
        print("RAW", json.dumps(result, ensure_ascii=False)[:1500])
        return 0
    finally:
        try:
            proc.kill()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())

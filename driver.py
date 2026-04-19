#!/usr/bin/env python3
"""
tm-agent driver: send commands to the plugin via its JSON file IPC.

Usage examples:
    ./driver.py ping
    ./driver.py state
    ./driver.py input "What blocks are on the map?"
    ./driver.py append " And items too."
    ./driver.py send
    ./driver.py new
    ./driver.py settings open    # or close / toggle
    ./driver.py window show      # or hide
    ./driver.py compact
    ./driver.py seed             # seed demo conversation
    ./driver.py msg user "hello"
    ./driver.py msg assistant "hi there"
    ./driver.py raw '{"op":"ping"}'
"""
import json
import os
import sys
import time
from pathlib import Path

STORAGE = Path.home() / "OpenplanetNext" / "PluginStorage" / "tm-agent"
CMD = STORAGE / "driver_cmd.json"
RESP = STORAGE / "driver_resp.json"

POLL_INTERVAL_S = 0.05
TIMEOUT_S = 3.0


def send(op_dict: dict) -> dict:
    if RESP.exists():
        RESP.unlink()
    CMD.write_text(json.dumps(op_dict))
    deadline = time.monotonic() + TIMEOUT_S
    while time.monotonic() < deadline:
        if RESP.exists() and not CMD.exists():
            try:
                return json.loads(RESP.read_text())
            except json.JSONDecodeError:
                pass
        time.sleep(POLL_INTERVAL_S)
    raise TimeoutError(f"no response after {TIMEOUT_S}s (plugin running? in editor?)")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    cmd = sys.argv[1]
    rest = sys.argv[2:]

    if cmd == "ping":
        op = {"op": "ping"}
    elif cmd == "state":
        op = {"op": "get_state"}
    elif cmd == "input":
        op = {"op": "set_input", "text": " ".join(rest)}
    elif cmd == "append":
        op = {"op": "append_input", "text": " ".join(rest)}
    elif cmd == "send":
        op = {"op": "send"}
    elif cmd == "new":
        op = {"op": "new"}
    elif cmd == "settings":
        mode = rest[0] if rest else "toggle"
        op = {"op": f"{mode}_settings"}
    elif cmd == "window":
        op = {"op": "show_window", "value": rest[0] == "show" if rest else True}
    elif cmd == "compact":
        op = {"op": "compact"}
    elif cmd == "windows":
        op = {"op": "get_windows"}
    elif cmd == "test":
        op = {"op": "test_provider"}
    elif cmd == "test_result":
        op = {"op": "get_test"}
    elif cmd == "seed":
        op = {"op": "seed_demo"}
    elif cmd == "msg":
        if len(rest) < 2:
            print("msg requires: role text", file=sys.stderr)
            return 2
        op = {"op": "add_message", "role": rest[0], "text": " ".join(rest[1:])}
    elif cmd == "status":
        if not rest:
            print("status requires a value", file=sys.stderr)
            return 2
        op = {"op": "set_status", "status": " ".join(rest)}
    elif cmd == "raw":
        op = json.loads(rest[0])
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 1

    try:
        resp = send(op)
    except TimeoutError as e:
        print(f"error: {e}", file=sys.stderr)
        return 3

    print(json.dumps(resp, indent=2))
    return 0 if resp.get("ok") else 4


if __name__ == "__main__":
    sys.exit(main())

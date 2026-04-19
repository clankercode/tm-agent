#!/usr/bin/env python3
"""
Capture the TM Agent UI — auto-cropped to the agent window (and the settings
window when it's open) using live dims queried from the plugin.

Outputs:
  /tmp/tm_agent_ui.png            full TM window
  /tmp/tm_agent_ui_crop.png       agent window, tight crop
  /tmp/tm_agent_ui_settings.png   settings window (only if visible)
"""
import subprocess
import sys
from pathlib import Path

from driver import send

OUT_FULL = Path("/tmp/tm_agent_ui.png")
OUT_AGENT = Path("/tmp/tm_agent_ui_crop.png")
OUT_SETTINGS = Path("/tmp/tm_agent_ui_settings.png")
PAD = 10


def find_tm_window() -> str:
    result = subprocess.run(
        ["xdotool", "search", "--name", "Trackmania"],
        capture_output=True, text=True, check=False,
    )
    for wid in result.stdout.strip().splitlines():
        name = subprocess.run(
            ["xdotool", "getwindowname", wid],
            capture_output=True, text=True, check=False,
        ).stdout.strip()
        if name == "Trackmania":
            return wid
    raise RuntimeError("Trackmania window not found")


def crop(src: Path, dst: Path, x: int, y: int, w: int, h: int) -> None:
    subprocess.run(
        ["magick", str(src), "-crop", f"{w}x{h}+{x}+{y}", "+repage", str(dst)],
        check=True,
    )


def main() -> int:
    try:
        wid = find_tm_window()
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    # Raise TM so no other OS window is sitting on top of our capture.
    subprocess.run(["xdotool", "windowactivate", "--sync", wid], check=False)

    subprocess.run(["import", "-window", wid, str(OUT_FULL)], check=True)

    try:
        resp = send({"op": "get_windows"})
    except TimeoutError:
        # Plugin not reachable — fall back to a static crop so the pipeline
        # still yields something.
        print("WARN: driver unreachable; using static fallback crop", file=sys.stderr)
        crop(OUT_FULL, OUT_AGENT, 110, 110, 460, 640)
        OUT_SETTINGS.unlink(missing_ok=True)
        print(f"PATH={OUT_FULL}")
        print(f"CROP={OUT_AGENT}")
        return 0

    agent = resp["agent"]
    ax, ay = agent["pos"]
    aw, ah = agent["size"]
    crop(OUT_FULL, OUT_AGENT, ax - PAD, ay - PAD, aw + PAD * 2, ah + PAD * 2)

    OUT_SETTINGS.unlink(missing_ok=True)
    settings = resp["settings"]
    if settings["visible"] and settings["size"][0] > 0:
        sx, sy = settings["pos"]
        sw, sh = settings["size"]
        crop(OUT_FULL, OUT_SETTINGS, sx - PAD, sy - PAD, sw + PAD * 2, sh + PAD * 2)
        print(f"SETTINGS={OUT_SETTINGS}")

    print(f"PATH={OUT_FULL}")
    print(f"CROP={OUT_AGENT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

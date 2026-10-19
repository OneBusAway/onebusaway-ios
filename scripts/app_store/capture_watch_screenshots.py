#!/usr/bin/env python3
"""Capture the Apple Watch App Store screenshots from a booted watch simulator.

The watch has no UI test target, so this drives the installed app directly:
for each slide in docs/app-store/watch-screenshots.json it relaunches the app
with that slide's DEBUG launch environment (OBAKitWatch/ScreenshotHooks.swift),
waits for live data to load, and saves a screenshot. A watch screenshot is
uploaded as is, at the simulator's screen size, so these are the final slides.

Usage: capture_watch_screenshots.py <udid> <bundle id> <output dir> [--only NAME]
"""

import argparse
import json
import os
import pathlib
import subprocess
import time

REPO = pathlib.Path(__file__).resolve().parents[2]
CONFIG = REPO / "docs" / "app-store" / "watch-screenshots.json"
SETTLE = 15     # seconds for a location fix, the API calls and the push to land


def simctl(*args, env=None):
    subprocess.run(["xcrun", "simctl", *args], check=True, env=env)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("udid")
    parser.add_argument("bundle_id")
    parser.add_argument("output_dir", type=pathlib.Path)
    parser.add_argument("--only")
    args = parser.parse_args()

    config = json.loads(CONFIG.read_text())
    args.output_dir.mkdir(parents=True, exist_ok=True)
    latitude, longitude = config["location"]
    simctl("location", args.udid, "set", f"{latitude},{longitude}")

    slides = [s for s in config["slides"] if not args.only or s["name"] == args.only]
    if not slides:
        raise SystemExit(f"error: no watch slide named {args.only}")
    for slide in slides:
        env = dict(os.environ)
        # simctl passes SIMCTL_CHILD_-prefixed variables to the app, unprefixed.
        for key, value in slide["env"].items():
            env[f"SIMCTL_CHILD_{key}"] = value
        if slide.get("bookmarks"):
            env["SIMCTL_CHILD_TEST_SCREENSHOT_BOOKMARKS"] = json.dumps(config["bookmarks"])
        simctl("launch", "--terminate-running-process", args.udid, args.bundle_id, env=env)
        time.sleep(SETTLE)
        target = args.output_dir / f"{slide['name']}.png"
        simctl("io", args.udid, "screenshot", str(target))
        print(target)


if __name__ == "__main__":
    main()

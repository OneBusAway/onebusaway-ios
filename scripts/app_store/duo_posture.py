#!/usr/bin/env python3
"""Wait until an iPhone Duo simulator is in the given posture: open or folded.

Nothing scriptable folds or unfolds the simulator: simctl and XCUITest have no
posture API, and Device Hub's posture buttons aren't exposed to Accessibility.
So this asks, then waits. It tells the postures apart by the inner display,
which is lit when the device is open and black when it's folded.

Usage: duo_posture.py <udid> open|folded
       duo_posture.py <udid> current      prints "open" or "folded"
"""

import pathlib
import re
import subprocess
import sys
import tempfile
import time

from PIL import Image, ImageStat

TIMEOUT = 600   # seconds to wait for the click
LIT = 3         # mean brightness (0-255) above which a display is on

BUTTON = {
    "open": "the rightmost one (flat)",
    "folded": "the one just right of the divider (folded)",
}


def inner_display(udid):
    """The port UUID of the largest integrated display: the inner screen."""
    output = subprocess.run(["xcrun", "simctl", "io", udid, "enumerate"],
                            check=True, capture_output=True, text=True).stdout
    best = None
    for port in output.split("Port:")[1:]:
        uuid = re.search(r"UUID: (\S+)", port)
        width = re.search(r"Default width: (\d+)", port)
        if uuid and width and "Display class: 0" in port:
            if best is None or int(width.group(1)) > best[1]:
                best = (uuid.group(1), int(width.group(1)))
    if best is None:
        sys.exit(f"error: simulator {udid} reports no displays; is it booted?")
    return best[0]


def is_open(udid, display):
    with tempfile.TemporaryDirectory() as tmp:
        shot = pathlib.Path(tmp) / "inner.png"
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", f"--display={display}", str(shot)],
                       check=True, capture_output=True)
        thumbnail = Image.open(shot).convert("L").resize((64, 64))
        return ImageStat.Stat(thumbnail).mean[0] > LIT


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in (*BUTTON, "current"):
        sys.exit(__doc__)
    udid, posture = sys.argv[1], sys.argv[2]
    display = inner_display(udid)
    if posture == "current":
        print("open" if is_open(udid, display) else "folded")
        return

    want_open = posture == "open"
    if is_open(udid, display) == want_open:
        return
    print(f"\a\n>>> Put the iPhone Duo {posture}: in Device Hub, click {BUTTON[posture]} of the "
          f"posture buttons under the device. Waiting...", file=sys.stderr, flush=True)
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        time.sleep(3)
        if is_open(udid, display) == want_open:
            # Let the display transition and the app's relayout finish.
            time.sleep(5)
            print(f">>> iPhone Duo is {posture}.", file=sys.stderr)
            return
    sys.exit(f"error: the iPhone Duo never became {posture}")


if __name__ == "__main__":
    main()

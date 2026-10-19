#!/usr/bin/env python3
"""Export the screenshot attachments from an .xcresult bundle as named PNGs.

AppStoreScreenshotUITests attaches one capture per slide with
`XCTAttachment.name` set to the slide's capture name (`01-stop-arrivals`, ...).
xcresulttool exports attachments under opaque names plus a manifest; this maps
them back.

Usage: export_screenshots.py <bundle.xcresult> <output dir>
"""

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    bundle, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", tmp],
            check=True,
        )
        manifest = json.loads((pathlib.Path(tmp) / "manifest.json").read_text())
        exported = 0
        for test in manifest:
            for attachment in test.get("attachments", []):
                name = attachment.get("suggestedHumanReadableName") or ""
                source = pathlib.Path(tmp) / attachment["exportedFileName"]
                # Only our slides, which start with their two-digit number;
                # XCTest also attaches its own failure captures.
                if not source.exists() or not re.match(r"\d\d-", name):
                    continue
                # xcresulttool suffixes the attachment name with its index and
                # a UUID ("01-stop-arrivals_0_<uuid>.png"); keep our name.
                stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", pathlib.Path(name).stem)
                target = out_dir / f"{stem}{source.suffix or '.png'}"
                shutil.copyfile(source, target)
                exported += 1
                print(target)
    print(f"exported {exported} screenshot(s) to {out_dir}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compose the iPhone Duo App Store slides: caption on top, Duo(s) below.

Reads the slide list from docs/app-store/duo-screenshots.json. Each slide
names one or more raw captures from `<raw dir>`; a capture ending in
`-folded` is the cover screen and is drawn as the folded Duo, any other as the
open Duo. frames-cli has no Duo frame, so this draws the device itself around
the capture, with the screen corner radii from the simulator's device profile.

Usage: compose_duo_screenshots.py <raw dir> <output dir> [--size WxH]

--size defaults to 2853x2007, the open Duo's landscape size. The App Store also
takes 2034x1398 (and either one portrait); the layout scales with the canvas.
"""

import argparse
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageOps

from compose_screenshots import draw_caption

REPO = pathlib.Path(__file__).resolve().parents[2]
CONFIG = REPO / "docs" / "app-store" / "duo-screenshots.json"

# Screen corner radii in pixels, from the iPhone Duo device profile
# (capabilities.plist: points, at 3x), running top-left, top-right,
# bottom-right, bottom-left. The cover screen's hinge is on its left.
OPEN_RADII = (165, 165, 165, 165)
COVER_RADII = (24, 177, 177, 24)

BEZEL = 62          # black border around the screen
RIM = 16            # metal band around the bezel
SPINE = 30          # the folded Duo's hinge, showing past its left edge
BUMP = 9            # how far buttons and hinge tabs stand proud
METAL = (58, 58, 62)
METAL_LIGHT = (112, 112, 118)
GLASS = (6, 6, 7)

CAPTION_SIZE = 0.075    # caption font size / canvas height
SUBTITLE_SIZE = 0.042   # subtitle font size / canvas height
SIDE_MARGIN = 0.05      # minimum caption inset / canvas width
DEVICE_TOP = 0.215      # device top / canvas height
OPEN_WIDTH = 0.84       # a lone open Duo's width / canvas width
DEVICE_HEIGHT = 0.74    # folded Duos' height / canvas height
GAP = 0.05              # space between devices / canvas width
MAX_ROW = 0.94          # widest a row of devices may be / canvas width
SUPERSAMPLE = 2         # masks are drawn this much larger, for smooth edges


def rounded_mask(size, radii):
    """An antialiased mask of a rectangle with a different radius per corner."""
    width, height = (v * SUPERSAMPLE for v in size)
    mask = Image.new("L", (width, height), 255)
    draw = ImageDraw.Draw(mask)
    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]    # top-left, clockwise
    for (right, bottom), radius in zip(corners, radii):
        r = radius * SUPERSAMPLE
        if r <= 0:
            continue
        x = width - r if right else 0
        y = height - r if bottom else 0
        draw.rectangle((x, y, x + r - 1, y + r - 1), fill=0)
        cx = x if right else x + r
        cy = y if bottom else y + r
        draw.ellipse((cx - r, cy - r, cx + r - 1, cy + r - 1), fill=255)
    return mask.resize(size, Image.LANCZOS)


def grown(radii, by):
    return tuple(r + by for r in radii)


def draw_device(capture, folded):
    """The capture in a Duo body, on a transparent image with room for bumps."""
    # The exported PNGs carry an EXIF rotation; the open Duo's is landscape.
    screen = ImageOps.exif_transpose(Image.open(capture)).convert("RGB")
    screen_size = screen.size
    screen_radii = COVER_RADII if folded else OPEN_RADII
    border = BEZEL + RIM
    body_radii = grown(screen_radii, border)
    body_size = (screen_size[0] + 2 * border, screen_size[1] + 2 * border)
    left_pad = SPINE if folded else BUMP
    device = Image.new("RGBA", (body_size[0] + left_pad + BUMP, body_size[1] + 2 * BUMP), (0, 0, 0, 0))
    draw = ImageDraw.Draw(device)
    ox, oy = left_pad, BUMP     # body origin
    bw, bh = body_size

    # Buttons on the top edge, toward the right, as on the hardware.
    for start in (0.70, 0.80):
        x = ox + round(bw * start)
        draw.rounded_rectangle((x, oy - BUMP, x + round(bw * 0.075), oy + RIM), radius=BUMP, fill=METAL_LIGHT)

    if folded:
        # The hinge spine runs down the left side, behind the body.
        draw.rounded_rectangle((0, oy + 40, ox + 60, oy + bh - 40), radius=SPINE, fill=METAL_LIGHT)
        draw.rounded_rectangle((8, oy + 52, ox + 60, oy + bh - 52), radius=SPINE, fill=METAL)
        body_radii = (40, body_radii[1], body_radii[2], 40)
        # A side button on the right.
        y = oy + round(bh * 0.30)
        draw.rounded_rectangle((ox + bw - RIM, y, ox + bw + BUMP, y + round(bh * 0.10)), radius=BUMP, fill=METAL_LIGHT)
    else:
        # Hinge tabs at the middle of the top and bottom edges.
        cx = ox + bw // 2
        tab = round(bw * 0.035)
        for y0, y1 in ((oy - BUMP // 2, oy + RIM), (oy + bh - RIM, oy + bh + BUMP // 2)):
            draw.rounded_rectangle((cx - tab, y0, cx + tab, y1), radius=4, fill=METAL_LIGHT)
            draw.line((cx, y0, cx, y1), fill=GLASS, width=4)

    # Metal band, a lighter edge on it, then the glass, then the screen.
    rim_body = Image.new("RGBA", body_size, (0, 0, 0, 0))
    rim_body.paste(Image.new("RGBA", body_size, METAL_LIGHT + (255,)), (0, 0), rounded_mask(body_size, body_radii))
    inner_size = (bw - 6, bh - 6)
    rim_body.paste(Image.new("RGBA", inner_size, METAL + (255,)), (3, 3), rounded_mask(inner_size, grown(body_radii, -3)))
    glass_size = (bw - 2 * RIM, bh - 2 * RIM)
    rim_body.paste(Image.new("RGBA", glass_size, GLASS + (255,)), (RIM, RIM),
                   rounded_mask(glass_size, grown(screen_radii, BEZEL)))
    rim_body.paste(screen, (border, border), rounded_mask(screen_size, screen_radii))
    device.alpha_composite(rim_body, (ox, oy))
    return device


def with_shadow(device):
    """The device over a soft shadow, offset downward."""
    pad = 90
    shadow = Image.new("RGBA", (device.width + 2 * pad, device.height + 2 * pad), (0, 0, 0, 0))
    alpha = device.getchannel("A").point(lambda v: v * 0.38)
    shadow.paste((0, 0, 0, 255), (pad, pad + 36), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    shadow.alpha_composite(device, (pad, pad))
    return shadow, pad


def compose(slide, raw_dir, size, background, text_color):
    width, height = size
    canvas = Image.new("RGB", size, background)
    device_top = round(height * DEVICE_TOP)
    draw_caption(canvas, slide, device_top, round(height * CAPTION_SIZE), round(height * SUBTITLE_SIZE),
                 text_color, side_margin=SIDE_MARGIN, gap_factor=0.35, nudge=0)

    folded = [capture.endswith("-folded") for capture in slide["devices"]]
    devices = [draw_device(raw_dir / f"{capture}.png", f) for capture, f in zip(slide["devices"], folded)]
    # A lone open Duo fills the width and runs off the bottom edge; folded
    # ones stand side by side at a common height.
    if folded == [False]:
        scales = [width * OPEN_WIDTH / devices[0].width]
    else:
        scales = [height * DEVICE_HEIGHT / d.height for d in devices]
    spacing = round(width * GAP)
    total = sum(d.width * s for d, s in zip(devices, scales)) + spacing * (len(devices) - 1)
    if total > width * MAX_ROW:
        shrink = width * MAX_ROW / total
        scales = [s * shrink for s in scales]
        total *= shrink

    x = (width - total) / 2
    for device, scale in zip(devices, scales):
        resized = device.resize((round(device.width * scale), round(device.height * scale)), Image.LANCZOS)
        shadowed, pad = with_shadow(resized)
        canvas.paste(shadowed, (round(x) - pad, device_top - pad), shadowed)
        x += resized.width + spacing
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("raw_dir", type=pathlib.Path)
    parser.add_argument("output_dir", type=pathlib.Path)
    parser.add_argument("--size", default="2853x2007")
    args = parser.parse_args()

    size = tuple(int(v) for v in args.size.lower().split("x"))
    config = json.loads(CONFIG.read_text())
    args.output_dir.mkdir(parents=True, exist_ok=True)

    missing = []
    for slide in config["slides"]:
        if not all((args.raw_dir / f"{capture}.png").exists() for capture in slide["devices"]):
            missing.append(slide["name"])
            continue
        image = compose(slide, args.raw_dir, size, config["background"], config["text"])
        target = args.output_dir / f"{slide['name']}-{size[0]}x{size[1]}.png"
        image.save(target)
        print(target)

    if missing:
        print(f"skipped {len(missing)} slide(s) missing a capture: {', '.join(missing)}", file=sys.stderr)


if __name__ == "__main__":
    main()

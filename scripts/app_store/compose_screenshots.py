#!/usr/bin/env python3
"""Compose App Store marketing slides: caption on top, framed device below.

Reads the slide list from docs/app-store/screenshots.json and, for each slide,
the framed capture `<framed dir>/<capture>_framed.png` (frames-cli output). The
layout reproduces the hand-made 2025 set: a solid background, a centred white
caption in the top fifth, and the device at 93% of the canvas width running off
the bottom edge.

Usage: compose_screenshots.py <framed dir> <output dir> [--size WxH]

--size defaults to 1206x2622, the 6.3" iPhone size. 1320x2868 is the 6.9" size.
"""

import argparse
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

REPO = pathlib.Path(__file__).resolve().parents[2]
CONFIG = REPO / "docs" / "app-store" / "screenshots.json"

FONT_CANDIDATES = [
    "/Library/Fonts/SF-Pro-Display-Bold.otf",
    str(pathlib.Path.home() / "Library/Fonts/SF-Pro-Display-Bold.otf"),
]

# Proportions measured from the 2025 slides (1290 x 2796).
DEVICE_WIDTH = 0.93     # device frame width / canvas width
DEVICE_TOP = 0.19       # device frame top / canvas height
CAPTION_SIZE = 0.10     # caption font size / canvas width
SUBTITLE_SIZE = 0.058   # subtitle font size / canvas width
SIDE_MARGIN = 0.06      # minimum caption inset / canvas width
LINE_SPACING = 1.12     # caption line pitch / font size


def load_font(size):
    for path in FONT_CANDIDATES:
        if pathlib.Path(path).exists():
            return ImageFont.truetype(path, size)
    # San Francisco ships with macOS as a variable font.
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    font.set_variation_by_name("Bold")
    return font


def fitted_font(lines, size, max_width):
    """The largest font no bigger than `size` at which every line fits."""
    while size > 10:
        font = load_font(size)
        if all(font.getlength(line) <= max_width for line in lines):
            return font
        size -= 2
    return load_font(size)


def draw_lines(draw, lines, font, top, width, color):
    """Draws centred lines starting at `top`; returns the y below the last."""
    pitch = round(font.size * LINE_SPACING)
    for line in lines:
        draw.text((width / 2, top), line, font=font, fill=color, anchor="ma")
        top += pitch
    return top


def block_height(lines, font):
    return round(font.size * LINE_SPACING) * len(lines)


def compose(slide, framed, size, background, text_color):
    width, height = size
    canvas = Image.new("RGB", size, background)
    draw = ImageDraw.Draw(canvas)
    max_text = width * (1 - 2 * SIDE_MARGIN)

    caption = slide["caption"].split("\n")
    caption_font = fitted_font(caption, round(width * CAPTION_SIZE), max_text)
    subtitle = slide.get("subtitle")
    subtitle_lines = subtitle.split("\n") if subtitle else []
    subtitle_font = fitted_font(subtitle_lines, round(width * SUBTITLE_SIZE), max_text) if subtitle else None

    device_top = round(height * DEVICE_TOP)
    gap = round(caption_font.size * 0.45) if subtitle else 0
    text_height = block_height(caption, caption_font)
    if subtitle:
        text_height += gap + block_height(subtitle_lines, subtitle_font)
    # Centre the text in the band above the device, nudged up a little so it
    # doesn't crowd the frame.
    top = max(0, round((device_top - text_height) / 2 - height * 0.005))
    bottom = draw_lines(draw, caption, caption_font, top, width, text_color)
    if subtitle:
        draw_lines(draw, subtitle_lines, subtitle_font, bottom + gap, width, text_color)

    device = Image.open(framed).convert("RGBA")
    device_width = round(width * DEVICE_WIDTH)
    device_height = round(device.height * device_width / device.width)
    device = device.resize((device_width, device_height), Image.LANCZOS)
    canvas.paste(device, ((width - device_width) // 2, device_top), device)
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("framed_dir", type=pathlib.Path)
    parser.add_argument("output_dir", type=pathlib.Path)
    parser.add_argument("--size", default="1206x2622")
    args = parser.parse_args()

    size = tuple(int(v) for v in args.size.lower().split("x"))
    config = json.loads(CONFIG.read_text())
    args.output_dir.mkdir(parents=True, exist_ok=True)

    missing = []
    for index, slide in enumerate(config["slides"], start=1):
        framed = args.framed_dir / f"{slide['capture']}_framed.png"
        if not framed.exists():
            missing.append(framed.name)
            continue
        image = compose(slide, framed, size, config["background"], config["text"])
        target = args.output_dir / f"{index:02d}-{slide['capture'].split('-', 1)[1]}-{size[0]}x{size[1]}.png"
        image.save(target)
        print(target)

    if missing:
        print(f"skipped {len(missing)} slide(s) with no framed capture: {', '.join(missing)}", file=sys.stderr)


if __name__ == "__main__":
    main()

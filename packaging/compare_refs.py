#!/usr/bin/env python3
"""Scale a captured screen and a reference screenshot to the same width.

Writes a top-aligned side-by-side, a 50% overlay, and an absolute-difference
image. The release is not failed on the size of the difference; the images
are the thing to iterate on.
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont


def load_font(size):
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def crop(image, box):
    x, y, w, h = box
    return image.crop((x, y, x + w, y + h)).convert("RGB")


def fit_width(image, width):
    if image.width == width:
        return image
    height = max(1, round(image.height * width / image.width))
    return image.resize((width, height), Image.Resampling.LANCZOS)


def pad(image, width, height, color):
    canvas = Image.new("RGB", (width, height), color)
    canvas.paste(image, (0, 0))
    return canvas


def labeled_pair(ours, reference, font):
    gap = 16
    caption = 28
    width = ours.width + gap + reference.width
    height = caption + max(ours.height, reference.height)
    canvas = Image.new("RGB", (width, height), (32, 32, 32))
    draw = ImageDraw.Draw(canvas)
    draw.text((8, 4), "成品", fill=(240, 240, 240), font=font)
    draw.text((ours.width + gap + 8, 4), "真机", fill=(240, 240, 240), font=font)
    canvas.paste(ours, (0, caption))
    canvas.paste(reference, (ours.width + gap, caption))
    return canvas


def compare(shot_path, ref_path, crop_box, out_dir, name):
    shot = Image.open(shot_path).convert("RGB")
    reference = Image.open(ref_path).convert("RGB")
    ours = crop(shot, crop_box)
    width = reference.width
    ours_scaled = fit_width(ours, width)
    height = max(ours_scaled.height, reference.height)
    background = reference.getpixel((0, min(8, reference.height - 1)))
    ours_pad = pad(ours_scaled, width, height, background)
    ref_pad = pad(reference, width, height, background)
    overlay = Image.blend(ours_pad, ref_pad, 0.5)
    difference = ImageChops.difference(ours_pad, ref_pad)
    # Stretch the difference so a few gray levels stay visible.
    difference = difference.point(lambda channel: min(255, channel * 3))
    overlap = min(ours_scaled.height, reference.height)
    sample = ImageChops.difference(ours_scaled.crop((0, 0, width, overlap)), reference.crop((0, 0, width, overlap)))
    histogram = sample.convert("L").histogram()
    total = overlap * width
    mean = sum(index * count for index, count in enumerate(histogram)) / max(total, 1)
    font = load_font(18)
    out_dir.mkdir(parents=True, exist_ok=True)
    labeled_pair(ours_pad, ref_pad, font).save(out_dir / f"compare-{name}.png")
    overlay.save(out_dir / f"overlay-{name}.png")
    difference.save(out_dir / f"diff-{name}.png")
    print(f"{name}: crop {ours.size} -> {ours_scaled.size}, ref {reference.size}, mean-abs {mean:.2f}")
    return mean


def main():
    shots = Path(sys.argv[1])
    refs = Path(sys.argv[2])
    out = Path(sys.argv[3])
    jobs = [
        ("toolbar", shots / "workspace.png", refs / "toolbar.png", (0, 56, 84, 758)),
        ("newdoc", shots / "new-document.png", refs / "newdoc-details.png", (820, 124, 320, 636)),
        ("panels", shots / "workspace.png", refs / "panels.png", (84, 56, 1196, 758)),
    ]
    lines = []
    for name, shot, ref, box in jobs:
        if not shot.exists() or not ref.exists():
            raise SystemExit(f"missing {shot} or {ref}")
        mean = compare(shot, ref, box, out, name)
        lines.append(f"{name} {mean:.2f}")
    (out / "diff.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

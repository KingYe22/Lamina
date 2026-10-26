#!/usr/bin/env python3
"""Scale a captured screen and a reference screenshot to the same width.

Writes a top-aligned side-by-side, a 50% overlay, and an absolute-difference
image. The release is not failed on the size of the difference; the images
are the thing to iterate on.
"""

import sys
from pathlib import Path

import numpy as np
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
    masked, region_max = element_metrics(
        np.asarray(ours_scaled.crop((0, 0, width, overlap))),
        np.asarray(reference.crop((0, 0, width, overlap))),
    )
    font = load_font(18)
    out_dir.mkdir(parents=True, exist_ok=True)
    labeled_pair(ours_pad, ref_pad, font).save(out_dir / f"compare-{name}.png")
    overlay.save(out_dir / f"overlay-{name}.png")
    difference.save(out_dir / f"diff-{name}.png")
    print(
        f"{name}: crop {ours.size} -> {ours_scaled.size}, ref {reference.size}, "
        f"mean-abs {mean:.2f} masked {masked:.2f} region-max {region_max:.2f}"
    )
    return mean, masked, region_max


def element_metrics(ours, reference):
    """Mean difference on UI pixels, plus the worst 48px cell.

    Flat gray (the pasteboard and empty panel fill) is left out of the masked
    mean so a large empty area cannot hide a wrong control.
    """
    ours_i = ours.astype(np.int16)
    ref_i = reference.astype(np.int16)
    channel = np.abs(ours_i - ref_i).mean(axis=2)

    def away_from_flat(image):
        flat = image.reshape(-1, 3).astype(np.int16)
        # The two most common colors are the pasteboard and the panel fill.
        quant = (flat // 8) * 8
        # Pack RGB so bincount can find the modes.
        packed = quant[:, 0].astype(np.int32) * 65536 + quant[:, 1].astype(np.int32) * 256 + quant[:, 2].astype(np.int32)
        counts = np.bincount(packed)
        modes = np.argsort(counts)[-2:]
        distance = np.full(flat.shape[0], 999, dtype=np.int16)
        for mode in modes:
            color = np.array([(mode >> 16) & 255, (mode >> 8) & 255, mode & 255], dtype=np.int16)
            distance = np.minimum(distance, np.abs(flat - color).sum(axis=1))
        return distance.reshape(image.shape[:2]) > 36

    mask = away_from_flat(reference) | away_from_flat(ours)
    if int(mask.sum()) < 32:
        masked = float(channel.mean())
    else:
        masked = float(channel[mask].mean())

    cell = 48
    region_max = 0.0
    height, width = channel.shape
    for y in range(0, height, cell):
        for x in range(0, width, cell):
            block = channel[y:y + cell, x:x + cell]
            region_max = max(region_max, float(block.mean()))
    return masked, region_max


def main():
    shots = Path(sys.argv[1])
    refs = Path(sys.argv[2])
    out = Path(sys.argv[3])
    workspace = Image.open(shots / "workspace.png")
    document = Image.open(shots / "new-document.png")
    # Screenshots are captured at 2x so a point maps to two pixels, matching ai-ref.
    scale = 2 if workspace.width >= 1600 else 1

    def px(points):
        return int(round(points * scale))

    title, tabs, status, tool = px(28), px(28), px(26), px(81)
    body_top = title + tabs
    body_h = workspace.height - body_top - status
    sheet_w = min(px(1000), document.width - px(80))
    sheet_h = min(px(680), document.height - px(80))
    sheet_x = (document.width - sheet_w) // 2
    sheet_top = (document.height - sheet_h) // 2
    detail_w = px(308)
    detail_x = sheet_x + sheet_w - detail_w
    print(f"scale {scale} workspace {workspace.size} document {document.size}")
    jobs = [
        ("toolbar", shots / "workspace.png", refs / "toolbar.png", (0, body_top, tool, body_h)),
        ("newdoc", shots / "new-document.png", refs / "newdoc-details.png", (detail_x, sheet_top + px(44), detail_w, sheet_h - px(44))),
        ("panels", shots / "workspace.png", refs / "panels.png", (tool, body_top, workspace.width - tool, body_h)),
    ]
    lines = []
    for name, shot, ref, box in jobs:
        if not shot.exists() or not ref.exists():
            raise SystemExit(f"missing {shot} or {ref}")
        mean, masked, region_max = compare(shot, ref, box, out, name)
        lines.append(f"{name} {mean:.2f} masked {masked:.2f} region-max {region_max:.2f}")
    (out / "diff.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

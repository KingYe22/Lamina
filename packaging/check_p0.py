#!/usr/bin/env python3
"""Acceptance checks for the five v0.4.0 P0s on a real window capture.

The shot is 1033×970 points at 2×. Geometry matches EditorShell / WorkspaceMetrics.
Illustrator was not running here. The oracle numbers below were measured on the
inbox references before this script was written:

- ux-v039/05-panel-header.png is 608×44, so a title bar is 22 pt.
- ai-ref/panels.png structural rules are 2 px at 2× (1 logical px), for example
  rows 76–77, 151–152 and 784–785.
- ux-v039/01-ai-workspace.png has no #606060 strip between the title chrome and
  the toolbar body. The right column reaches the window edge (x 4340–4967 of 4968).
- ux-v039/06-dock-blue-line.jpg mode near the guide is (0, 114, 239), #0072EF.
- lock pen hotspot: 32×32 bitmap, tip at top-left pixel (0, 25), never the center.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image


WINDOW_W = 1033
WINDOW_H = 970
SCALE = 2
TITLE_BAND = 28
TAB = 28
STATUS = 20
TOOL = 81
CHROME = 89
TITLE_PT = 22
PANEL_FILL = np.array([83, 83, 83])
TITLE_FILL = np.array([66, 66, 66])
LINE = np.array([106, 106, 106])
PASTE = np.array([96, 96, 96])
GUIDE = np.array([0, 114, 239])


def load(path):
    image = Image.open(path).convert("RGB")
    return np.asarray(image)


def lum(pixel):
    return float(np.mean(pixel))


def near(pixel, color, tol):
    return np.max(np.abs(pixel.astype(np.int16) - color)) <= tol


def column_height():
    top = WINDOW_H - TITLE_BAND
    body = top - TAB - STATUS
    return body - CHROME


def panel_top_px(top_pt):
    # Distance from the top of the window to the panel's top edge, in pixels.
    return (WINDOW_H - STATUS - column_height() + top_pt) * SCALE


def appearance_box():
    x = (TOOL + 19) * SCALE
    y = panel_top_px(20)
    return x, y, 302 * SCALE, 243 * SCALE


def align_box():
    x = (TOOL + 322) * SCALE
    y = panel_top_px(20)
    return x, y, 313 * SCALE, 283 * SCALE


def stroke_box():
    x = (TOOL + 322) * SCALE
    y = panel_top_px(303)
    return x, y, 313 * SCALE, 442 * SCALE


def edge_run(image, y, x0, step):
    """How many pixels, walking from x0 by step, match the first pixel."""
    color = image[y, x0].astype(np.int16)
    count = 0
    x = x0
    while 0 <= x < image.shape[1] and np.max(np.abs(image[y, x].astype(np.int16) - color)) <= 8:
        count += 1
        x += step
    return count, image[y, x0]


def vertical_run(image, x, y0, step):
    color = image[y0, x].astype(np.int16)
    count = 0
    y = y0
    while 0 <= y < image.shape[0] and np.max(np.abs(image[y, x].astype(np.int16) - color)) <= 8:
        count += 1
        y += step
    return count, image[y0, x]


def require(ok, message):
    print(("PASS " if ok else "FAIL ") + message)
    return ok


def check_borders(workspace):
    ok = True
    ax, ay, aw, ah = appearance_box()
    title_row = ay + 10
    print(f"appearance box px x={ax} y={ay} w={aw} h={ah} sample={workspace[title_row, ax + 8].tolist()}")
    # Left edge is one logical pixel, then the title fill.
    left_n, left_c = edge_run(workspace, title_row, ax, 1)
    ok &= require(left_n == 2 and near(left_c, LINE, 18), f"appearance left edge {left_n}px {left_c.tolist()}")
    ok &= require(near(workspace[title_row, ax + 4], TITLE_FILL, 18), f"appearance title fill {workspace[title_row, ax + 4].tolist()}")
    right = ax + aw - 1
    right_n, right_c = edge_run(workspace, title_row, right, -1)
    ok &= require(right_n == 2 and near(right_c, LINE, 18), f"appearance right edge {right_n}px {right_c.tolist()}")
    gap = workspace[title_row, right + 1]
    ok &= require(not near(gap, LINE, 12), f"gap after appearance is not a second border {gap.tolist()}")
    lx, ly, lw, _ = align_box()
    align_n, align_c = edge_run(workspace, ly + 10, lx, 1)
    ok &= require(align_n == 2 and near(align_c, LINE, 18), f"align left edge {align_n}px {align_c.tolist()}")
    sx, sy, sw, _ = stroke_box()
    stroke_n, stroke_c = edge_run(workspace, sy + 10, sx, 1)
    ok &= require(stroke_n == 2 and near(stroke_c, LINE, 18), f"stroke left edge {stroke_n}px {stroke_c.tolist()}")
    # Top edge and the 22 pt title, measured on a column inside the panel.
    inside = ax + 30
    top_n, top_c = vertical_run(workspace, inside, ay, 1)
    ok &= require(top_n == 2 and near(top_c, LINE, 18), f"appearance top edge {top_n}px {top_c.tolist()}")
    divider_y = ay + TITLE_PT * SCALE - 2
    div_n, div_c = vertical_run(workspace, inside, divider_y, 1)
    ok &= require(div_n == 2 and near(div_c, LINE, 18), f"appearance divider {div_n}px at {divider_y} {div_c.tolist()}")
    body = workspace[divider_y + 3, inside]
    ok &= require(near(body, PANEL_FILL, 18), f"appearance body under title {body.tolist()}")
    for name, box in (("align", align_box()), ("stroke", stroke_box())):
        x, y, w, _ = box
        # Right side of the title bar, clear of the tab labels and the menu button.
        column = x + w - 180
        top_n, _ = vertical_run(workspace, column, y, 1)
        div_y = y + TITLE_PT * SCALE - 2
        div_n, _ = vertical_run(workspace, column, div_y, 1)
        title = workspace[y + 10, column]
        ok &= require(
            top_n == 2 and div_n == 2 and near(title, TITLE_FILL, 18),
            f"{name} title band top {top_n}px divider {div_n}px fill {title.tolist()} y={y}",
        )
    bottom = ay + ah - 1
    bot_n, bot_c = vertical_run(workspace, inside, bottom, -1)
    ok &= require(bot_n == 2 and near(bot_c, LINE, 18), f"appearance bottom edge {bot_n}px {bot_c.tolist()}")
    return ok


def check_toolbar(workspace):
    # The old hole was pasteboard #606060 for about 22 pt under the title.
    x = 16
    y0 = TITLE_BAND * SCALE
    y1 = y0 + 40
    strip = workspace[y0:y1, x]
    print(f"toolbar seam x={x} y={y0}..{y1} first={strip[0].tolist()} mid={strip[len(strip)//2].tolist()}")
    paste_hits = sum(near(pixel, PASTE, 6) for pixel in strip)
    panel_hits = sum(near(pixel, PANEL_FILL, 12) for pixel in strip)
    ok = require(paste_hits == 0 and panel_hits > 30, f"toolbar seam paste={paste_hits} panel={panel_hits}")
    # Left edge stays on the window. A couple of pixels in is still toolbar fill.
    left = workspace[y0 + 20, 4]
    ok &= require(near(left, PANEL_FILL, 14), f"toolbar left {left.tolist()}")
    return ok


def blue_count(image, x0):
    crop = image[:, x0:].astype(np.int16)
    return int(np.sum((crop[:, :, 0] < 40) & (crop[:, :, 2] > 180) & (crop[:, :, 2] > crop[:, :, 0] + 120)))


def check_dock(guide, snapped):
    ok = True
    blues = blue_count(guide, guide.shape[1] - 12)
    ok &= require(blues > 200, f"guide blue pixels in the last 12 columns: {blues}")
    # The guide color should be the #0072EF sample, not the toolbar accent.
    crop = guide[:, -8:].astype(np.int16)
    mask = (crop[:, :, 0] < 40) & (crop[:, :, 2] > 180)
    if mask.any():
        mean = crop[mask].mean(axis=0)
        dist = np.max(np.abs(mean - GUIDE))
        print(f"guide mean {mean.round(1).tolist()} dist {dist:.1f}")
        ok &= require(dist < 40, f"guide color distance {dist:.1f}")
    else:
        ok &= require(False, "no guide pixels to sample")
    snapped_blue = blue_count(snapped, snapped.shape[1] - 12)
    ok &= require(snapped_blue < 40, f"snapped shot blue pixels {snapped_blue}")
    # Appearance moved to the window's right edge. Its title fill reaches the border.
    _, ay, aw, _ = appearance_box()
    host_w = (WINDOW_W - TOOL) * SCALE
    snapped_x = TOOL * SCALE + host_w - aw
    title = snapped[ay + 10, snapped_x + 8]
    edge = snapped[ay + 10, -1]
    inside = snapped[ay + 10, -4]
    print(f"snapped title {title.tolist()} inside {inside.tolist()} edge {edge.tolist()} x={snapped_x}")
    ok &= require(near(title, TITLE_FILL, 18), f"snapped panel title {title.tolist()}")
    ok &= require(near(inside, TITLE_FILL, 18), f"snapped interior reaches the edge {inside.tolist()}")
    ok &= require(near(edge, LINE, 18), f"snapped outer edge {edge.tolist()}")
    # The resting appearance column is no longer at the metric x.
    metric_x = appearance_box()[0]
    resting = snapped[ay + 10, metric_x + 8]
    ok &= require(not near(resting, TITLE_FILL, 12), f"old appearance slot cleared {resting.tolist()}")
    return ok


def bright_count(image, box):
    x, y, w, h = box
    crop = image[y + 48:y + h - 8, x + 8:x + w - 8]
    return int(np.sum(crop.max(axis=2) > 150))


def check_generative(before, after):
    box = appearance_box()
    align = align_box()
    stroke = stroke_box()
    ok = True
    for name, rect in (("appearance", box), ("align", align), ("stroke", stroke)):
        a = bright_count(before, rect)
        b = bright_count(after, rect)
        print(f"{name} bright before {a} after {b}")
        ok &= require(a > 20 and b > a * 0.7, f"{name} ink stayed ({a} -> {b})")
    # A new accent control appears outside the toolbar.
    def accent(image):
        crop = image[:, TOOL * SCALE :].astype(np.int16)
        return int(np.sum((np.abs(crop[:, :, 0] - 21) < 30) & (np.abs(crop[:, :, 1] - 115) < 30) & (crop[:, :, 2] > 190)))
    before_n = accent(before)
    after_n = accent(after)
    print(f"accent pixels outside toolbar before {before_n} after {after_n}")
    ok &= require(after_n > before_n + 20, f"generative accent added ({before_n} -> {after_n})")
    return ok


def check_pen(path):
    image = Image.open(path).convert("RGBA")
    print(f"pen cursor {image.size} {image.mode}")
    ok = require(image.size == (32, 32), f"pen cursor size {image.size}")
    pixels = np.asarray(image)
    tip = pixels[25, 0]
    print(f"tip pixel {tip.tolist()}")
    ok &= require(tip[3] > 200 and tip[:3].max() < 40, f"tip at (0, 25) is opaque black {tip.tolist()}")
    column = pixels[:, 0]
    dark_rows = [index for index, pixel in enumerate(column) if pixel[3] > 200 and pixel[:3].max() < 40]
    print(f"dark rows in column 0: {dark_rows}")
    ok &= require(dark_rows == [25], f"only the tip pixel is dark in column 0 {dark_rows}")
    center = pixels[16, 16]
    ok &= require(not (center[3] > 200 and center[:3].max() < 40 and dark_rows == [16]), "hotspot is not the center")
    report = path.with_name("p0-report.txt").read_text(encoding="utf-8")
    print(report)
    ok &= require("penTL=0,25" in report and "penCenter=false" in report and "penCursor=0,7" in report, "report records the nib hotspot")
    return ok


def main():
    shot_dir = Path(sys.argv[1])
    workspace = load(shot_dir / "workspace.png")
    print(f"workspace {workspace.shape}")
    ok = True
    ok &= check_borders(workspace)
    ok &= check_toolbar(workspace)
    ok &= check_dock(load(shot_dir / "p0-dock-guide.png"), load(shot_dir / "p0-dock-snapped.png"))
    ok &= check_generative(workspace, load(shot_dir / "p0-generative.png"))
    ok &= check_pen(shot_dir / "pen-cursor.png")
    if not ok:
        raise SystemExit(1)
    print("all five P0 checks passed")


if __name__ == "__main__":
    main()

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
- pen hotspot is the nib tip in the same top-left space as the bitmap.
  p0-report penCursor equals penTip; penTipError is max(|dx|, |dy|) at 1× and
  2× and must be ≤ 1.5. The tip pixel is opaque black. The nib has an interior
  white slit and no sticker outline. pen-cursor-new.png adds the asterisk.
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
    # Pasteboard #606060 sits 10 levels from the #6A line. A stacked border would be the line itself.
    gap_line = int(np.max(np.abs(gap.astype(np.int16) - LINE)))
    ok &= require(gap_line > 6, f"gap after appearance is not a second border {gap.tolist()} (line distance {gap_line})")
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


def report_fields(path):
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key.strip()] = value.strip()
    return fields


def check_pen(path):
    image = Image.open(path).convert("RGBA")
    print(f"pen cursor {image.size} {image.mode}")
    ok = require(image.size == (32, 32), f"pen cursor size {image.size}")
    pixels = np.asarray(image)
    report_path = path.with_name("p0-report.txt")
    report = report_path.read_text(encoding="utf-8")
    print(report)
    fields = report_fields(report_path)
    tip = [float(part) for part in fields["penTip"].split(",")]
    cursor = [float(part) for part in fields["penCursor"].split(",")]
    pixel = [int(part) for part in fields["penPixel"].split(",")]
    pix_x, pix_y = pixel
    ok &= require(abs(cursor[0] - tip[0]) < 0.01, f"hotspot x {cursor[0]} is the tip x {tip[0]}")
    ok &= require(abs(cursor[1] - tip[1]) < 0.01, f"hotspot y {cursor[1]} is the tip y {tip[1]}")
    ok &= require(fields.get("penCenter") == "false", "hotspot is not the center")
    ok &= require(abs(float(fields["penTipError"])) <= 1.5, f"tip error {fields.get('penTipError')}")
    for key in ("penTipError1", "penTipError2"):
        ok &= require(abs(float(fields[key])) <= 1.5, f"{key} {fields.get(key)}")
    ok &= require(pix_x == int(tip[0]) and pix_y == int(tip[1]), f"pixel {pixel} is the tip {tip}")
    ok &= require(abs(pix_x - 16) > 6 and abs(pix_y - 16) > 6, f"tip {pixel} is not the center")

    tip_px = pixels[pix_y, pix_x]
    print(f"tip pixel {tip_px.tolist()} at {pixel}")
    ok &= require(int(tip_px[3]) > 200 and int(tip_px[:3].max()) < 48, f"tip pixel is opaque black {tip_px.tolist()}")
    if pix_x > 0 and pix_y > 0:
        neighbor = pixels[pix_y - 1, pix_x - 1]
        ok &= require(int(neighbor[3]) < 16, f"up-left of the tip is empty {neighbor.tolist()}")

    alpha = pixels[:, :, 3]
    ys, xs = np.where(alpha > 16)
    score = xs.astype(int) + ys.astype(int)
    min_score = int(score.min())
    at_tip = score == min_score
    ul_x = float(xs[at_tip].min())
    ul_y = float(ys[at_tip].min())
    print(f"measured tip UL {ul_x},{ul_y} hotspot {cursor[0]},{cursor[1]}")
    ok &= require(max(abs(ul_x - cursor[0]), abs(ul_y - cursor[1])) <= 1.5, "png tip UL is the hotspot")
    ok &= require(min_score == pix_x + pix_y, f"foremost ink score {min_score} tip {pix_x + pix_y}")
    ok &= require(bool(np.all(xs[at_tip] == pix_x) and np.all(ys[at_tip] == pix_y)), "foremost opaque pixel is the tip")

    rgb = pixels[:, :, :3].astype(np.int16)
    black = (alpha > 200) & (rgb.max(axis=2) < 48)
    white = (alpha > 200) & (rgb.min(axis=2) > 200)
    print(f"black {int(black.sum())} white {int(white.sum())}")
    ok &= require(int(black.sum()) > 40, "solid black nib")
    interior = np.zeros(alpha.shape, dtype=bool)
    interior[1:-1, 1:-1] = (
        white[1:-1, 1:-1]
        & (alpha[:-2, 1:-1] > 200)
        & (alpha[2:, 1:-1] > 200)
        & (alpha[1:-1, :-2] > 200)
        & (alpha[1:-1, 2:] > 200)
    )
    exposed = np.zeros(alpha.shape, dtype=bool)
    exposed[1:-1, 1:-1] = (
        white[1:-1, 1:-1]
        & (
            (alpha[:-2, 1:-1] < 16)
            | (alpha[2:, 1:-1] < 16)
            | (alpha[1:-1, :-2] < 16)
            | (alpha[1:-1, 2:] < 16)
        )
    )
    print(f"interior white {int(interior.sum())} exterior white {int(exposed.sum())}")
    ok &= require(int(interior.sum()) >= 4, "white slit inside the black nib")
    ok &= require(int(exposed.sum()) < 8, "no sticker outline around the nib")

    star = np.asarray(Image.open(path.with_name("pen-cursor-new.png")).convert("RGBA"))
    ok &= require(star.shape[:2] == (32, 32), f"new-path cursor {star.shape}")

    def corner(image):
        return int((image[22:, 22:, 3] > 16).sum())

    plain_corner = corner(pixels)
    star_corner = corner(star)
    print(f"lower-right opaque plain {plain_corner} new-path {star_corner}")
    ok &= require(star_corner > plain_corner + 10, "new-path cursor carries the asterisk")
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

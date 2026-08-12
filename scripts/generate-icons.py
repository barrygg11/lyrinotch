#!/usr/bin/env python3
"""Generate AppIcon.icns and menu-bar template images from the Lyrinotch logo.

The source logo is a white mark on a black squircle, often exported with a
near-white canvas outside the squircle. We flood-fill that canvas away, keep
the white artwork, drop the wordmark for the menu-bar glyph, and build:
  - Resources/AppIcon.icns  (full logo for the .app bundle)
  - Sources/Lyrinotch/Resources/MenuBarIcon[.png|@2x.png]  (template mark)
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from collections import deque
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pillow", "-q"])
    from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

# Source logo (override with LYRINOTCH_LOGO=/path/to/logo.png).
DEFAULT_LOGO = ROOT / "Resources" / "AppIcon-source.png"


def flood_white_background(img: Image.Image, thr: int = 200) -> list[list[bool]]:
    """Mark near-white canvas (outside the black squircle) as background."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    pix = rgba.load()
    is_bg = [[False] * w for _ in range(h)]
    q: deque[tuple[int, int]] = deque()

    def is_light(x: int, y: int) -> bool:
        r, g, b, _a = pix[x, y]
        return (r + g + b) / 3 >= thr

    for sx, sy in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if is_light(sx, sy):
            is_bg[sy][sx] = True
            q.append((sx, sy))

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not is_bg[ny][nx] and is_light(nx, ny):
                is_bg[ny][nx] = True
                q.append((nx, ny))
    return is_bg


def design_mask(img: Image.Image, is_bg: list[list[bool]], thr: int = 180) -> Image.Image:
    """White artwork on the black body (excludes flooded canvas).

    Threshold is high so anti-aliased gray along the squircle edge is ignored;
    only the near-white logo strokes become the menu-bar glyph.
    """
    rgba = img.convert("RGBA")
    w, h = rgba.size
    pix = rgba.load()
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    for y in range(h):
        for x in range(w):
            if is_bg[y][x]:
                continue
            r, g, b, _a = pix[x, y]
            lum = (r + g + b) // 3
            if lum > thr:
                mp[x, y] = min(255, int(lum * 1.05))
    return mask


def cut_before_wordmark(mask: Image.Image) -> Image.Image:
    """Drop the bottom 'lyrinotch' wordmark using the empty gap above it."""
    w, h = mask.size
    mp = mask.load()
    row_sum = [sum(mp[x, y] for x in range(w)) for y in range(h)]
    mid = h // 2
    gap_start = None
    in_gap = False
    for y in range(mid, h):
        empty = row_sum[y] < 200
        if empty and not in_gap:
            in_gap = True
            gap_start = y
        elif not empty and in_gap:
            break
    cut_y = (gap_start - 4) if gap_start is not None else int(h * 0.72)
    cut_y = max(1, min(h, cut_y))
    mark = mask.crop((0, 0, w, cut_y))
    bb = mark.getbbox()
    if not bb:
        return mark
    pad = 12
    x0 = max(0, bb[0] - pad)
    y0 = max(0, bb[1] - pad)
    x1 = min(w, bb[2] + pad)
    y1 = min(cut_y, bb[3] + pad)
    return mark.crop((x0, y0, x1, y1))


def square_canvas(mask: Image.Image, pad_frac: float = 0.09) -> Image.Image:
    mw, mh = mask.size
    side = max(mw, mh)
    canvas_side = int(side * (1 + 2 * pad_frac))
    canvas = Image.new("L", (canvas_side, canvas_side), 0)
    canvas.paste(mask, ((canvas_side - mw) // 2, (canvas_side - mh) // 2))
    return canvas


def make_template(mask_l: Image.Image, size: int) -> Image.Image:
    """Black RGB + alpha (macOS template-image convention)."""
    m = mask_l.resize((size, size), Image.Resampling.LANCZOS)
    rgba = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    black = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    rgba.paste(black, (0, 0), m)
    return rgba


def opaque_app_icon(img: Image.Image, is_bg: list[list[bool]]) -> Image.Image:
    """Full logo on opaque black (Dock / Finder)."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    pix = rgba.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if not is_bg[y][x]:
                op[x, y] = pix[x, y]
    return out


def save_iconset(src: Image.Image, out_dir: Path) -> None:
    two = "2x"
    mapping: dict[int, list[str]] = {
        16: [f"icon_16x16.png"],
        32: [f"icon_16x16@{two}.png", f"icon_32x32.png"],
        64: [f"icon_32x32@{two}.png"],
        128: [f"icon_128x128.png"],
        256: [f"icon_128x128@{two}.png", f"icon_256x256.png"],
        512: [f"icon_256x256@{two}.png", f"icon_512x512.png"],
        1024: [f"icon_512x512@{two}.png"],
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    for size, names in mapping.items():
        resized = src.resize((size, size), Image.Resampling.LANCZOS)
        for name in names:
            resized.save(out_dir / name)


def main() -> None:
    import os

    logo_path = Path(os.environ.get("LYRINOTCH_LOGO", DEFAULT_LOGO))
    if not logo_path.is_file():
        raise SystemExit(
            f"logo not found: {logo_path}\n"
            "Place a source PNG at Resources/AppIcon-source.png "
            "or set LYRINOTCH_LOGO=/path/to/logo.png"
        )

    img = Image.open(logo_path).convert("RGBA")
    print(f"logo: {img.size[0]}x{img.size[1]} from {logo_path}")

    is_bg = flood_white_background(img)
    app = opaque_app_icon(img, is_bg)

    resources = ROOT / "Resources"
    resources.mkdir(exist_ok=True)
    app.save(resources / "AppIcon.png")
    # Keep a regenerable source copy next to it.
    img.save(resources / "AppIcon-source.png")

    iconset = Path("/tmp/lyrinotch-icon.iconset")
    if iconset.exists():
        shutil.rmtree(iconset)
    save_iconset(app, iconset)
    icns = resources / "AppIcon.icns"
    subprocess.check_call(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)])
    print(f"wrote {icns} ({icns.stat().st_size} bytes)")

    mask = design_mask(img, is_bg)
    mark = cut_before_wordmark(mask)
    canvas = square_canvas(mark)
    print(f"menu mark: {mark.size[0]}x{mark.size[1]} → canvas {canvas.size[0]}")

    mb_dir = ROOT / "Sources" / "Lyrinotch" / "Resources"
    mb_dir.mkdir(parents=True, exist_ok=True)
    for size, name in (
        (22, "MenuBarIcon.png"),
        (44, "MenuBarIcon@2x.png"),
    ):
        dest = mb_dir / name
        make_template(canvas, size).save(dest)
        print(f"wrote {dest}")

    # Keep Assets.xcassets imageset in sync with loose PNGs.
    imageset = mb_dir / "Assets.xcassets" / "MenuBarIcon.imageset"
    if imageset.is_dir():
        for name in ("MenuBarIcon.png", "MenuBarIcon@2x.png"):
            src = mb_dir / name
            if src.is_file():
                shutil.copy2(src, imageset / name)
                print(f"synced {imageset / name}")

    print("done")


if __name__ == "__main__":
    main()

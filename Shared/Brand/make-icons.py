#!/usr/bin/env python3
"""Regenerate every 3£ icon from the butterfly mark in 3E-butterfly.svg.

The mark is a "3" and a "£" set back to back, their tops swung up and out and
their bottoms swung down and out so the pair reads as butterfly wings. It is
black and white only. Run from anywhere: python3 Shared/Brand/make-icons.py
(needs Pillow). Outputs:
  * Shared/Brand/mark-1024.png, icon-1024.png, 3E.icns
  * TouchBar/musicstrip/Source/Resources/StripIcon.icns (Mac app icon)
  * Windows/DragEngine/ThreeFingerDragOnWindows/Assets/* (exe icon, tiles, logos)
  * embedded PNGs in TrayIconArtwork.cs (Windows tray), ClicksAccents.cs
    (Clicks tray) and Shared/Brand/ThreeEBrand.h (Mac menu bar)
"""
import base64, io, re, shutil
from pathlib import Path
from PIL import Image, ImageDraw

BRAND = Path(__file__).resolve().parent
ROOT = BRAND.parent.parent
PLATE = (20, 20, 20, 255)

def rings():
    d = re.search(r' d="([^"]+)"', (BRAND / "3E-butterfly.svg").read_text()).group(1)
    for ring in d.split("Z"):
        pts = [tuple(map(float, p.strip().lstrip("ML").split())) for p in ring.split("L") if p.strip()]
        if pts: yield pts

def mark(size, fg=(0, 0, 0, 255), frac=0.96, ss=4):
    """The mark centred on a transparent square; `frac` of the width is used."""
    S = size * ss
    mask = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(mask)
    k = S / 1000 * frac; off = S * (1 - frac) / 2
    # Even-odd fill: outer contours and counters toggle coverage.
    for pts in rings():
        ring = Image.new("L", (S, S), 0)
        ImageDraw.Draw(ring).polygon([(x * k + off, y * k + off) for x, y in pts], fill=255)
        mask = Image.frombytes("L", (S, S), bytes(a ^ b for a, b in zip(mask.tobytes(), ring.tobytes())))
    im = Image.new("RGBA", (S, S), fg[:3] + (0,))
    im.paste(Image.new("RGBA", (S, S), fg), (0, 0), mask)
    return im.resize((size, size), Image.LANCZOS)

def icon(size):
    """App icon: white mark on a near-black rounded square (readable on any theme)."""
    S = size * 4
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = round(S * 0.02)
    ImageDraw.Draw(im).rounded_rectangle((m, m, S - m - 1, S - m - 1), radius=round(S * 0.2), fill=PLATE)
    im.alpha_composite(mark(S, fg=(255, 255, 255, 255), frac=0.76, ss=1))
    return im.resize((size, size), Image.LANCZOS)

def centred(w, h, frac):
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s = max(1, round(min(w, h) * frac))
    canvas.alpha_composite(icon(s), ((w - s) // 2, (h - s) // 2))
    return canvas

def png64(im):
    buf = io.BytesIO(); im.save(buf, "PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode()

def embed(path, name, data):
    """Replace the string literal that follows the marker comment `brand:<name>`."""
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    new, n = re.subn(r'(/\*brand:%s\*/\s*@?")[^"]*(")' % name, lambda m: m.group(1) + data + m.group(2), text)
    if n != 1: raise SystemExit(f"marker brand:{name} not found once in {path}")
    p.write_text(new, encoding="utf-8")

def main():
    mark(1024).save(BRAND / "mark-1024.png", optimize=True)
    big = icon(1024); big.save(BRAND / "icon-1024.png", optimize=True)
    big.save(BRAND / "3E.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    shutil.copyfile(BRAND / "3E.icns", ROOT / "TouchBar/musicstrip/Source/Resources/StripIcon.icns")

    assets = ROOT / "Windows/DragEngine/ThreeFingerDragOnWindows/Assets"
    for f in assets.glob("*.png"):
        if f.name.startswith(("Screenshot", "Touchpad", "icon-threefinger")): continue
        w, h = Image.open(f).size
        if f.name.startswith(("logo-44", "icon-52", "logo-512", "Badge")): out = icon(w)
        elif f.name.startswith(("SmallTile", "LargeTile", "logo-150")): out = centred(w, h, 0.66)
        else: out = centred(w, h, 0.6)
        out.save(f, optimize=True)
    icon(256).save(assets / "icon.ico", sizes=[(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)])

    # Windows tray: white mask, recoloured for the taskbar theme at runtime.
    embed("Windows/DragEngine/ThreeFingerDragOnWindows/TrayIconArtwork.cs", "mask", png64(mark(64, fg=(255, 255, 255, 255), frac=1.0)))
    embed("Windows/Keyboard/ClicksAccents.cs", "logo", png64(icon(32)))
    # Mac menu bar template image: black mark cropped to its bounds (22x14 pt @4x).
    m = mark(512, frac=1.0); m = m.crop(m.getbbox()).resize((88, 56), Image.LANCZOS)
    embed("Shared/Brand/ThreeEBrand.h", "menu", png64(m))
    print("Icons regenerated.")

if __name__ == "__main__":
    main()

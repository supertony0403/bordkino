"""Renders the Bordkino app icon (120 px and 180 px) into Resources/Common."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Resources" / "Common"
SS = 4  # supersampling factor for smooth edges


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size: int) -> Image.Image:
    s = size * SS
    img = Image.new("RGB", (s, s))
    top, bottom = (11, 18, 32), (30, 41, 59)
    px = img.load()
    for y in range(s):
        c = lerp(top, bottom, y / (s - 1))
        for x in range(s):
            px[x, y] = c
    d = ImageDraw.Draw(img)
    # cinema screen
    m = s * 0.16
    screen = (m, s * 0.18, s - m, s * 0.64)
    d.rounded_rectangle(screen, radius=s * 0.07, fill=(245, 158, 11))
    # play triangle
    cx, cy, r = s / 2, (screen[1] + screen[3]) / 2, s * 0.13
    d.polygon([(cx - r * 0.75, cy - r), (cx - r * 0.75, cy + r), (cx + r * 1.05, cy)], fill=(15, 23, 42))
    # road: two converging edges and dashed centre line
    d.polygon([(s * 0.30, s * 0.92), (s * 0.70, s * 0.92), (s * 0.56, s * 0.72), (s * 0.44, s * 0.72)], fill=(51, 65, 85))
    for i in range(3):
        y0 = s * (0.74 + i * 0.065)
        w = s * (0.008 + i * 0.006)
        d.rectangle((s / 2 - w, y0, s / 2 + w, y0 + s * 0.035), fill=(241, 245, 249))
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for scale, size in ((2, 120), (3, 180)):
        render(size).save(OUT / f"AppIcon60x60@{scale}x.png")
    print("icons written to", OUT)

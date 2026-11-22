"""
make_icons.py - draws the app icon (a black Greek letter Delta, Δ, on white) and
the iPhone start screens: a plain page in the app's background colour, light and
dark, in the exact size of every iPhone. iOS shows it while the app loads; then
the intro draws the logo on it (index.html).

    pip install pillow
    python tools/make_icons.py

You only need this if you want to change the icon. The finished PNG files are
already in phone/icons/.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BACKGROUND = "#ffffff"
LETTER = "#000000"
OUT = Path(__file__).resolve().parent.parent / "phone" / "icons"

# Bold fonts that contain the letter Δ. The first one found is used.
FONTS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",   # Linux
    "C:/Windows/Fonts/arialbd.ttf",                          # Windows
    "C:/Windows/Fonts/segoeuib.ttf",
    "DejaVuSans-Bold.ttf",
]


def load_font(size):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return None


def draw_icon(size):
    # Draw 4x larger and shrink at the end: that gives smooth edges.
    s = size * 4
    image = Image.new("RGB", (s, s), BACKGROUND)
    draw = ImageDraw.Draw(image)
    font = load_font(int(s * 0.62))
    if font:
        # Centre the letter by its real outline, not by the font's line height.
        left, top, right, bottom = draw.textbbox((0, 0), "Δ", font=font)
        x = (s - (right - left)) / 2 - left
        y = (s - (bottom - top)) / 2 - top
        draw.text((x, y), "Δ", font=font, fill=LETTER)
    else:
        # No suitable font: draw the Delta as a thick triangle outline.
        w = s * 0.11
        outer = [(s * 0.5, s * 0.2), (s * 0.82, s * 0.78), (s * 0.18, s * 0.78)]
        draw.polygon(outer, fill=LETTER)
        inner = [(s * 0.5, s * 0.2 + w * 2.1), (s * 0.82 - w * 1.8, s * 0.78 - w), (s * 0.18 + w * 1.8, s * 0.78 - w)]
        draw.polygon(inner, fill=BACKGROUND)
    return image.resize((size, size), Image.LANCZOS)


# iPhone screens in points (portrait) and their pixel ratio. iOS only uses a start
# screen whose size matches the phone exactly.
IPHONES = [
    (440, 956, 3),   # 16 Pro Max, 17 Pro Max
    (430, 932, 3),   # 14 Pro Max, 15 Plus / Pro Max, 16 Plus
    (428, 926, 3),   # 12 / 13 Pro Max, 14 Plus
    (420, 912, 3),   # Air
    (414, 896, 3),   # XS Max, 11 Pro Max
    (414, 896, 2),   # XR, 11
    (414, 736, 3),   # 6 Plus – 8 Plus
    (402, 874, 3),   # 16 Pro, 17, 17 Pro
    (393, 852, 3),   # 14 Pro, 15, 15 Pro, 16
    (390, 844, 3),   # 12, 13, 14, 16e
    (375, 812, 3),   # X, XS, 11 Pro, 12 / 13 mini
    (375, 667, 2),   # SE (2nd and 3rd gen.), 6 – 8
]
START_COLOURS = {"light": "#e7e7e7", "dark": "#000000"}    # --bg in theme.css


def start_screen_tags():
    """The <link> lines for index.html."""
    lines = []
    for scheme in START_COLOURS:
        for w, h, r in IPHONES:
            lines.append(
                f'  <link rel="apple-touch-startup-image" href="icons/start-{w * r}x{h * r}-{scheme}.png" '
                f'media="(device-width: {w}px) and (device-height: {h}px) and (-webkit-device-pixel-ratio: {r}) '
                f'and (orientation: portrait) and (prefers-color-scheme: {scheme})">')
    return "\n".join(lines)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for size in (180, 192, 512):
        draw_icon(size).save(OUT / f"icon-{size}.png")
        print("wrote", OUT / f"icon-{size}.png")
    for scheme, colour in START_COLOURS.items():
        for w, h, r in IPHONES:
            path = OUT / f"start-{w * r}x{h * r}-{scheme}.png"
            Image.new("P", (w * r, h * r), colour).save(path, optimize=True)
    print("wrote", len(IPHONES) * len(START_COLOURS), "start screens")
    print("\nFor index.html:\n" + start_screen_tags())

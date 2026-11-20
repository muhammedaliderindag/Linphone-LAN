"""Generates the DerindSIP branding assets for the LAN build.

  python scripts/derindsip_branding.py

Writes:
  Linphone/Assets.xcassets/linphone.imageset/linphone.svg   in-app logo (single colour; the app
                                                            tints it as a template image)
  Linphone/Assets.xcassets/AppIcon.appiconset/1024x1024.png app icon (RGB, no alpha)

Needs Pillow and PyMuPDF (fitz, used to rasterise the SVG).
"""
import os

import fitz  # PyMuPDF
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Linphone", "Assets.xcassets")
LOGO_SVG = os.path.join(ASSETS, "linphone.imageset", "linphone.svg")
ICON_PNG = os.path.join(ASSETS, "AppIcon.appiconset", "1024x1024.png")
FONT = os.path.join(ROOT, "Linphone", "Fonts", "NotoSans-ExtraBold.ttf")

# "D" (even-odd ring) with a phone handset inside. Handset = Material "call" glyph (Apache 2.0).
D_PATH = "M8 6H46A45 45 0 0 1 46 96H8Z M22 20H46A31 31 0 0 1 46 82H22Z"
HANDSET = (
    "M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 "
    "3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 "
    ".45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z"
)


def logo_svg(color="#000000", size=None):
    attrs = f'width="{size[0]}" height="{size[1]}" ' if size else 'width="100" height="102" '
    return (
        f'<svg {attrs}viewBox="0 0 100 102" fill="none" xmlns="http://www.w3.org/2000/svg">\n'
        f'<path fill-rule="evenodd" clip-rule="evenodd" d="{D_PATH}" fill="{color}"/>\n'
        f'<path transform="translate(24 27) scale(2)" d="{HANDSET}" fill="{color}"/>\n'
        "</svg>\n"
    )


def rasterise(svg, width, height):
    doc = fitz.open(stream=svg.encode(), filetype="svg")
    pix = doc[0].get_pixmap(alpha=True)
    return Image.frombytes("RGBA", (pix.width, pix.height), pix.samples).resize((width, height), Image.LANCZOS)


def make_icon():
    s = 1024
    top, bottom = (11, 31, 74), (0, 168, 181)  # navy -> teal (Linphone is orange)
    icon = Image.new("RGB", (s, s))
    px = ImageDraw.Draw(icon)
    for y in range(s):
        t = y / (s - 1)
        px.line([(0, y), (s, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

    logo_w, logo_h = 520, int(520 * 102 / 100)
    logo = rasterise(logo_svg("#FFFFFF", (logo_w * 2, logo_h * 2)), logo_w, logo_h)
    icon.paste(logo, ((s - logo_w) // 2 + 20, 130), logo)

    draw = ImageDraw.Draw(icon)
    font = ImageFont.truetype(FONT, 170)
    text = "SIP"
    w = draw.textlength(text, font=font)
    draw.text(((s - w) / 2, 680), text, font=font, fill=(255, 255, 255))
    icon.save(ICON_PNG)


def main():
    with open(LOGO_SVG, "w", newline="\n") as f:
        f.write(logo_svg())
    make_icon()
    print("wrote", LOGO_SVG)
    print("wrote", ICON_PNG)


if __name__ == "__main__":
    main()

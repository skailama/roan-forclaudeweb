"""Build the email and YouTube thumbnails from the raw Zoom screenshot.

Usage: python3 -I scripts/thumbnails.py   (run from the project folder)

Outputs (thumbnails/):
  email-play.jpg       1200x675  screenshot + play button
  email-play-bar.jpg   1200x675  screenshot + play button + "BFCM Prep Live" bar
  youtube.jpg          1280x720  screenshot + bar, no play button (YouTube draws its own)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "source" / "thumbnail-source.png"
OUT = ROOT / "thumbnails"
FONTS = Path("/usr/share/fonts/opentype/inter")

W, H = 1920, 1080
SS = 4  # supersampling factor for smooth shapes

TOP_BAR = (29, 30, 32)  # Zoom's title bar colour, used to pad to 16:9
BAR_BG = (12, 12, 14)
BAR_H = 128
RED = (230, 45, 45)


def canvas():
    """The raw screenshot, padded to 16:9 with Zoom's own chrome colours."""
    shot = Image.open(SRC).convert("RGB")
    shot = shot.crop((0, 0, shot.width, shot.height - 2))  # drop a stray edge line
    shot = shot.resize((W, round(shot.height * W / shot.width)), Image.LANCZOS)
    pad = H - shot.height
    img = Image.new("RGB", (W, H), (0, 0, 0))
    img.paste(Image.new("RGB", (W, pad // 2), TOP_BAR), (0, 0))
    img.paste(shot, (0, pad // 2))
    return img


def play_button(img, cx=W // 2, cy=H // 2, r=104):
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    R, X, Y = r * SS, cx * SS, cy * SS
    d.ellipse((X - R, Y - R, X + R, Y + R), fill=(0, 0, 0, 170),
              outline=(255, 255, 255, 255), width=6 * SS)
    t = R * 0.42  # triangle half-height, nudged right so it looks centred
    off = R * 0.1
    d.polygon([(X - t * 0.8 + off, Y - t), (X - t * 0.8 + off, Y + t), (X + t + off, Y)],
              fill=(255, 255, 255, 255))
    layer = layer.resize((W, H), Image.LANCZOS)
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def bar(img):
    """A plain dark strip over Zoom's bottom toolbar: rec dot, name, title, CTA."""
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    top = (H - BAR_H) * SS
    d.rectangle((0, top, W * SS, H * SS), fill=BAR_BG + (255,))
    mid = top + BAR_H * SS // 2

    bold = ImageFont.truetype(str(FONTS / "Inter-Bold.otf"), 50 * SS)
    reg = ImageFont.truetype(str(FONTS / "Inter-Regular.otf"), 44 * SS)
    small = ImageFont.truetype(str(FONTS / "Inter-SemiBold.otf"), 34 * SS)

    x = 64 * SS
    dot = 15 * SS
    d.ellipse((x, mid - dot, x + 2 * dot, mid + dot), fill=RED + (255,))
    x += 2 * dot + 26 * SS
    d.text((x, mid), "BFCM Prep Live", font=bold, fill=(255, 255, 255, 255), anchor="lm")
    x += d.textlength("BFCM Prep Live", font=bold) + 28 * SS
    sep = "·  The first Black Friday of the AI era"
    d.text((x, mid), sep, font=reg, fill=(205, 205, 210, 255), anchor="lm")
    d.text((W * SS - 64 * SS, mid), "Full recording", font=small,
           fill=(150, 150, 158, 255), anchor="rm")
    layer = layer.resize((W, H), Image.LANCZOS)
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def save(img, name, size):
    img.resize(size, Image.LANCZOS).save(OUT / name, quality=90, optimize=True, progressive=True)
    print(name, size, (OUT / name).stat().st_size // 1024, "KB")


def main():
    OUT.mkdir(exist_ok=True)
    base = canvas()
    save(play_button(base), "email-play.jpg", (1200, 675))
    save(play_button(bar(base), cy=(H - BAR_H) // 2), "email-play-bar.jpg", (1200, 675))
    save(bar(base), "youtube.jpg", (1280, 720))


if __name__ == "__main__":
    main()

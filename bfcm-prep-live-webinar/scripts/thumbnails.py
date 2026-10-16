"""Build the email and YouTube thumbnails from the raw Zoom screenshot.

Usage: python3 -I scripts/thumbnails.py   (run from the project folder)

Outputs (thumbnails/):
  email-play.jpg        1200x675  screenshot + play button
  email-play-label.jpg  1200x675  screenshot + play button + "BFCM Prep Live" pill
  youtube.jpg           1280x720  screenshot + pill, no play button (YouTube draws its own)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "source" / "thumbnail-source.png"
OUT = ROOT / "thumbnails"
FONTS = Path("/usr/share/fonts/opentype/inter")

W, H = 1920, 1080
SS = 4  # supersampling factor for smooth shapes

TOP_BAR = (29, 30, 32)  # Zoom's title bar colour, used to pad to 16:9
RED = (230, 45, 45)

# Regions of the screenshot (source pixels) that name the demo store: the
# "Gindos · Store readiness" browser tab.
REDACT = [(541, 205, 580, 225)]


def canvas():
    """The raw screenshot with the store name blurred, padded to 16:9 with Zoom's own colours."""
    shot = Image.open(SRC).convert("RGB")
    for box in REDACT:
        shot.paste(shot.crop(box).filter(ImageFilter.GaussianBlur(5)), box[:2])
    shot = shot.crop((0, 0, shot.width, shot.height - 2))  # drop a stray edge line
    shot = shot.resize((W, round(shot.height * W / shot.width)), Image.LANCZOS)
    pad = H - shot.height
    img = Image.new("RGB", (W, H), (0, 0, 0))
    img.paste(Image.new("RGB", (W, pad // 2), TOP_BAR), (0, 0))
    img.paste(shot, (0, pad // 2))
    return img


def overlay(img, draw_fn):
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    layer = layer.resize((W, H), Image.LANCZOS)
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def play_button(img, cx=W // 2, cy=H // 2, r=104):
    def draw(d):
        R, X, Y = r * SS, cx * SS, cy * SS
        d.ellipse((X - R, Y - R, X + R, Y + R), fill=(30, 30, 32, 215))
        t = R * 0.42  # triangle half-height, nudged right so it looks centred
        off = R * 0.1
        d.polygon([(X - t * 0.8 + off, Y - t), (X - t * 0.8 + off, Y + t), (X + t + off, Y)],
                  fill=(255, 255, 255, 255))
    return overlay(img, draw)


def label(img, x=68, y=135, text="BFCM Prep Live"):
    """Dark pill in the empty top-left of the Zoom window: red dot + name."""
    font = ImageFont.truetype(str(FONTS / "Inter-Bold.otf"), 40 * SS)

    def draw(d):
        h, pad_l, pad_r, dot, gap = 84 * SS, 46 * SS, 40 * SS, 12 * SS, 26 * SS
        tw = d.textlength(text, font=font)
        X, Y = x * SS, y * SS
        w = pad_l + 2 * dot + gap + tw + pad_r
        d.rounded_rectangle((X, Y, X + w, Y + h), radius=h // 2,
                            fill=(12, 12, 14, 245), outline=(48, 48, 52, 255), width=2 * SS)
        mid = Y + h // 2
        dx = X + pad_l
        d.ellipse((dx, mid - dot, dx + 2 * dot, mid + dot), fill=RED + (255,))
        d.text((dx + 2 * dot + gap, mid), text, font=font, fill=(255, 255, 255, 255), anchor="lm")
    return overlay(img, draw)


def save(img, name, size):
    img.resize(size, Image.LANCZOS).save(OUT / name, quality=90, optimize=True, progressive=True)
    print(name, size, (OUT / name).stat().st_size // 1024, "KB")


def main():
    OUT.mkdir(exist_ok=True)
    base = canvas()
    save(play_button(base), "email-play.jpg", (1200, 675))
    save(play_button(label(base)), "email-play-label.jpg", (1200, 675))
    save(label(base), "youtube.jpg", (1280, 720))


if __name__ == "__main__":
    main()

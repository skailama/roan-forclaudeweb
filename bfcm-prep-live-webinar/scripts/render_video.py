"""Trim the Zoom recording and blur the redaction regions, in one encode.

Usage: python3 -I scripts/render_video.py <source.mp4> <redactions.json> <out.mp4> <start_s> <end_s> [preview_from preview_len]

With preview_from/preview_len (seconds on the trimmed timeline) it renders only that
stretch, to check the blur before a full render.

redactions.json is a list of {"t0", "t1", "x", "y", "w", "h"} on the trimmed
timeline, in video pixels. Frames are decoded by ffmpeg, blurred here with
Pillow (on the raw YUV planes, so no colour conversion), and piped back to ffmpeg, which also trims and fades the audio.
"""
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageFilter

FPS = 25


def probe(src):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height", "-of", "csv=p=0", src],
                         capture_output=True, text=True, check=True).stdout
    w, h = (int(v) for v in out.strip().split(","))
    return w, h


def blur_plane(plane, x, y, w, h, block):
    H, W = plane.shape
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x1 - x0 < 2 or y1 - y0 < 2:
        return
    crop = Image.fromarray(plane[y0:y1, x0:x1])
    cw, ch = crop.size
    # pixelate hard, then soften: unreadable, and looks like a blur rather than mosaic
    small = crop.resize((max(1, cw // block), max(1, ch // block)), Image.BOX)
    soft = small.resize((cw, ch), Image.BILINEAR).filter(ImageFilter.GaussianBlur(max(1, block // 4)))
    plane[y0:y1, x0:x1] = np.asarray(soft)


def blur(planes, x, y, w, h):
    """Blur a box in a yuv420p frame: full size on luma, half size on the two chroma planes."""
    yp, up, vp = planes
    blur_plane(yp, x, y, w, h, 12)
    for p in (up, vp):
        blur_plane(p, x // 2, y // 2, (w + 1) // 2, (h + 1) // 2, 6)


def main(src, regions_path, out, start, end, preview_from=None, preview_len=None):
    start, end = float(start), float(end)
    offset = 0.0
    if preview_from is not None:
        offset = float(preview_from)
        start, end = start + offset, start + offset + float(preview_len)
    dur = end - start
    regions = json.load(open(regions_path))
    W, H = probe(src)
    fade_out = dur - 1.0

    dec = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(start), "-i", src, "-t", str(dur),
                            "-map", "0:v:0", "-r", str(FPS), "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
                           stdout=subprocess.PIPE)
    enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y",
                            "-f", "rawvideo", "-pix_fmt", "yuv420p", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                            "-ss", str(start), "-t", str(dur), "-i", src,
                            "-map", "0:v:0", "-map", "1:a:0", "-map_chapters", "-1", "-map_metadata", "-1",
                            "-metadata", "title=BFCM Prep Live: The First Black Friday of the AI Era",
                            "-vf", f"fade=t=in:st=0:d=0.5,fade=t=out:st={fade_out}:d=1",
                            "-af", f"afade=t=in:st=0:d=0.5,afade=t=out:st={fade_out}:d=1",
                            "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-tune", "stillimage",
                            "-pix_fmt", "yuv420p", "-g", "50",
                            "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-movflags", "+faststart", out],
                           stdin=subprocess.PIPE)

    ysz, csz = W * H, (W // 2) * (H // 2)
    size = ysz + 2 * csz
    buf = bytearray(size)
    regions.sort(key=lambda r: r["t0"])
    i = blurred = 0
    while True:
        n = dec.stdout.readinto(buf)
        if not n:
            break
        while n < size:  # pipe reads can come back short
            m = dec.stdout.readinto(memoryview(buf)[n:])
            if not m:
                break
            n += m
        if n < size:
            break
        t = offset + i / FPS
        active = [r for r in regions if r["t0"] <= t < r["t1"]]
        if active:
            frame = np.frombuffer(buf, dtype=np.uint8).copy()
            planes = (frame[:ysz].reshape(H, W),
                      frame[ysz:ysz + csz].reshape(H // 2, W // 2),
                      frame[ysz + csz:].reshape(H // 2, W // 2))
            for r in active:
                blur(planes, round(r["x"]), round(r["y"]), round(r["w"]), round(r["h"]))
            enc.stdin.write(frame.tobytes())
            blurred += 1
        else:
            enc.stdin.write(buf)
        i += 1
        if i % (FPS * 300) == 0:
            print(f"{i // FPS // 60} min rendered", flush=True)
    enc.stdin.close()
    enc.wait()
    dec.wait()
    print(f"{i} frames, {blurred} with blur -> {out}")
    sys.exit(enc.returncode)


if __name__ == "__main__":
    main(*sys.argv[1:])

"""OCR chosen moments of a video with Tesseract, 4 frames at a time.

Usage: python3 -I scripts/ocr_frames.py <video> <out_dir> <start:end:step> [...]
  e.g. 270:1190:10  2500:2980:0.5

Each frame is upscaled 2x so tab-bar text is readable; Tesseract's TSV
(coordinates in 2x pixels) lands in <out_dir>/<milliseconds>.tsv. Frames already
done are skipped, so it can be re-run with finer ranges.
"""
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def times(spec):
    a, b, step = (float(x) for x in spec.split(":"))
    t = a
    while t <= b + 1e-9:
        yield round(t, 3)
        t += step


def ocr(video, out, t):
    dst = out / f"{round(t * 1000):08d}.tsv"
    if dst.exists():
        return
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "f.png"
        subprocess.run(["ffmpeg", "-v", "error", "-ss", str(t), "-i", video, "-frames:v", "1",
                        "-vf", "scale=iw*2:ih*2:flags=lanczos", "-update", "1", str(png)], check=True)
        subprocess.run(["tesseract", str(png), str(Path(tmp) / "o"), "--psm", "11", "tsv"],
                       check=True, capture_output=True, env={**os.environ, "OMP_THREAD_LIMIT": "1"})
        (Path(tmp) / "o.tsv").replace(dst)


def main(video, out, *specs):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    ts = sorted({t for s in specs for t in times(s)})
    done = 0
    with ThreadPoolExecutor(4) as pool:
        for _ in pool.map(lambda t: ocr(video, out, t), ts):
            done += 1
            if done % 100 == 0:
                print(f"{done}/{len(ts)}", flush=True)
    print(f"done {len(ts)}")


if __name__ == "__main__":
    main(*sys.argv[1:])

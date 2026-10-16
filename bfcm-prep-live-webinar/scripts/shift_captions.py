"""Shift Zoom's caption file onto the trimmed timeline for YouTube.

Usage: python3 -I scripts/shift_captions.py <in.vtt> <out.srt> <start_s> <end_s>
Cues that fall outside [start, end] are dropped; ones that straddle a cut are clipped.
"""
import re
import sys


def secs(ts):
    h, m, s = ts.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def srt_ts(t):
    ms = round(t * 1000)
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def main(src, dst, start, end):
    cues = []
    for block in open(src, encoding="utf-8").read().strip().split("\n\n"):
        lines = block.splitlines()
        timing = next((i for i, l in enumerate(lines) if "-->" in l), None)
        if timing is None:
            continue
        a, b = (secs(x.strip().split()[0]) for x in lines[timing].split("-->"))
        if b <= start or a >= end:
            continue
        text = "\n".join(lines[timing + 1:]).strip()
        if text:
            cues.append((max(a, start) - start, min(b, end) - start, text))
    with open(dst, "w", encoding="utf-8") as f:
        for i, (a, b, text) in enumerate(cues, 1):
            f.write(f"{i}\n{srt_ts(a)} --> {srt_ts(b)}\n{text}\n\n")
    print(f"{len(cues)} cues -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]))

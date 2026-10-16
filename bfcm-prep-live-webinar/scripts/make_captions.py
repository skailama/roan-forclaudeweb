"""Short, well-timed captions: Zoom's corrected words on Whisper's word timings.

Usage: python3 -I scripts/make_captions.py <zoom_shifted.srt> <whisper_words.json> <out.srt>

<zoom_shifted.srt> is Zoom's captions on the trimmed timeline (scripts/shift_captions.py);
its mishearings are fixed with the list in clean_captions.py. <whisper_words.json> is
[{"w", "s", "e"}, ...] from Whisper with word timestamps, run on the trimmed audio.
Zoom's text is better (names, numbers), Whisper's timing is better (Zoom's cues run
up to 30 s), so each Zoom word takes the time of the Whisper word it lines up with.

Captions are one line of at most 42 characters: the text is cut into phrases at
sentence ends, commas and pauses, each phrase into evenly sized lines (no lone word
left on a line), and captions too brief to read are merged into a neighbour.
"""
import difflib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from clean_captions import fix, secs, srt_ts  # noqa: E402

MAX_CHARS = 42
MIN_DUR, MAX_DUR = 1.0, 6.0
PAUSE = 0.6          # a gap this long between words ends a caption
LEAD_OUT = 0.25      # keep a caption up a moment after its last word


def norm(w):
    return re.sub(r"[^a-z0-9]", "", w.lower())


def zoom_words(path):
    """[(word, cue_start, cue_end)] with the cue's time window, mishearings fixed."""
    out = []
    for block in open(path, encoding="utf-8").read().strip().split("\n\n"):
        lines = block.splitlines()
        a, b = (secs(x.strip()) for x in lines[1].split("-->"))
        for w in fix(" ".join(lines[2:])).split():
            out.append([w, a, b])
    return out


def align(zw, ww):
    """Give each Zoom word a (start, end), matching Whisper words near its cue."""
    times = [None] * len(zw)
    # align cue by cue, against the Whisper words that fall around that cue
    i = 0
    while i < len(zw):
        a, b = zw[i][1], zw[i][2]
        j = i
        while j < len(zw) and zw[j][1] == a:
            j += 1
        near = [k for k, w in enumerate(ww) if a - 2.0 <= w["s"] <= b + 2.0]
        za = [norm(zw[k][0]) for k in range(i, j)]
        wa = [norm(ww[k]["w"]) for k in near]
        sm = difflib.SequenceMatcher(None, za, wa, autojunk=False)
        for blk in sm.get_matching_blocks():
            for d in range(blk.size):
                w = ww[near[blk.b + d]]
                times[i + blk.a + d] = (w["s"], w["e"])
        i = j
    matched = sum(1 for t in times if t)
    # words Whisper didn't match: spread them between the matched words around them
    known = [k for k, t in enumerate(times) if t]
    for k in range(len(zw)):
        if times[k]:
            continue
        prev = max((p for p in known if p < k), default=None)
        nxt = min((n for n in known if n > k), default=None)
        lo = times[prev][1] if prev is not None and zw[prev][1] == zw[k][1] else zw[k][1]
        hi = times[nxt][0] if nxt is not None and zw[nxt][1] == zw[k][1] else zw[k][2]
        p0 = prev if prev is not None and zw[prev][1] == zw[k][1] else k - 1
        n0 = nxt if nxt is not None and zw[nxt][1] == zw[k][1] else k + 1
        span = max(1, n0 - p0)
        t = lo + (hi - lo) * (k - p0) / span
        times[k] = (t, t + max(0.15, (hi - lo) / span))
    # keep time moving forward
    for k in range(1, len(times)):
        if times[k][0] < times[k - 1][0]:
            times[k] = (times[k - 1][0], max(times[k][1], times[k - 1][0] + 0.1))
    return times, matched


def phrases(zw, times):
    """Split the word stream at sentence ends, commas, pauses, and a duration cap."""
    out, cur = [], []
    for k in range(len(zw)):
        if cur:
            text = " ".join(zw[c][0] for c in cur)
            gap = times[k][0] - times[cur[-1]][1]
            sentence = re.search(r"[.?!…]$", text) and len(text) >= 12
            clause = re.search(r"[,;:]$", text) and len(text) >= 18
            if sentence or clause or gap > PAUSE or times[k][1] - times[cur[0]][0] > 2 * MAX_DUR:
                out.append(cur)
                cur = []
        cur.append(k)
    if cur:
        out.append(cur)
    return out


def balanced(zw, words):
    """Split one phrase into as few lines as fit MAX_CHARS, of roughly equal length,
    so no line is a lone word left over."""
    text = " ".join(zw[k][0] for k in words)
    n = -(-len(text) // MAX_CHARS)
    while True:
        target = len(text) / n
        lines, cur, ok = [], [], True
        for k in words:
            cand = " ".join(zw[c][0] for c in cur + [k])
            if cur and (len(cand) > MAX_CHARS or (len(cand) > target + 6 and len(lines) < n - 1)):
                lines.append(cur)
                cur = []
            cur.append(k)
        lines.append(cur)
        if all(len(" ".join(zw[c][0] for c in l)) <= MAX_CHARS for l in lines) or n > 20:
            return lines
        n += 1


def captions(zw, times):
    caps = []
    for ph in phrases(zw, times):
        for line in balanced(zw, ph):
            caps.append([times[line[0]][0], times[line[-1]][1], " ".join(zw[k][0] for k in line)])
    # merge captions too brief to read into a neighbour, when the two fit on one line
    merged = []
    for c in caps:
        if merged:
            p = merged[-1]
            short = (p[1] - p[0] < MIN_DUR) or (c[1] - c[0] < MIN_DUR)
            if short and len(p[2]) + 1 + len(c[2]) <= MAX_CHARS and c[0] - p[1] <= PAUSE:
                p[1], p[2] = c[1], p[2] + " " + c[2]
                continue
        merged.append(c)
    caps = merged
    # timing: a little lead-out, at least MIN_DUR on screen, never overlapping the next
    for i, c in enumerate(caps):
        nxt = caps[i + 1][0] if i + 1 < len(caps) else c[1] + 2
        c[1] = min(max(c[1] + LEAD_OUT, c[0] + MIN_DUR), nxt - 0.02)
        c[1] = max(c[1], c[0] + 0.3)
    return caps


def main(zoom_srt, whisper_json, out):
    zw = zoom_words(zoom_srt)
    ww = json.load(open(whisper_json))
    times, matched = align(zw, ww)
    caps = captions(zw, times)
    with open(out, "w", encoding="utf-8") as f:
        for i, (a, b, text) in enumerate(caps, 1):
            f.write(f"{i}\n{srt_ts(a)} --> {srt_ts(b)}\n{text}\n\n")
    print(f"{len(zw)} words ({matched / len(zw):.0%} timed by Whisper), {len(caps)} captions, longest {max(len(c[2]) for c in caps)} chars -> {out}")


if __name__ == "__main__":
    main(*sys.argv[1:])

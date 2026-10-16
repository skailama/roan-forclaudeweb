"""Fix Zoom's mishearings and split its long caption blocks into readable ones.

Usage: python3 -I scripts/clean_captions.py <in.srt> <out.srt>

Zoom's cues run up to 30 seconds and 500+ characters, which YouTube shows as a
wall of text. Each cue is split at sentence or clause breaks into chunks of at
most two 42-character lines, with the cue's time shared out by length.
"""
import re
import sys
import textwrap

LINE = 42
MAX_CHARS = 2 * LINE

# (pattern, replacement), applied in order. Words Zoom misheard, checked against
# the slides and the speaker transcript; spoken slips are left alone.
FIXES = [
    (r"\bsales switches\b", "sales pitches"),
    (r"\boffice strateg", "offer strateg"),
    (r"\blay of the line\b", "lay of the land"),
    (r"\bPsychic\b", "Sidekick"),
    (r"\bsidekick\b", "Sidekick"),
    (r"\bfor sort of sales\b", "four sort of sales"),
    (r"\bdone Offer September\b", "done offers in September"),
    (r"\bAO[EB]\b|\bAob\b", "AOV"),
    (r"\breal debt\b", "real depth"),
    (r"\bstagged\b", "stacked"),
    (r"AI skill that you're going to send you", "AI skill that we're going to send you"),
    (r"\bstats and starter bundles\b", "sets and starter bundles"),
    (r"\bexclusive setup price promise\b", "exclusive set, a price promise"),
    (r"\bSiddha\b", "Sid"),
    (r"percentage of, prior, you just", "percentage off? Right? You just"),
    (r"\bIn about 13 or 16 stores\b", "In about 13 of 16 stores"),
    (r"very first easy S very", "very first easy yes. Very"),
    (r"\bPlans on your homepage\b", "Lands on your homepage"),
    (r"\$18,000 a month", "18,000 orders a month"),
    (r"\$1,300 orders", "1,300 orders"),
    (r"buying just the 3 states", "buying just the 3-pack"),
    (r"\bquality breaks\b", "quantity breaks"),
    (r"\ban NEMCP\b", "an MCP"),
    (r"\bdifferent sense\b", "different scents"),
    (r"\bStent designs\b", "10 designs"),
    (r"\ba triode, duo\b", "a trio, duo"),
    (r"\bSo I'll get your running ads\b", "So they're running ads"),
    (r"\bjust one picture\b", "just one pager"),
    (r"\bthe funding section\b", "the bundling section"),
    (r"\bLlms\b", "LLMs"),
    (r"\bLlm\b", "LLM"),
    (r"Route A the other web route A via", "Route A via the web, Route B via"),
    (r"\byour root be is\b", "your Route B is"),
    (r"\bselect best hot sale\b", "select best hot sauce"),
    (r"\bships to yours or Canada\b", "ships to US or Canada"),
    (r"\ball of these AI chats\b", "all of these AI channels"),
    (r"\bwhat agents need\b", "what agents read"),
    (r"\bHow do you face that\b", "How do you fix that"),
    (r"\bBest for blown sauce\b", "Best poblano sauce"),
    (r"\bCompetitive answers\b", "Competitor analysis"),
    (r"\bthis source will be used\b", "this sauce will be used"),
    (r"\ba source for\b", "a sauce for"),
    (r"\bbefore BFC\b", "before BFCM"),
    (r"\btail promos\b", "stale promos"),
    (r"\bcovered bug link\b", "covered bundling"),
    (r"\bNitiqa\b", "Neetika"),
    (r"\bor sit at skylama\.com\b", "neetika@skailama.com or sid@skailama.com"),
]


def secs(ts):
    h, m, rest = ts.split(":")
    s, ms = rest.split(",")
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def srt_ts(t):
    ms = round(t * 1000)
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def fix(text):
    for pat, rep in FIXES:
        text = re.sub(pat, rep, text)
    return text


def chunks(text):
    """Split into pieces of <= MAX_CHARS, preferring sentence, then clause, then word breaks."""
    out, rest = [], text.strip()
    while len(textwrap.wrap(rest, LINE)) > 2:
        window = rest[: MAX_CHARS + 1]
        cut = -1
        for pat in (r"[.?!…]\s", r"[,;:]\s", r"\s"):
            hits = [m.end() for m in re.finditer(pat, window) if m.end() >= MAX_CHARS * 0.4]
            if hits:
                cut = hits[-1]
                break
        if cut <= 0:
            cut = MAX_CHARS
        # word wrapping can push a full-length chunk onto a third line; back off a word
        while len(textwrap.wrap(rest[:cut], LINE)) > 2:
            cut = rest.rfind(" ", 0, cut - 1) + 1
        out.append(rest[:cut].strip())
        rest = rest[cut:].strip()
    if rest:
        out.append(rest)
    return out


def main(src, dst):
    blocks = open(src, encoding="utf-8").read().strip().split("\n\n")
    cues = []
    for block in blocks:
        lines = block.splitlines()
        a, b = (secs(x.strip()) for x in lines[1].split("-->"))
        text = fix(" ".join(lines[2:]))
        parts = chunks(text)
        total = sum(len(p) for p in parts)
        t = a
        for p in parts:
            d = (b - a) * len(p) / total
            cues.append((t, t + d, "\n".join(textwrap.wrap(p, LINE))))
            t += d
    with open(dst, "w", encoding="utf-8") as f:
        for i, (a, b, text) in enumerate(cues, 1):
            f.write(f"{i}\n{srt_ts(a)} --> {srt_ts(b)}\n{text}\n\n")
    longest = max(b - a for a, b, _ in cues)
    print(f"{len(blocks)} cues in, {len(cues)} out; longest {longest:.1f}s -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

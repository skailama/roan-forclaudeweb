"""Turn OCR of the trimmed video into blur regions that hide the demo store.

Usage: python3 -I scripts/find_redactions.py <ocr_dir> <out.json>

<ocr_dir> holds <milliseconds>.tsv files from scripts/ocr_frames.py. Each
frame's regions cover the time from halfway to the previous sample until
halfway to the next one, and identical boxes in neighbouring samples merge.

What gets blurred (video pixels): names and photos, not the text around them.
  - the store's name wherever it's read ("Gindos", "Gindo's", OCR slips like "Glndo"),
    including the handle inside the admin URL, and the collaboration that names it
    ("2 Fools Apple Sauced")
  - the store switcher, bottom left of the admin
  - lists that are only the store's product names, and product photos with its label:
      Product readiness   the product list
      Agent lens          the photo on the store's own result card
      Optimize prompts    the product list, and the photo in the modal
      Catalog mapping     the photo in the product preview
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ocr_lines import lines  # noqa: E402

NAME = re.compile(r"g[il1|][nm]d[o0]|[il1]nd[o0]['’]?s\b|gindos?", re.I)
# Names to blur wherever they appear in running text: the store ("Gindo's", the
# handle "gindos" inside the URL), and the collaboration product that names it
# ("2 Fools Apple Sauced", "2 Fools Cider").
NAMES = [
    re.compile(r"[^\s/]*(?:" + NAME.pattern + r")[^\s/]*", re.I),
    re.compile(r"\b2\s*Fools(\s+(Apple\s+Sauced|Cider|Pinehopple))?\b", re.I),
    re.compile(r"\bApple\s+Sauced\b", re.I),
]
PAD_X, PAD_Y = 3, 5
VIDEO_W, VIDEO_H = 1986, 1050
TAB = [423, 10, 50, 22]   # "Gindos" in the browser tab; the tab never moves while Neetika shares

try:  # proportional-font widths, to place a name inside a longer token (the URL)
    from PIL import ImageFont
    _FONT = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-Regular.otf", 40)
    text_width = _FONT.getlength
except Exception:  # no Pillow/font: fall back to equal-width characters
    text_width = len


def box(x, y, w, h, pad_x=PAD_X, pad_y=PAD_Y):
    return [x - pad_x, y - pad_y, w + 2 * pad_x, h + 2 * pad_y]


def find(ls, pattern, x_min=0, x_max=VIDEO_W, y_min=0, y_max=VIDEO_H):
    rx = re.compile(pattern, re.I)
    return [l for l in ls if rx.search(l["text"]) and x_min <= l["x"] <= x_max and y_min <= l["y"] <= y_max]


def name_boxes(line):
    """Boxes around just the names in a line. A match inside a longer token (the store
    handle in the URL) gets its share of that token's width, padded for the estimate."""
    words, spans, text = line["words"], [], ""
    for w in words:
        a = len(text) + (1 if text else 0)
        text += (" " if text else "") + w["text"]
        spans.append((a, a + len(w["text"])))
    out = []
    for rx in NAMES:
        for m in rx.finditer(text):
            s, e = m.span()
            for w, (a, b) in zip(words, spans):
                if a >= e or b <= s:
                    continue
                token = w["text"]
                i0, i1 = max(0, s - a), min(len(token), e - a)
                partial = i0 > 0 or i1 < len(token)
                full = text_width(token) or 1
                x0 = w["x"] + w["w"] * text_width(token[:i0]) / full
                x1 = w["x"] + w["w"] * text_width(token[:i1]) / full
                out.append(box(x0, w["y"], x1 - x0, w["h"], pad_x=6 if partial else PAD_X))
    return out


def regions_for(ls):
    out = []
    admin = find(ls, r"admin\.shopify\.com", y_max=90)

    # 1. the store's name, and names that point to it, wherever they're read: the tab,
    #    the URL's store handle, search terms, vendor labels, product copy
    for l in ls:
        out += name_boxes(l)

    # 1b. agentic overview: the first two "recent searches" start with the store's name.
    #     OCR loses those words mid-scroll but keeps the heading, so blur by position too.
    for h in find(ls, r"Recent searches where", x_min=540, x_max=600):
        out.append([597, h["y"] + 28, 50, 22])
        out.append([597, h["y"] + 72, 50, 22])

    # 2. store switcher, bottom left of the admin (avatar + name)
    if admin:
        out.append([44, 1004, 100, 34])

    header = " ".join(l["text"] for l in ls if 260 <= l["x"] <= 700 and 95 <= l["y"] <= 140)
    url = " ".join(l["text"] for l in admin)
    page = lambda heading, path: re.search(heading, header, re.I) or (path and re.search(path, url))

    # 3. product readiness: the product list is nothing but the store's product names
    if page(r"Product readiness", r"product-readiness"):
        ui = re.compile(r"^\W{0,3}\s*(Current|Suggested|As of the last|Categ|Clateg|Description|Descriptiqn|"
                        r"Empty desc|Hide products|In the first|No\b|Product (checks|readiness)|Re-analyze|"
                        r"Review|Sh[oq]w \d|Top-level|taxonomy|.*products? (were|was)|.*Restoring|\d+$|gory)", re.I)
        for l in ls:
            if 295 <= l["x"] <= 330 and l["y"] > 140 and len(l["text"]) >= 6 and not ui.match(l["text"]):
                out.append(box(l["x"], l["y"], max(l["w"], 520), l["h"]))

    # 4. agent lens: the store's own result card shows its label on the bottle; blur the photo
    if page(r"Agent lens", r"agent-lens"):
        for v in find(ls, r"\(You\)", x_min=500):
            out.append([v["x"] - 18, v["y"] - 262, 270, 252])

    # 5. optimize for prompts: the product list (names + thumbnails) and the product photo
    modal_title = find(ls, r"^Optimize\s*[-·.]", x_min=480, x_max=520, y_max=260)
    if page(r"Optimize", r"/app/products") or modal_title:
        list_w = 188 if modal_title else 440   # names end before "Product health"; the modal covers the list from x=483
        out.append([294, 290, list_w, VIDEO_H - 290])
        for a in find([l for l in ls if 500 <= l["x"] <= 530], r"^Images$"):
            out.append([510, a["y"] + 30, 120, 105])

    # 6. catalog mapping: the product photo (and its thumbnail) in the preview panel
    if page(r"Catalog Mapping", r"_ps=1"):
        for p in find(ls, r"^Preview$", x_min=1380, x_max=1440, y_max=420):
            out.append([1364, p["y"] + 66, 32, 40])
            out.append([1350, p["y"] + 124, 100, 98])

    return [[round(v) for v in r] for r in out]


def same(a, b, tol=12):
    return all(abs(p - q) <= tol for p, q in zip(a, b))


def main(ocr_dir, out_path):
    files = sorted(Path(ocr_dir).glob("[0-9]*.tsv"))
    ts = [int(f.stem) / 1000 for f in files]
    open_regions, done = [], []
    for i, (f, t) in enumerate(zip(files, ts)):
        lo = (ts[i - 1] + t) / 2 if i else t - 0.5
        hi = (t + ts[i + 1]) / 2 if i + 1 < len(ts) else t + 0.5
        # a long gap between samples means we know nothing there; cap the reach
        lo, hi = max(lo, t - 2.5), min(hi, t + 2.5)
        boxes = regions_for(lines(f))
        still = []
        for r in open_regions:
            match = next((b for b in boxes if same(r["box"], b)), None)
            if match is not None and abs(r["t1"] - lo) < 1e-6:
                r["t1"] = hi
                r["box"] = [min(r["box"][0], match[0]), min(r["box"][1], match[1]),
                            max(r["box"][0] + r["box"][2], match[0] + match[2]) - min(r["box"][0], match[0]),
                            max(r["box"][1] + r["box"][3], match[1] + match[3]) - min(r["box"][1], match[1])]
                boxes.remove(match)
                still.append(r)
            else:
                done.append(r)
        for b in boxes:
            still.append({"t0": lo, "t1": hi, "box": b})
        open_regions = still
    done += open_regions
    # The browser tab naming the store sits in the same place for as long as Neetika's
    # window is shared; blur it end to end so a missed OCR sample can't leave a gap.
    tabs = [r for r in done if r["box"][1] < 35]
    done = [r for r in done if r["box"][1] >= 35]
    if tabs:
        done.append({"t0": min(r["t0"] for r in tabs), "t1": max(r["t1"] for r in tabs), "box": TAB})
    # a little slack either side: over-blurring for a tenth of a second is harmless
    out = [{"t0": round(r["t0"] - 0.1, 3), "t1": round(r["t1"] + 0.1, 3),
            "x": r["box"][0], "y": r["box"][1], "w": r["box"][2], "h": r["box"][3]} for r in done]
    out.sort(key=lambda r: (r["t0"], r["y"], r["x"]))
    json.dump(out, open(out_path, "w"), indent=0)
    print(f"{len(files)} frames -> {len(out)} regions -> {out_path}")


if __name__ == "__main__":
    main(*sys.argv[1:])

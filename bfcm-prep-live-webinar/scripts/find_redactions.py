"""Turn OCR of the trimmed video into blur regions that hide the demo store.

Usage: python3 -I scripts/find_redactions.py <ocr_dir> <out.json>

<ocr_dir> holds <milliseconds>.tsv files from scripts/ocr_frames.py. Each
frame's regions cover the time from halfway to the previous sample until
halfway to the next one, and identical boxes in neighbouring samples merge.

What gets blurred (video pixels):
  - any line mentioning the store ("Gindos", "Gindo's", OCR slips like "Glndo"), and
    the first rows of "Recent searches where your products appeared" (branded queries)
  - the Shopify admin URL (it carries the store handle) and the store switcher
  - on the store's own pages, its product names, photos and copy:
      Product readiness   product titles above each "Current:" line
      Agent lens          result cards sold by "(You)"
      Optimize prompts    product list rows, and the modal's title, fields,
                          image and AI suggestions
      Catalog mapping     the product preview panel
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ocr_lines import lines  # noqa: E402

NAME = re.compile(r"g[il1|][nm]d[o0]|[il1]nd[o0]['’]?s\b|gindos?", re.I)
PAD_X, PAD_Y = 8, 6
VIDEO_W, VIDEO_H = 1986, 1050


def box(x, y, w, h, pad_x=PAD_X, pad_y=PAD_Y):
    return [x - pad_x, y - pad_y, w + 2 * pad_x, h + 2 * pad_y]


def find(ls, pattern, x_min=0, x_max=VIDEO_W, y_min=0, y_max=VIDEO_H):
    rx = re.compile(pattern, re.I)
    return [l for l in ls if rx.search(l["text"]) and x_min <= l["x"] <= x_max and y_min <= l["y"] <= y_max]


def regions_for(ls):
    out = []
    admin = find(ls, r"admin\.shopify\.com", y_max=90)

    # 1. anything naming the store
    for l in ls:
        if not NAME.search(l["text"]):
            continue
        if l["y"] < 35:
            # browser tab: blur that tab's title only, not its neighbour
            w = next((w for w in l["words"] if NAME.search(w["text"])), l)
            out.append(box(w["x"] - 22, w["y"], 225, w["h"]))
        else:
            out.append(box(l["x"], l["y"], l["w"], l["h"]))

    # 1b. agentic overview: the top "recent searches" rows are the store's branded queries;
    #     anchor on the heading, which OCR still reads mid-scroll when the rows blur
    for h in find(ls, r"Recent searches where", x_min=540, x_max=600):
        out.append([560, h["y"] + 22, 460, 88])

    # 2. admin chrome: URL bar text, store switcher (avatar + name)
    for l in admin:
        out.append(box(l["x"], l["y"], 1440 - l["x"], l["h"], pad_y=8))
    if admin:
        out.append([44, 1004, 100, 34])

    header = " ".join(l["text"] for l in ls if 260 <= l["x"] <= 700 and 95 <= l["y"] <= 140)
    url = " ".join(l["text"] for l in admin)
    page = lambda heading, path: re.search(heading, header, re.I) or (path and re.search(path, url))

    # 3. product readiness: every product title in the list (UI text in that column is known)
    if page(r"Product readiness", r"product-readiness"):
        ui = re.compile(r"^\W{0,3}\s*(Current|Suggested|As of the last|Categ|Clateg|Description|Descriptiqn|"
                        r"Empty desc|Hide products|In the first|No\b|Product (checks|readiness)|Re-analyze|"
                        r"Review|Sh[oq]w \d|Top-level|taxonomy|.*products? (were|was)|.*Restoring|\d+$|gory)", re.I)
        for l in ls:
            if 295 <= l["x"] <= 330 and l["y"] > 140 and len(l["text"]) >= 6 and not ui.match(l["text"]):
                out.append(box(l["x"], l["y"], max(l["w"], 520), l["h"]))

    # 4. agent lens: result cards sold by the store ("Gindos (You)" as the vendor)
    if page(r"Agent lens", r"agent-lens"):
        for v in find(ls, r"\(You\)", x_min=500):
            out.append([v["x"] - 18, v["y"] - 285, 270, 345])

    # 5. optimize for prompts: the product list (names + thumbnails) and the modal contents
    modal_title = find(ls, r"^Optimize\s*[-·.]", x_min=480, x_max=520, y_max=260)
    if page(r"Optimize", r"/app/products") or modal_title:
        list_w = 188 if modal_title else 440   # names end before "Product health"; the modal covers the list from x=483
        out.append([294, 290, list_w, VIDEO_H - 290])
        for t in modal_title:
            out.append(box(t["x"], t["y"], 900, t["h"]))
        modal = [l for l in ls if 500 <= l["x"] <= 1450]
        for a in find(modal, r"^Title$", x_max=530):
            out.append([510, a["y"] + 14, 920, 42])
        for a in find(modal, r"^Description$", x_max=530):
            out.append([510, a["y"] + 14, 920, 104])
        for a in find(modal, r"^Images$", x_max=530):
            out.append([510, a["y"] + 30, 120, 105])
        for a in find(modal, r"^Suggested title", x_max=545):
            out.append([522, a["y"] + 16, 900, 32])
        for a in find(modal, r"^Suggested description", x_max=545):
            end = [b for b in find(modal, r"^Apply to description") if b["y"] > a["y"]]
            bottom = min(b["y"] for b in end) - 6 if end else a["y"] + 200
            out.append([522, a["y"] + 16, 900, bottom - a["y"] - 16])

        # fallbacks keyed on the buttons, for frames where OCR misses the "Suggested ..." labels
        for b in find(modal, r"^Apply to title", x_max=545):
            out.append([522, b["y"] - 40, 900, 34])
        for b in find(modal, r"^Apply to desc", x_max=545):
            top = max([t["y"] + 30 for t in find(modal, r"^Apply to title", x_max=545) if t["y"] < b["y"]] or [b["y"] - 160])
            out.append([522, top, 900, b["y"] - 6 - top])

        # any other long line of product copy in the modal body (the AI suggestions, the
        # description field); OCR often can't read the dark "Apply to ..." buttons or the labels
        ui_modal = re.compile(r"^\W{0,3}\s*(Product (health|details)|OK on|This checks|above\.|Run a buyer|kun a buyer|"
                              r"Suggestions are|Live top|None of your|What to fix|Prompt checker|Lead with|ead with|"
                              r"Agents summar|View-only|Images|Title|Description|Suggested|Apply to|best\b)", re.I)
        for l in modal:
            bullet = re.match(r"^[e*«¢•·]\s", l["text"])   # "What to fix" advice stays readable
            if 520 <= l["x"] <= 540 and l["w"] >= 200 and not ui_modal.match(l["text"]) and not bullet:
                out.append([516, l["y"] - 5, 910, l["h"] + 10])

    # 6. catalog mapping: the preview of one of the store's products
    if page(r"Catalog Mapping", r"_ps=1"):
        out.append([1350, 330, 295, VIDEO_H - 330])

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
    if tabs:
        x0 = min(r["box"][0] for r in tabs); x1 = max(r["box"][0] + r["box"][2] for r in tabs)
        y0 = min(r["box"][1] for r in tabs); y1 = max(r["box"][1] + r["box"][3] for r in tabs)
        done.append({"t0": min(r["t0"] for r in tabs), "t1": max(r["t1"] for r in tabs),
                     "box": [x0, y0, x1 - x0, y1 - y0]})
    # a little slack either side: over-blurring for a tenth of a second is harmless
    out = [{"t0": round(r["t0"] - 0.1, 3), "t1": round(r["t1"] + 0.1, 3),
            "x": r["box"][0], "y": r["box"][1], "w": r["box"][2], "h": r["box"][3]} for r in done]
    out.sort(key=lambda r: (r["t0"], r["y"], r["x"]))
    json.dump(out, open(out_path, "w"), indent=0)
    print(f"{len(files)} frames -> {len(out)} regions -> {out_path}")


if __name__ == "__main__":
    main(*sys.argv[1:])

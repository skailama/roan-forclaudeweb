"""Group Tesseract TSV words into text lines (video pixels, i.e. OCR coords / 2)."""
import csv


def words(path, scale=0.5):
    out = []
    with open(path, newline="", encoding="utf-8", errors="replace") as f:
        for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            text = (r.get("text") or "").strip()
            if not text or r["level"] != "5" or float(r["conf"]) < 0:
                continue
            x, y, w, h = (int(r[k]) * scale for k in ("left", "top", "width", "height"))
            out.append({"x": x, "y": y, "w": w, "h": h, "text": text})
    return out


def lines(path, gap=30, tol=6):
    """Words whose vertical centres are within `tol` px, and no more than `gap` px apart, form one line."""
    ws = sorted(words(path), key=lambda w: w["y"] + w["h"] / 2)
    bands, band = [], []
    for w in ws:
        cy = w["y"] + w["h"] / 2
        if band and cy - (band[0]["y"] + band[0]["h"] / 2) > tol:
            bands.append(band)
            band = []
        band.append(w)
    if band:
        bands.append(band)
    out = []
    for band in bands:
        band.sort(key=lambda w: w["x"])
        row = [band[0]]
        for w in band[1:]:
            if w["x"] - max(r["x"] + r["w"] for r in row) > gap:
                out.append(_merge(row))
                row = []
            row.append(w)
        out.append(_merge(row))
    return sorted(out, key=lambda l: (l["y"], l["x"]))


def _merge(row):
    x0 = min(w["x"] for w in row); y0 = min(w["y"] for w in row)
    x1 = max(w["x"] + w["w"] for w in row); y1 = max(w["y"] + w["h"] for w in row)
    return {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "text": " ".join(w["text"] for w in row),
            "words": row}


if __name__ == "__main__":
    import sys
    for l in lines(sys.argv[1]):
        print(f'{l["x"]:5.0f} {l["y"]:5.0f} {l["w"]:5.0f} {l["h"]:3.0f}  {l["text"]}')

# BFCM Prep Live webinar: edit, chapters and thumbnails

Cleanup of the Zoom recording of **BFCM Prep Live** (15 Oct 2026, Sid and Neetika) for YouTube and the follow-up email.

| What | Where |
|---|---|
| Trimmed video, demo store blurred (55:28, 1986x1050, H.264/AAC) | `output/BFCM-Prep-Live-2026.mp4`, not in git (too big); sent in the session |
| Captions for YouTube | `output/BFCM-Prep-Live-2026.en.srt` |
| Title, description, chapters | `youtube.md` |
| Email thumbnail, play button only | `thumbnails/email-play.jpg` (1200x675) |
| Email thumbnail, play button + "BFCM Prep Live" label | `thumbnails/email-play-label.jpg` (1200x675) |
| YouTube thumbnail (label, no play button) | `thumbnails/youtube.jpg` (1280x720) |
| Every blurred area, with times | `redactions.json` |

## What was cut

Nothing in the middle. Only the two ends:

- **Start, 0:00 to 3:43.7.** Pre-show: mic checks ("Hey Dustin, hey Rick, can you hear us?") and waiting for people to join. The video now opens half a second before Sid's "All right, perfect. Welcome, everyone."
- **End, 59:11.5 to 59:26.** Silence after "Bye-bye" and the camera-off "Neetika M" tile.

Half-second fade in and one-second fade out, so neither cut is abrupt.

The whole trimmed video was scanned for silences over 4 seconds, black frames and frozen video, and the captions were read end to end. No internal talk or dead air in the middle. The only pause is about 8 seconds at 55:01, while Sid waits for questions.

## The demo store is blurred

The AEO demo runs in a real customer's Shopify admin. The store can't be recognised in the video: it still reads as "a hot sauce store", but nothing names it.

| Where | When (trimmed) | Blurred |
|---|---|---|
| Browser tab "Gindos · …" | 19:30 to 54:50, whenever Neetika's screen is shared | the tab's title |
| Shopify admin | 42:05 to 49:15, and 52:59 to 53:21 | the URL bar (it carries the store handle) and the store switcher, bottom left |
| Any line naming the store | same | "Gindos (You)", "Best-ranked product: Gindo's …" and so on |
| Agentic overview | 42:47 to 44:40 | the first two "Recent searches where your products appeared" rows ("gindo's hot sauce starter kit"…), anchored on the heading so they stay blurred mid-scroll |
| Product readiness | 44:47 to 46:00 | every product name in the list |
| Agent lens | 46:00 to 48:10 | the store's own result card (photo, name, price) |
| Optimize for prompts | 48:10 to 49:15, 52:59 to 53:02 | the product list, and in the modal the product's title, description, photo and the AI-suggested title and description. The "What to fix" advice stays readable |
| Catalog mapping | 44:00 to 44:37 | the product preview panel |

How it was found: Neetika's shared screen was OCR'd (every 5 s on slides; every 0.5 s in the admin, and every 0.1 s wherever the screen scrolled), and `scripts/find_redactions.py` turns the text into blur boxes, by page. The finished video was then OCR'd again at moments in between those samples, looking for the store name and its product names. The first check caught two leaks (a branded search row mid-scroll at 43:04, and the AI-suggested description at 48:50 to 49:05); both rules were fixed and the check re-run clean.

What stays: the app's own interface, the competitor results (Pepper Palace, Hatch Chile Store…, which are public), revenue and product counts, and Neetika saying "hot sauce" and "food and beverage".

## Rebuilding

Needs `ffmpeg`, `tesseract` and Python 3 with Pillow and NumPy. Source files go in `source/` (the Zoom export: `GMT20261015-165816_Recording_1986x1050.mp4` plus its `.cc.vtt` and `.transcript.vtt`).

```bash
mkdir -p work
SRC=source/GMT20261015-165816_Recording_1986x1050.mp4

# 1. a plain trim to OCR (same cut points as the final)
ffmpeg -ss 223.7 -i $SRC -t 3327.8 -map 0:v:0 -c:v libx264 -crf 20 -preset veryfast work/trim.mp4

# 2. OCR where the store can appear; then densify where the blur boxes change (see find_redactions.py)
python3 -I scripts/ocr_frames.py work/trim.mp4 work/ocr 1160:2500:5 2500:2980:0.5 2980:3300:5 3150:3230:0.5

# 3. blur boxes, then the final video: trim, blur, fade, encode in one pass
python3 -I scripts/find_redactions.py work/ocr redactions.json
python3 -I scripts/render_video.py $SRC redactions.json output/BFCM-Prep-Live-2026.mp4 223.7 3551.5
#    add "<from> <seconds>" to render just a stretch, e.g. "2520 60", to check the blur

# captions: shift onto the trimmed timeline, then fix mishearings and split long blocks
python3 -I scripts/shift_captions.py source/GMT20261015-165816_Recording.cc.vtt work/captions-raw.srt 223.7 3551.5
python3 -I scripts/clean_captions.py work/captions-raw.srt output/BFCM-Prep-Live-2026.en.srt

# thumbnails, from source/thumbnail-source.png (the store's tab is blurred there too)
python3 -I scripts/thumbnails.py
```

To move a cut, change `223.7` (start) or `3551.5` (end) everywhere above, re-run the OCR (blur times follow the trimmed timeline), then shift the chapter times in `youtube.md` by the same amount.

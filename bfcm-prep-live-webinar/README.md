# BFCM Prep Live webinar: edit, chapters and thumbnails

Cleanup of the Zoom recording of **BFCM Prep Live** (15 Oct 2026, Sid and Neetika) for YouTube and the follow-up email.

| What | Where |
|---|---|
| Trimmed video (55:28, 1986x1050, H.264/AAC) | `output/BFCM-Prep-Live-2026.mp4`, not in git. Download link in the PR / session |
| Captions for YouTube | `output/BFCM-Prep-Live-2026.en.srt` |
| Title, description, chapters | `youtube.md` |
| Email thumbnail, play button only | `thumbnails/email-play.jpg` (1200x675) |
| Email thumbnail, play button + "BFCM Prep Live" bar | `thumbnails/email-play-bar.jpg` (1200x675) |
| YouTube thumbnail (bar, no play button) | `thumbnails/youtube.jpg` (1280x720) |

## What was cut

Nothing in the middle. Only the two ends:

- **Start, 0:00 to 3:43.7.** Pre-show: mic checks ("Hey Dustin, hey Rick, can you hear us?") and waiting for people to join. The video now opens half a second before Sid's "All right, perfect. Welcome, everyone."
- **End, 59:11.5 to 59:26.** Silence after "Bye-bye" and the camera-off "Neetika M" tile.

Half-second fade in and one-second fade out, so neither cut is abrupt.

## Checked, nothing else to cut

The whole trimmed video was scanned for silences over 4 seconds, black frames and frozen video, and the captions were read end to end. No internal talk or dead air in the middle. The only pause is about 8 seconds at 55:01, while Sid waits for questions.

- **The live demo shows a real store's admin**, about 42:20 to 49:30: the store handle `gindos` is in the browser tab and URL, with its order badge (9,999+) and product-readiness counts. The slides' case studies were anonymised; this isn't. Blurring the tab and URL bar for that stretch is a small change if it's needed.
- Sid calls Neetika "Aditi" once (around 53:00). It's spoken, so it stays in the video; the captions leave the name out.

## Rebuilding

Needs `ffmpeg` and Python 3 with Pillow. Source files go in `source/` (the Zoom export: `GMT20261015-165816_Recording_1986x1050.mp4` plus its `.cc.vtt` and `.transcript.vtt`).

```bash
# video
ffmpeg -ss 223.7 -i source/GMT20261015-165816_Recording_1986x1050.mp4 -t 3327.8 \
  -map 0:v:0 -map 0:a:0 -map_chapters -1 -map_metadata -1 \
  -vf "fade=t=in:st=0:d=0.5,fade=t=out:st=3326.8:d=1" \
  -af "afade=t=in:st=0:d=0.5,afade=t=out:st=3326.8:d=1" \
  -c:v libx264 -preset medium -crf 20 -tune stillimage -pix_fmt yuv420p -r 25 -g 50 \
  -c:a aac -b:a 160k -ar 48000 -movflags +faststart output/BFCM-Prep-Live-2026.mp4

# captions: shift onto the trimmed timeline, then fix mishearings and split long blocks
mkdir -p work && python3 -I scripts/shift_captions.py source/GMT20261015-165816_Recording.cc.vtt \
  work/captions-raw.srt 223.7 3551.5
python3 -I scripts/clean_captions.py work/captions-raw.srt output/BFCM-Prep-Live-2026.en.srt

# thumbnails, from source/thumbnail-source.png
python3 -I scripts/thumbnails.py
```

To move a cut, change `223.7` (start) or `3551.5` (end) everywhere above, then shift the chapter times in `youtube.md` by the same amount.

#!/usr/bin/env bash
# Capture the scene and encode the animated listing image in every format we test.
#   ./encode.sh            -> frames/ + output/*
set -euo pipefail
cd "$(dirname "$0")"

FPS=25
NAME=kite-listing-5
OUT=output
mkdir -p "$OUT"

node scene/capture.mjs "$FPS" frames

# Frames are captured at 2x (3200x1800); listing slot is 1600x900.
SCALE="scale=1600:900:flags=lanczos"

# 1) APNG, true colour. A real PNG file (PNG signature + acTL/fcTL/fdAT chunks):
#    passes any "is this a PNG" upload check, animates in every modern browser.
ffmpeg -v error -y -framerate "$FPS" -i frames/f%04d.png -vf "$SCALE" \
  -pix_fmt rgb24 -plays 0 -f apng "$OUT/$NAME-animated.png"

# 2) APNG, 256-colour palette (much smaller, tiny banding on the photo gradient).
ffmpeg -v error -y -framerate "$FPS" -i frames/f%04d.png -filter_complex \
  "[0:v]$SCALE,split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -plays 0 -f apng "$OUT/$NAME-animated-lite.png"

# 3) Animated GIF (what the live Creativul-client listing actually serves),
#    plus the same bytes saved under a .png name.
ffmpeg -v error -y -framerate "$FPS" -i frames/f%04d.png -filter_complex \
  "[0:v]$SCALE,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -loop 0 "$OUT/$NAME-animated.gif"
cp "$OUT/$NAME-animated.gif" "$OUT/$NAME-animated-gif-renamed.png"

# 4) Static fallback = the untouched Figma export at listing size.
ffmpeg -v error -y -i source/frame-5@2x.png -vf "$SCALE" "$OUT/$NAME-static.png"

# 5) MP4 preview for sharing in Slack etc.
ffmpeg -v error -y -framerate "$FPS" -i frames/f%04d.png -vf "$SCALE" \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart "$OUT/$NAME-preview.mp4"

ls -la "$OUT"

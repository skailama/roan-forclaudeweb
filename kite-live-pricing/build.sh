#!/usr/bin/env bash
# Builds Kite's custom-discount-builder function to WebAssembly and inlines it into the demo page.
# Usage: ./build.sh /path/to/backend-discountAndGift-app7
set -euo pipefail
APP7=${1:?path to a backend-discountAndGift-app7 checkout}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
cp -r "$APP7/extensions/custom-discount-builder" "$WORK/"
rustup target add wasm32-wasip1 >/dev/null
(cd "$WORK/custom-discount-builder" && cargo build --release --target wasm32-wasip1)
WASM="$WORK/custom-discount-builder/target/wasm32-wasip1/release/consolidated-discounts-v2.wasm"
node "$HERE/engine/offers.test.mjs" "$WASM"
python3 - "$WASM" "$HERE/page/kite-live-pricing.src.html" "$HERE/dist/kite-live-pricing.html" <<'PY'
import sys, base64, gzip
wasm, src, out = sys.argv[1:]
w = open(wasm, 'rb').read()
s = open(src).read()
s = s.replace('__WASM_B64__', base64.b64encode(w).decode()).replace('__WASM_GZ_KB__', str(round(len(gzip.compress(w, 9)) / 1024)))
open(out, 'w').write(s)
print(f'wrote {out} ({len(w) // 1024} KB wasm)')
PY

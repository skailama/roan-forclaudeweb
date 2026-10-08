# Bundle builder — card swatches email image

Generic mock of a "Build Your Own Bundle" builder page for the
swatches-on-product-cards email. Layout follows a live bundle builder, but the
brand (Hearthly), products and photos are made up; the product art is
drawn as inline SVG.

Only one card's swatch row (Stoneware Mug) is highlighted, with a callout;
the other cards and the bundle sidebar are shown as normal.

- `source/template.html` — editable, self-contained mock
- `output/bundle-swatches.html` — copy of the mock that the images are rendered from
- `output/bundle-swatches@2x.png` — 2400px image, use this in the email at 600px wide
- `output/bundle-swatches.png` — 1200px version

Rebuild with `node build.mjs` (uses the global Playwright install).

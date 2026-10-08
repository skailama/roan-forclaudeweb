# Speks — bundle swatches email image

Mock of the Speks "Build Your Own Bundle" builder
(getspeks.com/products/build-your-own-bundle) with the color swatches on each
product card highlighted, for the swatches-on-product-cards email.

- `source/template.html` — editable mock (product photos are `{{p0}}`…`{{p2}}` placeholders)
- `source/assets/` — product photos pulled from the live store
- `output/speks-bundle-swatches.html` — self-contained HTML (photos inlined)
- `output/speks-bundle-swatches@2x.png` — 2400px image, use this in the email at 600px wide
- `output/speks-bundle-swatches.png` — 1200px version

Swatches are redrawn in CSS from the store's own 25px swatch art so they stay
sharp at 2x. Rebuild with `node build.mjs` (uses the global Playwright install).

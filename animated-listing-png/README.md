# Animated "PNG" listing screenshots

An experiment to reproduce what [Creativul](https://creativul.com/shopify-animated-screenshots) sells: listing screenshots that move on the Shopify App Store, even though the upload slot only accepts static image formats.

## What Creativul offers

- They turn your existing listing screenshots (or new designs) into short looping animations, each about 5–7 seconds of one feature flow: appear → select → confirm.
- You get an animated version plus a static PNG of every screen, the editable source files and upload guidance.
- Turnaround is 7 business days to animate an existing design, or 12 for a new design built with animation in. Their static listing design starts at $300; the animated price is quoted per listing.
- Their FAQ, word for word: *"We deliver every animation as an APNG — a PNG file that plays like a GIF. Shopify's screenshot slots accept PNG, so it uploads and displays exactly like any other screenshot."*

## What the live listing actually serves

Their example client is [apps.shopify.com/abprofit](https://apps.shopify.com/abprofit). Its listing images were inspected on 2026-10-06:

| URL ends in | Real bytes | Size | Frames |
|---|---|---|---|
| `desktop_screenshot/…CLbM5IO9opcDEAE=.png` | **GIF89a**, 1600×900 | 1.04 MB | 112 frames / 5.6 s |
| 5 other `desktop_screenshot/*.png` + `promotional_image/*.png` | **GIF89a**, 1600×900 | 0.24–0.71 MB | animated |

- The CDN returns `content-type: image/gif` even though the URL ends in `.png`.
- When the browser accepts WebP (`Accept: image/webp`), `cdn.shopify.com` re-encodes the image to an **animated WebP**, so the animation survives the CDN's format conversion.
- The `?width=&height=` resize params the listing page adds also keep the animation. The CDN does thin out frames when it resizes or converts: the 112-frame original came back as 47 frames (1280×720 GIF) or 47–48 frames (WebP). Expect slightly less smooth motion than the source file.

So the "trick" is simply this: the listing image slot keeps animated image data, and the CDN preserves animation through resizing and WebP conversion. Whether Creativul uploads APNG and Shopify stores it as GIF, or they upload a GIF named `.png`, the bytes Shopify serves are animated.

## How this folder reproduces it

1. **Source**: the real Figma export of frame `1322:23221` at 2x (`source/frame-5@2x.png`), plus the original layer assets pulled from Figma: product images, SVG icons, and exact fonts/colours/sizes.
2. **Scene**: `scene/scene.html` uses the export as a backdrop. It rebuilds the pieces that move in HTML/CSS, positioned to Figma's coordinates: the BXGY widget, both AOV stat cards, the nav cart badge, and a pointer. Frame 0 matches the Figma export to within about 0.5 px.
3. **Timeline** (7 s loop, 25 fps): finished design → widget collapses → widget opens → pointer clicks **Add** on Kite Comfort Insoles → "✓ Added" + cart badge 1→2 → AOV $186→$233 and products per order +1.0→+1.4 count up with the trend pills popping → back to the finished design. The loop starts and ends on the full design, so the first frame (what any static thumbnail shows) is the complete screenshot and the loop seam is invisible.
4. **Capture**: `scene/capture.mjs` (Playwright + Chromium) steps a deterministic clock and screenshots each frame at 2x.
5. **Encode**: `encode.sh` (ffmpeg) produces the outputs below.

## Outputs (`output/`)

| File | Format | Size | Use |
|---|---|---|---|
| `kite-listing-5-animated.png` | APNG, true colour, 175 frames, infinite loop | 4.2 MB | Best quality, what Creativul says they deliver |
| `kite-listing-5-animated-lite.png` | APNG, 256-colour palette | 0.6 MB | Same animation, about 7x smaller |
| `kite-listing-5-animated-gif-renamed.png` | GIF bytes, `.png` name | 0.76 MB | Exactly what the live competitor listing serves |
| `kite-listing-5-animated.gif` | GIF | 0.76 MB | Same as above with an honest extension |
| `kite-listing-5-static.png` | PNG | 0.47 MB | Static fallback (untouched Figma export) |
| `kite-listing-5-preview.mp4` | H.264 | 0.2 MB | For sharing in Slack, etc. |

All animated files were verified to loop in Chromium. Open `preview.html` locally to see them side by side.

## Testing on Shopify

1. **Product image on a demo store**: upload `kite-listing-5-animated-lite.png` (then the full one) as a product image and view the product page. The theme requests the image through `image_url` with a width, which goes through the same CDN resizing/WebP path described above.
2. **App listing**: in the Partner Dashboard listing editor, upload `kite-listing-5-animated.png` into a screenshot slot and use the listing preview. If the APNG comes back static, try `kite-listing-5-animated-gif-renamed.png`, which is the format proven to work on a live listing today.
3. Keep `kite-listing-5-static.png` as the fallback.

Policy note: requirement 4.4.4 says listing images should primarily show the app's real UI, and 4.4.5 says each image must be unique. An animation of the actual widget flow fits both. Avoid adding outcome guarantees in the animation itself.

## Regenerate

```bash
npm install                 # fonts (@fontsource) + playwright
./encode.sh                 # captures frames/ and writes output/
```

To change the motion, edit the `T` timeline and the `render(t)` function in `scene/scene.html`. To preview a single moment: `node scene/capture.mjs 25 /tmp/check --only=3.7`.

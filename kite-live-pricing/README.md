# Kite live pricing prototype

The question: how could a merchant (or their AI agent) build any storefront UI on top of a Kite discount, such as a bundle page, a quantity table or a cart bar, with live discounted prices, "add 1 more to save 15%" nudges and tiers, without a Kite widget?

The answer this prototype tests: compile Kite's own discount function to WebAssembly and run the same file in the shopper's browser. The storefront then asks the real function what a hypothetical cart would cost, instead of a hand-written JavaScript copy of the Rust logic.

Published page (write-up plus live demo): https://claude.ai/artifact/Akf9HsBBaWJaHpVax74UPt

## What was verified

- Five Kite functions from `skailama/backend-discountAndGift-app7` at `769ed9b` build unmodified with `cargo build --release --target wasm32-wasip1`: `custom-discount-builder`, `consolidated-bxgy-discount`, `Volume-Discount`, `combined-custom-discount` and `shipping-discount-v2`. Each is 230 to 310 KB raw and 90 to 110 KB gzipped.
- All five import the same six WASI calls (`fd_read`, `fd_write`, `proc_exit`, `random_get`, `environ_get`, `environ_sizes_get`), because they use `shopify_function 0.8` (JSON on stdin and stdout). `engine/run-function.mjs` provides those calls in about 60 lines, and the same code runs in a browser.
- `custom-discount-builder` runs in about 0.5 to 1 ms per call once loaded. The demo page makes about 40 to 60 runs per interaction, for the what-if nudges, per-product prices and the quantity table.
- Three offer shapes behave as expected (`engine/offers.test.mjs`): tiers of 3/4/5 items at 10/15/20%, buy 2 and get the cheapest third 10% off, and any 3 for $75. The last one is gated on the `_kite_bundle` line property; without that property the function returns nothing.

## Files

- `page/kite-live-pricing.src.html`: the demo and write-up, with a `__WASM_B64__` placeholder.
- `dist/kite-live-pricing.html`: the built page with the function inlined. Open it in a browser.
- `engine/run-function.mjs`: the WASI shim that runs a Shopify Function outside Shopify.
- `engine/offers.test.mjs`: assertions for the three demo offers against the real function.
- `build.sh`: compiles the function from an app7 checkout, runs the tests, and builds `dist/`.

```bash
./build.sh ../backend-discountAndGift-app7
```

## Not built yet

- `Kite.ready`, `Kite.offers`, `Kite.on('update')`, and reconciling against `/cart.js` once items are in the cart.
- Publishing the function config to the storefront. Today `routes/frontend/frontend.service.js` loads consolidated discounts with `.select('-metafieldInfo …')`, so the storefront never sees what the function reads.
- Input builders for the other four functions. Each function has its own GraphQL input query, so each needs its own builder.

// Renders scene.html frame-by-frame with a deterministic clock and writes PNGs.
// Usage: node scene/capture.mjs [fps] [outDir] [--only=t1,t2,...]
import { chromium } from "playwright";
import { mkdirSync, rmSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fps = Number(process.argv[2] || 25);
const outDir = resolve(process.argv[3] || resolve(here, "../frames"));
const only = (process.argv.find(a => a.startsWith("--only=")) || "").slice(7);

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ executablePath: "/opt/pw-browsers/chromium-1194/chrome-linux/chrome" });
const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 2 });
await page.goto("file://" + resolve(here, "scene.html"));
await page.evaluate(() => document.fonts.ready);
await page.waitForFunction(() => [...document.images].every(i => i.complete && i.naturalWidth > 0));

const duration = await page.evaluate(() => window.TIMELINE.duration);
const times = only
  ? only.split(",").map(Number)
  : Array.from({ length: Math.round(duration * fps) }, (_, i) => i / fps);

for (let i = 0; i < times.length; i++) {
  await page.evaluate(t => window.render(t), times[i]);
  await page.screenshot({ path: `${outDir}/f${String(i).padStart(4, "0")}.png` });
}
console.log(`wrote ${times.length} frames (${fps} fps, ${duration}s) to ${outDir}`);
await browser.close();

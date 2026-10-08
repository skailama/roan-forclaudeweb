// Inlines product photos into the template and renders the email PNG.
// Usage: node build.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';

const here = new URL('.', import.meta.url).pathname;
const require = createRequire(import.meta.url);
const { chromium } = require(execSync('npm root -g').toString().trim() + '/playwright');

let html = readFileSync(here + 'source/template.html', 'utf8');
for (const k of ['p0', 'p1', 'p2']) {
  const b64 = readFileSync(here + `source/assets/${k}.jpg`).toString('base64');
  html = html.replaceAll(`{{${k}}}`, `data:image/jpeg;base64,${b64}`);
}
writeFileSync(here + 'output/speks-bundle-swatches.html', html);

const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined;
const browser = await chromium.launch({ proxy });
const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 2, ignoreHTTPSErrors: true });
await page.goto('file://' + here + 'output/speks-bundle-swatches.html', { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
const el = page.locator('#shot');
await el.screenshot({ path: here + 'output/speks-bundle-swatches@2x.png' });
await page.setViewportSize({ width: 1200, height: 900 });
const p1 = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 1, ignoreHTTPSErrors: true });
await p1.goto('file://' + here + 'output/speks-bundle-swatches.html', { waitUntil: 'networkidle' });
await p1.evaluate(() => document.fonts.ready);
await p1.locator('#shot').screenshot({ path: here + 'output/speks-bundle-swatches.png' });
await browser.close();
console.log('done');

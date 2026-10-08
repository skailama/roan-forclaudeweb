// Renders the email PNGs (1x and 2x) from the self-contained template.
// Usage: node build.mjs
import { copyFileSync, mkdirSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';

const here = new URL('.', import.meta.url).pathname;
const require = createRequire(import.meta.url);
const { chromium } = require(execSync('npm root -g').toString().trim() + '/playwright');

mkdirSync(here + 'output', { recursive: true });
const html = here + 'output/bundle-swatches.html';
copyFileSync(here + 'source/template.html', html);

const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined;
const browser = await chromium.launch({ proxy });
for (const [scale, name] of [[2, 'bundle-swatches@2x.png'], [1, 'bundle-swatches.png']]) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: scale, ignoreHTTPSErrors: true });
  await page.goto('file://' + html, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  await page.locator('#shot').screenshot({ path: here + 'output/' + name });
}
await browser.close();
console.log('done');

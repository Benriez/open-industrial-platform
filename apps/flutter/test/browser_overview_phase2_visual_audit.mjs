const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18810';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/visual-audit-phase2');
await mkdir(out, {recursive: true});
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({
  viewport: {width: 1440, height: 900}, deviceScaleFactor: 1, serviceWorkers: 'block',
});
const page = await context.newPage();
const errors = [], captures = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
async function capture(name) {
  await page.screenshot({path: resolve(out, `${name}-1440x900.png`)});
  captures.push(`${name}-1440x900.png`);
}
async function nav(label) {
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
}
try {
  await page.goto(`${base}/?phase2-visual-audit=1`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Deine Infrastruktur. Ein Bild.', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await page.waitForTimeout(1200);
  await capture('overview-phase1');
  await nav('OPC-UA-Browser');
  await page.getByText('Namespace 2', {exact: true}).waitFor();
  await page.waitForTimeout(400);
  await capture('reference-opcua-phase2');
  await nav('Netzwerk & VPN');
  await page.getByText('NETWORK ENGINEERING EXPLORER · READ-ONLY', {exact: true}).waitFor();
  await page.waitForTimeout(400);
  await capture('reference-network-phase2');
  await nav('Diagnose & Ereignisse');
  await page.getByRole('button', {name: 'Diagnosedaten aktualisieren', exact: true}).waitFor();
  await page.waitForTimeout(400);
  await capture('reference-diagnostics-working-copy');
  assert.deepEqual(errors, []);
  const status = await (await context.request.get(`${base}/api/v1/system/status`)).json();
  await writeFile(resolve(out, 'visual-audit.json'), JSON.stringify({
    verdict: 'PASS', base, viewport: '1440x900', scenario: status.scenario,
    captures, errors,
    note: 'Actual combined Phase 1 preview; all four views captured in one browser context and data scope.',
  }, null, 2));
  console.log(`PASS ${captures.length} identical-viewport reference captures`);
} finally {
  await browser.close();
}

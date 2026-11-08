const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18910';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/visual-audit-devices');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined), headless: true});
const context = await browser.newContext({viewport: {width: 1440, height: 900}, deviceScaleFactor: 1, serviceWorkers: 'block'});
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
  await page.goto(`${base}/?devices-visual-audit=1`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav('Geräte & Dienste');
  await page.getByText('Geräte & Dienste', {exact: true}).last().waitFor();
  await page.waitForTimeout(500);
  await capture('devices-before');
  await nav('OPC-UA-Browser');
  await page.getByText('Namespace 2', {exact: true}).waitFor();
  await capture('reference-opcua-phase2');
  await nav('Netzwerk & VPN');
  await page.getByText('NETWORK ENGINEERING EXPLORER · READ-ONLY', {exact: true}).waitFor();
  await capture('reference-network-phase2');
  await nav('Übersicht');
  await page.getByText('Operations Workstation', {exact: true}).waitFor();
  await capture('reference-overview-phase2');
  assert.deepEqual(errors, []);
  await writeFile(resolve(out, 'visual-audit.json'), JSON.stringify({
    verdict: 'PASS', base, viewport: '1440x900', captures, errors,
    note: 'Actual combined Overview Phase 2 preview; Devices before and three current references captured in one browser/data scope.',
  }, null, 2));
  console.log(`PASS ${captures.length} identical-viewport Devices/reference captures`);
} finally {
  await browser.close();
}

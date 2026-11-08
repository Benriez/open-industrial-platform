const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';

const before = process.env.OIP_BEFORE_URL ?? 'http://127.0.0.1:18921';
const after = process.env.OIP_AFTER_URL ?? 'http://127.0.0.1:18920';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/before-after-devices-2027');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const errors = [], external = [], files = [];
async function assetHash(base) {
  const response = await fetch(`${base}/main.dart.js`);
  assert.equal(response.status, 200);
  return createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
}
async function nav(page, label) {
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
}
async function waitNormal(context) {
  const deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    const [sources, metrics] = await Promise.all([
      (await context.request.get(`${after}/api/v1/sources`)).json(),
      (await context.request.get(`${after}/api/v1/metrics/current`)).json(),
    ]);
    if (sources.every(source => source.connection === 'connected') &&
        metrics.some(item => item.metric_id === 'temperature' && item.freshness === 'fresh')) return;
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  throw new Error('Normal scenario did not reach connected SourceHealth and fresh telemetry');
}

try {
  const assets = {before: await assetHash(before), after: await assetHash(after)};
  assert.notEqual(assets.before, assets.after, 'Before and after must be distinct bundles');
  for (const viewport of [{width: 1440, height: 900}, {width: 1920, height: 1080}]) {
    const context = await browser.newContext({viewport, deviceScaleFactor: 1, serviceWorkers: 'block'});
    const response = await context.request.post(`${after}/api/v1/demo/scenario`, {data: {scenario: 'normal'}});
    assert.equal(response.status(), 200);
    await waitNormal(context);
    for (const [label, base] of [['before', before], ['after', after]]) {
      const page = await context.newPage();
      page.on('pageerror', error => errors.push(`${label}: ${error.message}`));
      page.on('console', message => {
        if (message.type() === 'error') errors.push(`${label}: ${message.text()}`);
      });
      page.on('request', request => {
        const url = new URL(request.url());
        if (url.protocol.startsWith('http') && ![new URL(before).origin, new URL(after).origin].includes(url.origin)) external.push(url.href);
      });
      await page.goto(`${base}/?before-after-devices=${label}`, {waitUntil: 'domcontentloaded'});
      await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
      await page.getByText('API CONNECTED', {exact: false}).waitFor();
      await nav(page, 'Geräte & Dienste');
      await page.getByText(label === 'before' ? 'Ein gemeinsames Inventar. Jede Quelle bleibt erkennbar.' : 'DEVICES & SERVICES · ENGINEERING WORKSTATION', {exact: true}).first().waitFor();
      await page.waitForTimeout(500);
      const initial = `devices-${label}-initial-${viewport.width}x${viewport.height}.png`;
      await page.screenshot({path: resolve(out, initial)});
      files.push(initial);
      if (label === 'before') {
        await page.getByRole('button', {name: /Details OPC-UA-Sensoren · M-01/}).click();
        await page.getByText('Fünf unabhängige Statusdimensionen', {exact: true}).waitFor();
      } else {
        await page.keyboard.press('/');
        await page.keyboard.type('OPC-UA-Sensoren · M-01', {delay: 8});
        const row = page.getByRole('button', {name: /Gerät OPC-UA-Sensoren · M-01 M-01 auswählen/});
        await row.waitFor();
        await row.click({force: true});
        await page.getByText('ENGINEERING WORKSPACE', {exact: true}).waitFor();
        await page.getByText('CONTEXT INSPECTOR', {exact: true}).waitFor();
      }
      const detail = `devices-${label}-detail-${viewport.width}x${viewport.height}.png`;
      await page.screenshot({path: resolve(out, detail)});
      files.push(detail);
      await page.close();
    }
    await context.close();
  }
  assert.deepEqual(errors, []);
  assert.deepEqual(external, []);
  await writeFile(resolve(out, 'before-after-devices.json'), JSON.stringify({
    verdict: 'PASS', viewports: ['1440x900', '1920x1080'], same_own_core: 'http://127.0.0.1:18210',
    scenario: 'normal', before, after, mainDartJsSha256: assets, files, errors, external,
    note: 'Baseline and Devices workstation captured sequentially against the same Core and normal scenario. Live values may advance between captures; provenance and selection scope are the comparison contract.',
  }, null, 2));
  console.log(`PASS ${files.length} identical-viewport before/after Devices captures`);
} finally {
  await browser.close();
}

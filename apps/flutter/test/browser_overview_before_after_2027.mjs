const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
const before = process.env.OIP_BEFORE_URL ?? 'http://127.0.0.1:18911';
const after = process.env.OIP_AFTER_URL ?? 'http://127.0.0.1:18910';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/before-after-overview-phase2');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined), headless: true});
const errors = [], files = [];
async function waitNormal(context) {
  const deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    const [sources, metrics] = await Promise.all([
      (await context.request.get(`${before}/api/v1/sources`)).json(),
      (await context.request.get(`${before}/api/v1/metrics/current`)).json(),
    ]);
    if (sources.every(source => source.connection === 'connected') &&
        metrics.some(item => item.metric_id === 'temperature' && item.freshness === 'fresh')) return;
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  throw new Error('Normal scenario did not reach connected SourceHealth and fresh telemetry');
}
try {
  for (const viewport of [{width: 1440, height: 900}, {width: 1920, height: 1080}]) {
    const context = await browser.newContext({viewport, deviceScaleFactor: 1, serviceWorkers: 'block'});
    const response = await context.request.post(`${before}/api/v1/demo/scenario`, {data: {scenario: 'normal'}});
    assert.equal(response.status(), 200);
    await waitNormal(context);
    for (const [label, base] of [['phase1', before], ['phase2', after]]) {
      const page = await context.newPage();
      page.on('pageerror', error => errors.push(`${label}: ${error.message}`));
      await page.goto(`${base}/?before-after-overview-phase2=${label}`, {waitUntil: 'domcontentloaded'});
      await page.getByText(label === 'phase1' ? 'Deine Infrastruktur. Ein Bild.' : 'Operations Workstation', {exact: true}).waitFor({timeout: 60000});
      await page.getByText('API CONNECTED', {exact: false}).waitFor();
      await page.waitForTimeout(1200);
      const name = `overview-${label}-${viewport.width}x${viewport.height}.png`;
      await page.screenshot({path: resolve(out, name)});
      files.push(name);
      if (label === 'phase2') {
        await page.getByRole('button', {name: 'Navigation OPC-UA-Browser', exact: true}).click();
        await page.getByText('Namespace 2', {exact: true}).waitFor();
        const opcua = `reference-opcua-${viewport.width}x${viewport.height}.png`;
        await page.screenshot({path: resolve(out, opcua)}); files.push(opcua);
        await page.getByRole('button', {name: 'Navigation Netzwerk & VPN', exact: true}).click();
        await page.getByText('NETWORK ENGINEERING EXPLORER · READ-ONLY', {exact: true}).waitFor();
        const network = `reference-network-${viewport.width}x${viewport.height}.png`;
        await page.screenshot({path: resolve(out, network)}); files.push(network);
      }
      await page.close();
    }
    await context.close();
  }
  assert.deepEqual(errors, []);
  await writeFile(resolve(out, 'before-after.json'), JSON.stringify({
    verdict: 'PASS', viewports: ['1440x900', '1920x1080'],
    same_own_core: 'http://127.0.0.1:18210', scenario: 'normal', before, after, files, errors,
  }, null, 2));
  console.log(`PASS ${files.length} identical-data comparison captures`);
} finally {
  await browser.close();
}

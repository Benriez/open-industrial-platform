const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-devices-fixtures-2027');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const errors = [], checks = [], captures = [];
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function run(mode, base, workflow) {
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(`${mode}: ${error.message}`));
  page.on('console', message => {
    if (message.type() === 'error') errors.push(`${mode}: ${message.text()}`);
  });
  await page.goto(`${base}/?explicit-devices-fixture=${mode}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await page.getByRole('button', {name: 'Navigation Geräte & Dienste', exact: true}).click();
  await page.getByText('DEVICES & SERVICES · ENGINEERING WORKSTATION', {exact: true}).waitFor();
  async function capture(name) {
    await page.screenshot({path: resolve(out, `${name}.png`)});
    captures.push(`${name}.png`);
  }
  async function select(name, id) {
    const field = page.getByRole('textbox').first();
    await field.click();
    await page.keyboard.press('Escape');
    await field.click();
    await page.keyboard.type(name, {delay: 8});
    const row = page.getByRole('button', {name: new RegExp(`Gerät ${escape(name)} ${escape(id)} auswählen`)}).first();
    await row.waitFor();
    await row.scrollIntoViewIfNeeded();
    await row.click({force: true});
    await page.getByText('ENGINEERING WORKSPACE', {exact: true}).waitFor();
  }
  await workflow({page, capture, select});
  await context.close();
}

try {
  await run('multi', process.env.OIP_DEVICES_MULTI_URL ?? 'http://127.0.0.1:18928', async ({page, capture, select}) => {
    await page.getByText('2 von 2 Geräten · Simuliertes Inventar', {exact: true}).waitFor();
    await select('Fixture M-02', 'M-02');
    await page.getByText(/320\.5 kPa/).first().waitFor();
    assert.equal(await page.getByText(/61\.2 °C/).count(), 0);
    await capture('devices-FIXTURE-multi-source-M02-1440x1000');
    await select('Fixture M-01', 'M-01');
    await page.getByText(/61\.2 °C/).first().waitFor();
    assert.equal(await page.getByText(/320\.5 kPa/).count(), 0);
    await capture('devices-FIXTURE-multi-source-M01-1440x1000');
    checks.push('Multi-source DeviceDetail joins exact source and entity; no value crosses devices');
  });

  await run('zero', process.env.OIP_DEVICES_ZERO_URL ?? 'http://127.0.0.1:18924', async ({page, capture}) => {
    await page.getByText('0 von 0 Geräten · Simuliertes Inventar', {exact: true}).waitFor();
    await page.getByText('Keine Geräte gefunden', {exact: true}).waitFor();
    assert.equal(await page.getByText(/°C|kPa/).count(), 0);
    await capture('devices-FIXTURE-zero-1440x1000');
    checks.push('Zero inventory renders an honest empty state with no measurements');
  });

  await run('empty', process.env.OIP_DEVICES_EMPTY_URL ?? 'http://127.0.0.1:18929', async ({page, capture, select}) => {
    await select('Fixture M-01', 'M-01');
    await page.getByText('Keine Telemetrie für dieses Gerät verfügbar', {exact: true}).waitFor();
    await page.getByText(/Kein Ersatzwert, kein 0 % und kein künstlicher Chart/).waitFor();
    await capture('devices-FIXTURE-no-telemetry-1440x1000');
    checks.push('One device without observations has no zero substitute or fabricated chart');
  });

  await run('large', process.env.OIP_DEVICES_LARGE_URL ?? 'http://127.0.0.1:18927', async ({page, capture}) => {
    await page.getByText('120 von 120 Geräten · Simuliertes Inventar', {exact: true}).waitFor();
    await page.getByText('Seite 1 / 3', {exact: true}).waitFor();
    await capture('devices-FIXTURE-large-page1-1440x1000');
    await page.getByRole('button', {name: 'Nächste Geräte', exact: true}).click();
    await page.getByText('Seite 2 / 3', {exact: true}).waitFor();
    await page.getByRole('button', {name: /Gerät Fixture inv-051 inv-051 auswählen/}).waitFor();
    assert.equal(await page.getByRole('button', {name: /Gerät Fixture inv-101 inv-101 auswählen/}).count(), 0);
    await capture('devices-FIXTURE-large-page2-1440x1000');
    checks.push('Explicit 120-device fixture paginates fifty rows without claiming server-side filtering');
  });

  assert.deepEqual(errors, []);
  await writeFile(resolve(out, 'browser-devices-fixture-results.json'), JSON.stringify({
    verdict: 'PASS', fixture_only: true, synthetic_inventory: true,
    real_ingestion: false, backend_scaling_proof: false, checks, captures, errors,
  }, null, 2));
  for (const check of checks) console.log(`PASS ${check}`);
} catch (error) {
  await writeFile(resolve(out, 'browser-devices-fixture-failure.json'), JSON.stringify({
    verdict: 'FAIL', error: String(error), checks, captures, errors,
  }, null, 2));
  console.error(error);
  process.exitCode = 1;
} finally {
  await browser.close();
}

const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-overview-2027');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined), headless: true});
const checks = [], captures = [], errors = [];

async function run(mode, base) {
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(`${mode}: ${error.message}`));
  page.on('console', message => { if (message.type() === 'error') errors.push(`${mode}: ${message.text()}`); });
  await page.goto(`${base}/?explicit-ui-fixture=${mode}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await page.getByText('DEMO / SIMULATION', {exact: true}).waitFor();
  if (mode === 'multi') {
    await page.locator('flt-semantics[role="text"]').filter({hasText: /^SOURCES: 2 \/ 2 CONNECTED/}).waitFor();
    await page.getByText(/Fixture Source A/).first().waitFor();
    await page.getByText(/Fixture Source B/).first().waitFor();
    await page.screenshot({path: resolve(out, 'overview-FIXTURE-multiple-sources-1440x1000.png')});
    captures.push('overview-FIXTURE-multiple-sources-1440x1000.png');
    await page.getByRole('button', {name: 'Nächstes Sample', exact: true}).waitFor();
    await page.keyboard.press('F6');
    let focusedSample = '';
    for (let attempt = 0; attempt < 30 && focusedSample !== 'Nächstes Sample'; attempt++) {
      await page.waitForTimeout(100);
      focusedSample = await page.evaluate(() => document.activeElement?.textContent ?? '');
    }
    assert.equal(focusedSample, 'Nächstes Sample', 'F6 must focus the sample action');
    await page.keyboard.press('Enter');
    await page.getByText(/ · Simulator-Quellzeit .* · Tatsächlicher Empfang /).waitFor();
    checks.push('Explicit fixture proves F6 and Enter sample inspection without pointer input');
    await page.getByRole('button', {name: /Fixture Source B/}).first().click();
    await page.getByText('320.5 kPa', {exact: true}).waitFor();
    assert.equal(await page.getByText('61.2 °C', {exact: true}).count(), 0);
    checks.push('Explicit multi-source fixture keeps Source, Signal, value and chart selection scoped');
  } else {
    await page.getByText('Kein Live-Signal verfügbar', {exact: true}).waitFor();
    await page.getByText(/Keine Ersatzwerte/).waitFor();
    await page.screenshot({path: resolve(out, 'overview-FIXTURE-no-live-signal-1440x1000.png')});
    captures.push('overview-FIXTURE-no-live-signal-1440x1000.png');
    checks.push('Explicit empty fixture renders no fake chart, value or healthy telemetry claim');
  }
  await context.close();
}

try {
  await run('multi', process.env.OIP_MULTI_FIXTURE_URL ?? 'http://127.0.0.1:18912');
  await run('empty', process.env.OIP_EMPTY_FIXTURE_URL ?? 'http://127.0.0.1:18913');
  assert.deepEqual(errors, []);
  await writeFile(resolve(out, 'browser-overview-fixture-results.json'), JSON.stringify({
    verdict: 'PASS', fixture_only: true, backend_scaling_proof: false, checks, captures, errors,
  }, null, 2));
  for (const check of checks) console.log(`PASS ${check}`);
} catch (error) {
  await writeFile(resolve(out, 'browser-overview-fixture-failure.json'), JSON.stringify({verdict: 'FAIL', error: String(error), checks, captures, errors}, null, 2));
  console.error(error);
  process.exitCode = 1;
} finally {
  await browser.close();
}

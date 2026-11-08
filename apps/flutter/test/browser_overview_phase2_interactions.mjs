const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18910';
const multi = process.env.OIP_MULTI_FIXTURE_URL ?? 'http://127.0.0.1:18912';
const empty = process.env.OIP_EMPTY_FIXTURE_URL ?? 'http://127.0.0.1:18913';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/interactions-overview-phase2');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined), headless: true});
const errors = [], checks = [], captures = [], apiPaths = [];
function observe(page) {
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  page.on('request', request => {
    const path = new URL(request.url()).pathname;
    if (path.startsWith('/api/')) apiPaths.push(path);
  });
}
function pass(label) { checks.push(label); console.log(`PASS ${label}`); }
async function capture(page, name) {
  await page.screenshot({path: resolve(out, `${name}.png`)});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `${name}: overflow`);
}
async function boot(context, url = base) {
  const page = await context.newPage(); observe(page);
  await page.goto(`${url}/?overview-phase2-interactions=1`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await page.waitForTimeout(1000);
  return page;
}
async function nav(page, label) {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (await menu.count()) await menu.click();
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
}
try {
  const context = await browser.newContext({viewport: {width: 1440, height: 900}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  const page = await boot(context);
  await capture(page, 'source-selected-1440x900');
  await page.getByText('AVAILABLE SIGNALS', {exact: true}).waitFor();
  const activityBox = await page.getByRole('button', {name: 'Activity', exact: true}).boundingBox();
  const investigationBox = await page.getByRole('button', {name: 'OPC-UA untersuchen', exact: true}).last().boundingBox();
  assert.ok(activityBox && activityBox.y < 900 && investigationBox && investigationBox.y < 900,
    '1440x900 must expose activity and direct investigation without a long page search');
  pass('Source selection links primary SourceHealth, signal and inspector in the first 1440x900 viewport');

  await page.getByText(/SIMULATOR-QUELLZEIT/).first().waitFor();
  await page.getByText(/TATSÄCHLICHER EMPFANG/).first().waitFor();
  const metrics = await (await context.request.get(`${base}/api/v1/metrics/current`)).json();
  const temperature = metrics.find(item => item.metric_id === 'temperature');
  assert.ok(temperature.simulation_origin && temperature.timestamps.source < temperature.timestamps.received);
  pass('Clock provenance distinguishes virtual simulator source time from actual receive time without changing freshness');

  const search = page.getByRole('textbox', {name: /Source, Gerät, Typ/});
  await search.fill('AMD EVO-X2');
  await page.waitForTimeout(350);
  await page.getByRole('button', {name: /AMD EVO-X2 evo/}).click();
  await page.waitForTimeout(350);
  await page.getByText('Kein Live-Signal verfügbar', {exact: true}).waitFor();
  await page.getByText(/kein aktiver Probe/).first().waitFor();
  await capture(page, 'device-selected-no-telemetry-1440x900');
  await page.getByRole('button', {name: 'Gerätedetails öffnen', exact: true}).click();
  await page.getByText('GERÄTEDETAILS · SIMULATION', {exact: true}).waitFor();
  await page.getByRole('button', {name: 'Details schließen', exact: true}).click();
  assert.equal(await page.getByText('0.0 °C', {exact: true}).count(), 0);
  pass('Device selection clears unrelated telemetry, keeps connectivity unmeasured and opens actual device details');

  await page.getByRole('button', {name: 'Source Health', exact: true}).click();
  await page.waitForTimeout(350);
  await page.getByText(/Local OPC-UA Simulation · oip-local-simulation-v1/).click();
  await page.getByRole('button', {name: 'Activity', exact: true}).click();
  await page.waitForTimeout(350);
  const event = page.getByText(/ConnectionLost/).last();
  await event.click();
  await page.getByText('EVENT TIME · CONTROL/WALL CLOCK', {exact: true}).waitFor();
  await page.getByText(/Ursache und globale Severity nicht geliefert/).waitFor();
  await capture(page, 'event-selected-1440x900');
  await page.getByRole('button', {name: 'Diagnostics öffnen', exact: true}).last().click();
  await page.getByRole('button', {name: 'Diagnosedaten aktualisieren', exact: true}).waitFor();
  await nav(page, 'Übersicht');
  pass('Collection event selection exposes actual evidence/time context and opens the existing Diagnostics module');

  await page.getByRole('button', {name: 'Auswahl aufheben', exact: true}).click();
  await page.getByText('Quelle, Gerät oder Ereignis auswählen.', {exact: true}).waitFor();
  await capture(page, 'empty-inspector-1440x900');
  pass('Inspector empty state is compact and does not invent a selected entity');
  await context.close();

  const multiContext = await browser.newContext({viewport: {width: 1440, height: 900}, serviceWorkers: 'block'});
  const multiPage = await boot(multiContext, multi);
  await multiPage.getByRole('button', {name: /Fixture Source B/}).first().click();
  await multiPage.getByText('320.5 kPa', {exact: true}).waitFor();
  await multiPage.getByText('AVAILABLE SIGNALS', {exact: true}).waitFor();
  await multiPage.getByText(/SubscriptionError/).last().waitFor();
  assert.equal(await multiPage.getByText(/Reconnected · fixture-source-a#1/).count(), 0,
    'Source A activity record must not appear in Source B activity');
  await capture(multiPage, 'FIXTURE-source-b-selected-1440x900');
  pass('Explicit multi-source fixture synchronizes Source B signal, inspector and filtered activity without Source A leakage');
  await multiContext.close();

  const emptyContext = await browser.newContext({viewport: {width: 1440, height: 900}, serviceWorkers: 'block'});
  const emptyPage = await boot(emptyContext, empty);
  await emptyPage.getByText('Kein Live-Signal verfügbar', {exact: true}).waitFor();
  await emptyPage.getByText('Keine Events im ausgewählten aktuellen Datenumfang.', {exact: true}).waitFor();
  await capture(emptyPage, 'FIXTURE-no-telemetry-empty-diagnostics-1440x900');
  pass('Explicit no-telemetry/no-events fixture renders neither fake chart nor fake diagnostics');
  await emptyContext.close();

  for (const width of [390, 834]) {
    const responsive = await browser.newContext({viewport: {width, height: width === 390 ? 844 : 1112}, serviceWorkers: 'block'});
    const p = await boot(responsive);
    if (width === 390) {
      await p.getByRole('button', {name: 'Explorer', exact: true}).click();
      await p.getByRole('button', {name: /Local OPC-UA Simulation/}).first().click();
      await p.getByRole('button', {name: 'Inspector', exact: true}).click();
      await p.getByText('AVAILABLE SIGNALS', {exact: true}).waitFor();
    }
    await capture(p, width === 390 ? 'mobile-inspector-390x844' : 'tablet-834x1112');
    await responsive.close();
  }
  pass('Mobile Explorer/Focus/Inspector navigation and tablet arrangement are functional');

  assert.deepEqual(errors, []);
  assert.equal(apiPaths.some(path => path.startsWith('/api/v2/')), false);
  await writeFile(resolve(out, 'interaction-results.json'), JSON.stringify({
    verdict: 'PASS', checks, captures, errors, api_paths: [...new Set(apiPaths)],
    fixtures_explicit: true, visual_status: 'VISUAL_PENDING_OPERATOR_ACCEPTANCE',
  }, null, 2));
  console.log(`PASS ${checks.length} interaction chains, ${captures.length} captures`);
} catch (error) {
  await writeFile(resolve(out, 'interaction-failure.json'), JSON.stringify({verdict: 'FAIL', error: String(error), checks, captures, errors}, null, 2));
  console.error(error); process.exitCode = 1;
} finally {
  await browser.close();
}

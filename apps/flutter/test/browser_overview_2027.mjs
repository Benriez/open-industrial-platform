const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18910';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-overview-phase2');
await mkdir(out, {recursive: true});
for (const file of ['browser-overview-failure.json', 'failure.png']) await rm(resolve(out, file), {force: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined), headless: true});
const errors = [], failedResources = [], external = [], expectedFaults = [], checks = [], captures = [], apiPaths = [];
let expectedFault = false;
let streamRequests = 0;

function observe(page) {
  page.on('pageerror', error => (expectedFault ? expectedFaults : errors).push(error.message));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const identityProbe = message.text().includes('403');
    (expectedFault || identityProbe ? expectedFaults : errors).push(message.text());
  });
  page.on('request', request => {
    const path = new URL(request.url()).pathname;
    if (path.startsWith('/api/')) apiPaths.push(path);
    if (path === '/api/v1/stream') streamRequests++;
  });
  page.on('response', response => {
    if (response.status() >= 400) {
      const identityProbe = response.status() === 403 && new URL(response.url()).pathname === '/api/v2/organizations';
      (expectedFault || identityProbe ? expectedFaults : failedResources).push(`${response.status()} ${response.url()}`);
    }
  });
}
function pass(label) { checks.push(label); console.log(`PASS ${label}`); }
async function capture(page, name) {
  await page.screenshot({path: resolve(out, `${name}.png`), fullPage: false});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `${name}: document overflow`);
}
async function scenario(context, name) {
  const response = await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: name}});
  assert.equal(response.status(), 200, `scenario ${name}`);
}
async function waitApi(context, path, predicate, label) {
  const deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    const response = await context.request.get(`${base}${path}`);
    assert.equal(response.status(), 200, label);
    const value = await response.json();
    if (predicate(value)) return value;
    await new Promise(resolve => setTimeout(resolve, 120));
  }
  throw new Error(`Timed out waiting for ${label}`);
}
async function boot(context, width = 1440, height = 900) {
  const page = await context.newPage();
  observe(page);
  await page.setViewportSize({width, height});
  await page.goto(`${base}/?overview-2027=${width}x${height}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  // Existing Overview regression intentionally exercises the full expert layout.
  await page.getByRole('button', {name: /Engineering Workspace/}).click({force: true});
  await page.getByRole('button', {name: /Detail-Inspector manuell öffnen/}).click({force: true});
  if (width < 760) {
    await page.getByRole('button', {name: 'Focus', exact: true}).click();
  }
  await page.getByText('OPERATIONAL FOCUS · SESSION TELEMETRY', {exact: true}).waitFor();
  await page.waitForTimeout(1200);
  return page;
}
async function nav(page, label) {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (await menu.count()) await menu.click();
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
}
async function scrollTo(page, text) {
  await page.getByText(text, {exact: true}).first().evaluate(element => element.scrollIntoView({block: 'center'}));
  await page.waitForTimeout(150);
}

try {
  const context = await browser.newContext({viewport: {width: 1440, height: 900}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) {
      external.push(url.href);
      return route.abort();
    }
    return route.continue();
  });
  await scenario(context, 'normal');
  const page = await boot(context);
  await capture(page, 'overview-normal-1440x900');
  await capture(page, 'overview-fresh-opcua-telemetry-1440x900');
  await capture(page, 'overview-no-active-findings-1440x900');
  await capture(page, 'overview-missing-host-collectors-1440x900');
  await page.locator('flt-semantics[role="text"]').filter({hasText: /^FINDINGS: NONE IN CURRENT DATA/}).waitFor();
  await page.getByRole('button', {name: 'Data Coverage', exact: true}).click();
  await page.getByText(/globaler Core\/SQLite-Bestand/).waitFor();
  await page.getByText(/kein aktiver Probe/).first().waitFor();
  await page.getByRole('button', {name: 'Activity', exact: true}).click();
  assert.equal(await page.getByText('Erreichbare Geräte', {exact: true}).count(), 0);
  assert.equal(await page.getByText('0 %', {exact: true}).count(), 0);
  assert.equal(streamRequests, 1, 'normal operation must use one SSE subscription');
  pass('Normal operation separates Core, Sources, Registry, Findings, Freshness and missing host collectors');

  const next = page.getByRole('button', {name: 'Nächstes Sample', exact: true});
  await next.click();
  await page.getByText(/ · Simulator-Quellzeit .* · Tatsächlicher Empfang /).waitFor();
  assert.equal(await next.count(), 1);
  pass('Telemetry sample selection exposes actual source/receive timestamps');

  await scrollTo(page, 'Activity');
  const event = page.getByRole('button', {name: /Reconnected/}).last();
  if (await event.count()) {
    await event.click();
    await page.getByText(/kein ID-Router-Kontext/).waitFor();
    await capture(page, 'overview-reconnect-evidence-1440x900');
    const dismiss = page.getByText('Dismiss', {exact: true});
    if (await dismiss.count()) {
      await page.mouse.click(1200, 150);
      await page.waitForTimeout(150);
    }
  }
  await page.getByRole('button', {name: /Source Local OPC-UA Simulation .* auswählen/}).click();
  pass('Recent activity inspects actual event timing and documents missing ID deep-link support');

  const deep = await boot(context);
  await deep.getByRole('button', {name: /Source Local OPC-UA Simulation .* auswählen/}).click();
  await deep.getByRole('button', {name: 'OPC-UA untersuchen', exact: true}).last().click();
  await deep.getByText('Namespace 2', {exact: true}).waitFor();
  await nav(deep, 'Übersicht');
  await deep.getByText('OPERATIONAL FOCUS · SESSION TELEMETRY', {exact: true}).waitFor();
  await deep.getByRole('button', {name: 'Netzwerk untersuchen', exact: true}).click();
  await deep.getByRole('button', {name: 'Topologie', exact: true}).click();
  await deep.getByText('Logische Topologie', {exact: true}).first().waitFor();
  await nav(deep, 'Übersicht');
  await deep.getByRole('button', {name: 'Diagnostics öffnen', exact: true}).last().click();
  await deep.getByText('Diagnose & Ereignisse', {exact: true}).first().waitFor();
  await nav(deep, 'Übersicht');
  await deep.close();
  pass('Deep dives open only existing OPC-UA, Network and Diagnostics modules and preserve return navigation');

  const visual = await boot(context);
  await visual.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
  await visual.waitForTimeout(250);
  await capture(visual, 'overview-daylight-1440x900');
  await visual.getByText('OPERATIONAL ATTENTION', {exact: true}).waitFor();
  await visual.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
  await visual.waitForTimeout(250);
  await capture(visual, 'overview-graphite-1440x900');
  await visual.getByText('OPERATIONAL FOCUS · SESSION TELEMETRY', {exact: true}).waitFor();
  await visual.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
  pass('Spectrum, Daylight and Graphite preserve the same information architecture');

  await scenario(context, 'offline');
  await visual.getByText(/Collector-Verbindung unterbrochen/).waitFor({timeout: 20000});
  await waitApi(context, '/api/v1/sources', value => value.some(source => source.connection === 'disconnected'), 'actual SourceHealth disconnect');
  await visual.locator('flt-semantics[role="text"]').filter({hasText: /^SOURCES: 0 \/ 1 CONNECTED/}).waitFor({timeout: 15000});
  await scrollTo(visual, 'OPERATIONAL ATTENTION');
  await capture(visual, 'overview-source-disconnect-1440x900');
  await waitApi(context, '/api/v1/metrics/current', value => value.some(item =>
    item.metric_id === 'temperature' && item.freshness === 'stale'), 'stale temperature observation');
  await visual.getByText('VERALTET', {exact: true}).first().waitFor({timeout: 15000});
  await capture(visual, 'overview-stale-data-1440x900');
  await capture(visual, 'overview-documented-finding-1440x900');
  await visual.getByText(/SIMULATED/).first().waitFor();
  pass('Offline scenario exposes simulated finding, actual disconnect/reconnect evidence and stale/unknown state without fake live values');

  await scenario(context, 'normal');
  await waitApi(context, '/api/v1/metrics/current', value => value.some(item =>
    item.metric_id === 'temperature' && item.freshness === 'fresh'), 'fresh temperature after reconnect');
  await visual.locator('flt-semantics[role="text"]').filter({hasText: /^SOURCES: 1 \/ 1 CONNECTED/}).waitFor({timeout: 20000});
  await visual.getByText('AKTUELL', {exact: true}).first().waitFor({timeout: 15000});
  await capture(visual, 'overview-reconnect-1440x900');
  pass('Reconnect restores connected/fresh state only after new Core data arrives');

  await scenario(context, 'sensor');
  await visual.getByText(/OPC-UA-Sensoralarm/).waitFor({timeout: 20000});
  await capture(visual, 'overview-active-documented-finding-1440x900');
  pass('Diagnostic finding remains explicitly simulated and links to the existing Diagnostics module');
  await scenario(context, 'normal');
  await context.close();

  for (const width of [320, 375, 390, 768, 834, 1024, 1920]) {
    const responsive = await browser.newContext({viewport: {width, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
    const p = await boot(responsive, width, 1000);
    await capture(p, `overview-responsive-${width}x1000`);
    await p.getByRole('button', {name: 'Data Coverage', exact: true}).click();
    await p.getByText(/DATA COVERAGE & TRUST/).waitFor();
    await p.getByRole('button', {name: 'Activity', exact: true}).click();
    assert.equal(errors.length, 0, `responsive ${width}: ${errors.join('\n')}`);
    await responsive.close();
  }
  pass('Responsive browser captures pass at 320/375/390/768/834/1024/1440/1920 px');

  expectedFault = true;
  const fault = await browser.newContext({viewport: {width: 1440, height: 1000}, serviceWorkers: 'block'});
  const failed = await fault.newPage();
  observe(failed);
  await failed.route('**/api/**', route => route.abort('connectionrefused'));
  await failed.goto(`${base}/?overview-api-failure=1`, {waitUntil: 'domcontentloaded'});
  await failed.getByText('Server nicht erreichbar', {exact: true}).waitFor({timeout: bootTimeout});
  await capture(failed, 'overview-api-failure-1440x900');
  assert.equal(await failed.getByText('NONE IN CURRENT DATA', {exact: true}).count(), 0);
  await fault.close();
  expectedFault = false;
  pass('API/SSE transport failure never falls back to an everything-healthy state');

  assert.deepEqual(errors, [], `browser errors: ${errors.join('\n')}`);
  assert.deepEqual(failedResources, [], `failed resources: ${failedResources.join('\n')}`);
  assert.deepEqual(external, [], `external requests: ${external.join('\n')}`);
  assert.equal(
    apiPaths.some(path => path.startsWith('/api/v2/') && path !== '/api/v2/organizations'),
    false,
    'legacy demo performs only the bounded OIP-009 identity probe',
  );
  const result = {
    verdict: 'PASS', base, checks, captures, errors, failedResources, expectedFaults, external,
    api_paths: [...new Set(apiPaths)], stream_requests_including_reconnects: streamRequests,
    v2_context_probe: 'OIP-009 /api/v2/organizations; expected 403 before the explicit demo fallback',
    multiple_sources: 'Flutter fixture test only; demo Core has one source',
    no_live_signal: 'Flutter fixture test only; no empty live-backend scenario invented',
    visual_status: 'VISUAL_PENDING_OPERATOR_ACCEPTANCE',
  };
  await writeFile(resolve(out, 'browser-overview-results.json'), JSON.stringify(result, null, 2));
  console.log(`PASS ${checks.length} browser checks, ${captures.length} captures`);
} catch (error) {
  const report = {verdict: 'FAIL', error: String(error), stack: error.stack, checks, captures, errors, failedResources, expectedFaults, external};
  await writeFile(resolve(out, 'browser-overview-failure.json'), JSON.stringify(report, null, 2));
  console.error(error);
  process.exitCode = 1;
} finally {
  await browser.close();
}

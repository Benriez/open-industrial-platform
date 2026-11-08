const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18773';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-diagnostics-2027');
await mkdir(out, {recursive: true});
for (const file of ['browser-diagnostics-failure.json', 'failure.png']) await rm(resolve(out, file), {force: true});
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined), headless: true});
const errors = [], external = [], failedResources = [], expectedFaults = [], checks = [], captures = [], geometry = [];
let expectedFault = false;
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function observe(page) {
  page.on('pageerror', error => (expectedFault ? expectedFaults : errors).push(error.message));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const identityProbe = message.text().includes('403');
    (expectedFault || identityProbe ? expectedFaults : errors).push(message.text());
  });
  page.on('response', response => {
    if (response.status() >= 400) {
      const identityProbe = response.status() === 403 &&
        new URL(response.url()).pathname === '/api/v2/organizations';
      (expectedFault || identityProbe ? expectedFaults : failedResources)
        .push(`${response.status()} ${response.url()}`);
    }
  });
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.origin !== new URL(base).origin) external.push(request.url());
  });
}
function pass(label) { checks.push(label); console.log('PASS', label); }
async function capture(page, name, fullPage = false) {
  await page.screenshot({path: resolve(out, `${name}.png`), fullPage});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `${name}: document overflow`);
}
async function scenario(context, name) {
  const response = await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: name}});
  assert.equal(response.status(), 200);
}
async function nav(page) {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (await menu.count()) {
    await menu.click();
    await page.getByText('Dismiss', {exact: true}).waitFor({state: 'visible'});
  }
  await page.getByRole('button', {name: 'Navigation Diagnose & Ereignisse', exact: true}).click();
  if (await menu.count()) await page.getByText('Dismiss', {exact: true}).waitFor({state: 'hidden'});
}
async function boot(context, width = 1440, height = 1000, suffix = '') {
  const page = await context.newPage();
  observe(page);
  await page.setViewportSize({width, height});
  await page.goto(`${base}/?diagnostics-2027=${width}x${height}${suffix}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav(page);
  const filters = page.getByRole('button', {name: /Explorer-Filter anzeigen/});
  if (await filters.count()) await filters.click();
  await page.getByRole('button', {name: /Evidence Timeline/}).first().click();
  if (width >= 1120) {
    await page.getByRole('button', {name: /Detail-Inspector manuell öffnen/}).click();
  }
  if (width < 600) {
    await page.getByRole('radio', {name: 'Explorer', exact: true}).click();
  }
  if (width < 600 || width >= 1200) await page.getByRole('button', {name: /Ereignis .* auswählen/}).first().waitFor();
  if (width >= 600) await page.getByRole('button', {name: /Telemetry:/}).first().waitFor();
  await page.waitForTimeout(700);
  return page;
}
async function records(context) {
  const response = await context.request.get(`${base}/api/v1/events`);
  assert.equal(response.status(), 200);
  const body = await response.json();
  return body.records.map(record => {
    const kind = Object.keys(record.event)[0];
    const event = record.event[kind];
    return {id: `${record.context.data_source_id}#${record.sequence}`, source: record.context.data_source_id, sequence: record.sequence, kind, ...event};
  });
}
async function search(page, value) {
  const field = page.getByRole('textbox').first();
  const clear = page.getByRole('button', {name: 'Suche löschen', exact: true});
  if (await clear.count()) await clear.click();
  await field.click();
  await page.keyboard.type(value, {delay: 8});
  await page.waitForTimeout(500);
}
async function selectRecord(page, id) {
  await search(page, id);
  const row = page.getByRole('button', {name: new RegExp(`Record ${escape(id)}`)});
  await row.waitFor();
  const viewport = page.viewportSize();
  for (let attempt = 0; attempt < 8; attempt++) {
    const box = await row.boundingBox();
    if (box && box.y >= 0 && box.y + box.height <= viewport.height) break;
    await page.mouse.move(viewport.width / 2, viewport.height * .65);
    await page.mouse.wheel(0, !box || box.y > viewport.height ? 520 : -520);
    await page.waitForTimeout(180);
  }
  await row.click({force: true});
  await page.waitForTimeout(300);
  if (viewport.width < 600 && !await page.getByText('Event ID / Record-ID', {exact: true}).count()) {
    await page.getByRole('radio', {name: 'Inspector', exact: true}).click();
  }
  // The subtitle is merged with the inspector title in CanvasKit semantics;
  // the record-ID field is the exposed selected-record contract.
  await page.getByText('Event ID / Record-ID', {exact: true}).waitFor({timeout: 8000});
}
async function timelineGeometry(page, label) {
  const markers = page.getByRole('button', {name: /Telemetry:/});
  const count = await markers.count();
  assert.ok(count > 0, `${label}: no markers`);
  const boxes = [];
  for (let index = 0; index < count; index++) {
    const box = await markers.nth(index).boundingBox();
    if (!box) continue;
    assert.ok(box.width >= 44 && box.height >= 44, `${label}: hitbox ${JSON.stringify(box)}`);
    boxes.push({index, ...box});
  }
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const a = boxes[i], b = boxes[j];
    const overlap = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
    assert.ok(overlap <= 1, `${label}: overlapping markers ${i}/${j}: ${overlap}`);
  }
  geometry.push({label, markers: boxes});
}

try {
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  context.grantPermissions(['clipboard-read', 'clipboard-write'], {origin: base});
  await scenario(context, 'normal');
  let apiRecords = await records(context);
  assert.ok(apiRecords.some(item => item.kind === 'ConnectionLost'));
  const first = apiRecords.find(item => item.kind === 'ConnectionLost');
  const gap = apiRecords.find(item => item.kind === 'Reconnected' && item.gap?.ended_at >= item.gap?.started_at) ?? apiRecords.find(item => item.kind === 'Reconnected');

  const page = await boot(context);
  await capture(page, 'diagnostics-initial-1440x1000');
  await timelineGeometry(page, 'initial-1440');
  pass('Initial desktop workstation exposes Explorer, source-lane Timeline and Inspector with bounded-history notice');

  await selectRecord(page, first.id);
  await page.getByText('Severity', {exact: true}).waitFor();
  await page.getByText('Nicht vom Core geliefert', {exact: true}).waitFor();
  await page.getByText('Clock Uncertainty', {exact: true}).waitFor();
  await capture(page, 'diagnostics-selected-event-1440x1000');
  pass('Record-ID search selects the same event in Explorer and technical Inspector without inventing severity or timestamps');

  await page.getByRole('button', {name: 'Timeline vergrößern', exact: true}).click();
  await page.waitForTimeout(300);
  await capture(page, 'diagnostics-timeline-zoom-1440x1000');
  await page.getByRole('button', {name: 'Timeline nach rechts', exact: true}).click();
  await page.getByRole('button', {name: 'Fit to Available Data', exact: true}).click();
  await page.waitForTimeout(300);
  await timelineGeometry(page, 'fit-1440');
  pass('Timeline zoom, pan and Fit preserve exact hitboxes and non-overlapping event groups');

  const group = page.getByRole('button', {name: /Telemetry: .*Ereignisse, .*Gruppe öffnen/}).first();
  if (await group.count()) {
    await group.click();
    await page.getByText(/zeitnahe Ereignisse/).waitFor();
    await capture(page, 'diagnostics-density-group-1440x1000');
    await page.getByText('Schließen', {exact: true}).click();
  }
  pass('Dense timeline groups disclose their actual members and time bounds when present');

  apiRecords = await records(context);
  const currentGap = apiRecords.find(item => item.kind === 'Reconnected' && item.gap?.ended_at >= item.gap?.started_at) ?? apiRecords[0];
  await selectRecord(page, currentGap.id);
  await page.getByRole('button', {name: 'Ereignis anheften', exact: true}).last().click();
  await page.getByRole('button', {name: 'Zu Compare hinzufügen', exact: true}).last().click();
  apiRecords = await records(context);
  const currentFirst = apiRecords.find(item => item.kind === 'ConnectionLost' && item.id !== currentGap.id) ?? apiRecords.find(item => item.id !== currentGap.id);
  await selectRecord(page, currentFirst.id);
  await page.getByRole('button', {name: 'Zu Compare hinzufügen', exact: true}).last().click();
  await page.getByRole('button', {name: 'Vergleich schließen', exact: true}).waitFor();
  await capture(page, 'diagnostics-event-compare-1440x1000');
  pass('Pins, recents and independent two-event Compare remain session-local without time-alignment claims');

  await page.getByText('Collection Health', {exact: true}).click();
  await page.getByText('Source-Diagnostik & dokumentierte Datenlücken', {exact: true}).waitFor();
  await capture(page, 'diagnostics-collection-health-1440x1000');
  pass('Collection Health combines actual current Source fields with loaded reconnect/gap evidence');

  await scenario(context, 'gpu');
  await page.getByText('Incidents', {exact: true}).click();
  await page.getByRole('button', {name: /Betroffenes Gerät: AMD EVO-X2/}).waitFor();
  await capture(page, 'diagnostics-deterministic-demo-finding-1440x1000');
  await scenario(context, 'normal');
  pass('Demo Incident evidence remains separate from observed events and no Core rule evaluation is reconstructed');

  await scenario(context, 'offline');
  await page.waitForTimeout(8000);
  await page.getByRole('button', {name: 'Diagnosedaten aktualisieren', exact: true}).click();
  await page.waitForTimeout(700);
  apiRecords = await records(context);
  const reconnected = apiRecords.find(item => item.kind === 'Reconnected' && item.gap);
  await page.getByText('Timeline', {exact: true}).first().click();
  await selectRecord(page, reconnected.id);
  await page.getByText('DATA GAP', {exact: true}).waitFor();
  await capture(page, 'diagnostics-reconnect-investigation-1440x1000');
  await scenario(context, 'normal');
  pass('Real offline/reconnect cycle exposes delivered event timing and gap bounds without claiming fresh complete metrics');

  // Fresh selected state for theme review.
  await page.getByText('Timeline', {exact: true}).first().click();
  apiRecords = await records(context);
  const themeEvent = apiRecords.find(item => item.kind === 'Reconnected') ?? apiRecords[0];
  await selectRecord(page, themeEvent.id);
  for (const theme of ['GRAPHITE', 'DAYLIGHT', 'SPECTRUM']) {
    for (let attempt = 0; attempt < 3 && !await page.getByText(theme, {exact: true}).count(); attempt++) {
      await page.mouse.move(700, 150);
      await page.waitForTimeout(300);
      await page.getByRole('button', {name: /Darstellung wechseln/}).click();
      await page.waitForTimeout(150);
    }
    await page.getByText(theme, {exact: true}).waitFor();
    await capture(page, `diagnostics-${theme.toLowerCase()}-1440x1000`);
  }
  pass('Spectrum, Graphite and Daylight preserve the same workstation semantics');
  await page.close();

  // Responsive matrix: real Core data, fresh page per width.
  for (const width of [320, 375, 390, 768, 834, 1024, 1920]) {
    const height = width < 600 ? 900 : width === 1920 ? 1080 : 1000;
    const responsive = await boot(context, width, height, `-responsive-${width}`);
    await capture(responsive, `diagnostics-initial-${width}x${height}`);
    if (width < 600) {
      await responsive.getByRole('radio', {name: 'Timeline', exact: true}).click();
      await responsive.getByRole('button', {name: /Telemetry:/}).first().waitFor();
      await capture(responsive, `diagnostics-timeline-${width}x${height}`);
      const latest = (await records(context))[0];
      await responsive.getByRole('radio', {name: 'Explorer', exact: true}).click();
      await selectRecord(responsive, latest.id);
      await responsive.getByText('Event ID / Record-ID', {exact: true}).waitFor();
      await capture(responsive, `diagnostics-selected-${width}x${height}`);
    } else if (width < 1200) {
      await responsive.getByText('Explorer öffnen', {exact: true}).click();
      await responsive.getByRole('button', {name: /Ereignis .* auswählen/}).first().waitFor();
      await capture(responsive, `diagnostics-explorer-open-${width}x${height}`);
      await responsive.getByText('Explorer schließen', {exact: true}).click();
      await responsive.getByText('Inspector öffnen', {exact: true}).click();
      await capture(responsive, `diagnostics-inspector-open-${width}x${height}`);
    } else {
      await timelineGeometry(responsive, `desktop-${width}`);
      await capture(responsive, `diagnostics-workstation-${width}x${height}`);
    }
    await responsive.close();
  }
  pass('Fresh real-data captures cover 320/375/390/768/834/1024/1440/1920 with mobile panes and collapsible tablet panels');

  // Deliberate post-initial API failure: stale evidence must stay marked.
  const fault = await boot(context, 1440, 1000, '-api-fault');
  await fault.route('**/api/v1/events', async route => {
    expectedFault = true;
    await route.fulfill({status: 503, contentType: 'application/json', body: JSON.stringify({code: 'TEST_TIMEOUT', message: 'Diagnostics API test timeout'})});
  });
  await fault.getByRole('button', {name: 'Diagnosedaten aktualisieren', exact: true}).click();
  await fault.locator('flt-semantics[aria-label*="Collection-Ereignisse nicht verfügbar"]').waitFor();
  await fault.locator('flt-semantics[aria-label*="Angezeigte Events sind der letzte erfolgreiche, jetzt stale Stand"]').waitFor();
  await capture(fault, 'diagnostics-api-error-stale-1440x1000');
  await fault.unroute('**/api/v1/events');
  expectedFault = false;
  await fault.close();
  pass('Post-initial API failure preserves but explicitly marks stale evidence; expected fault telemetry is separate');

  // Empty local filter, distinct from a backend-empty fixture covered by widget tests.
  const empty = await boot(context, 1440, 1000, '-empty-filter');
  await search(empty, 'not-present-in-loaded-history');
  await empty.getByText('Keine Collection-Ereignisse geliefert', {exact: true}).waitFor();
  await capture(empty, 'diagnostics-empty-filter-1440x1000');
  await empty.close();
  pass('Empty loaded-filter state does not claim empty server history');

  assert.deepEqual(errors, [], `browser errors: ${errors.join('\n')}`);
  assert.deepEqual(external, [], `external requests: ${external.join('\n')}`);
  assert.deepEqual(failedResources, [], `failed resources: ${failedResources.join('\n')}`);
  const report = {
    verdict: 'PASS', browser: await browser.version(), base,
    checks, captures, geometry, errors, externalRequests: external, failedResources, expectedFaults,
    liveData: {sourceCount: 1, scenarioApi: '/api/v1/demo/scenario', eventApi: '/api/v1/events'},
    limits: [
      'The demo Core has one source; multi-source lane behavior and coincident timestamps are covered by widget fixtures, not claimed as a live multi-source backend test.',
      'True zero-event and large-list rendering are widget-fixture evidence; the live Core persists startup/reconnect control events.',
      'Browser geometry is release CanvasKit evidence, not screen-reader certification or native raster profiling.',
    ],
  };
  await writeFile(resolve(out, 'browser-diagnostics.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length, captures: captures.length, geometry: geometry.length, expectedFaults: expectedFaults.length}, null, 2));
} catch (error) {
  for (const context of browser.contexts()) {
    for (const openPage of context.pages()) {
      await openPage.screenshot({path: resolve(out, 'failure.png')}).catch(() => {});
    }
  }
  await writeFile(resolve(out, 'browser-diagnostics-failure.json'), JSON.stringify({verdict: 'FAIL', error: String(error), checks, captures, errors, external, failedResources, expectedFaults}, null, 2));
  throw error;
} finally {
  await browser.close();
}

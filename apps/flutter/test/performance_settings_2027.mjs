const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_SETTINGS_URL ?? 'http://127.0.0.1:18945';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/performance-settings-2027');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const stats = values => {
  if (!values.length) return {samples: [], medianMs: null, p95Ms: null, maxMs: null};
  const sorted = [...values].sort((a, b) => a - b);
  const q = p => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  return {samples: values, medianMs: q(.5), p95Ms: q(.95), maxMs: sorted.at(-1)};
};
async function heap(page, label) {
  return {
    label,
    ...(await page.evaluate(() => performance.memory ? {
      used: performance.memory.usedJSHeapSize,
      total: performance.memory.totalJSHeapSize,
      limit: performance.memory.jsHeapSizeLimit,
    } : {used: null, total: null, limit: null})),
  };
}
async function nav(page, label) {
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
}
async function openSettings(page) {
  await page.goto(`${base}/?performance-settings=1`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor({timeout: 30000});
  await nav(page, 'Einstellungen');
  await page.getByText('SETTINGS · APPLICATION MANAGEMENT', {exact: true}).waitFor({timeout: 30000});
  await page.getByText('OFFLINE ADMINISTRATION REQUIRED', {exact: true}).first().waitFor({timeout: 30000});
  await page.waitForTimeout(600);
}
async function category(page, label) {
  await page.getByRole('button', {name: new RegExp(`Settings-Kategorie ${label}`)}).first().click({force: true});
  await page.waitForTimeout(250);
}
async function section(page, label) {
  await page.getByRole('button', {name: new RegExp(`Settings-Bereich ${label}`)}).first().click({force: true});
  await page.waitForTimeout(300);
}
async function search(page, value) {
  const box = page.getByRole('textbox', {name: /Tool, Capability/}).first();
  await box.waitFor();
  const clear = page.getByRole('button', {name: 'Suche löschen', exact: true});
  if (await clear.count()) {
    await clear.first().click({force: true});
    await page.waitForTimeout(120);
  }
  await box.click();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Backspace');
  let current = await box.inputValue().catch(() => '');
  for (let i = 0; i < 80 && current.length; i++) {
    await page.keyboard.press('Backspace');
    current = await box.inputValue().catch(() => '');
  }
  if (value) await page.keyboard.type(value, {delay: 4});
  await page.waitForTimeout(80);
}

const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
const page = await context.newPage();
const cdp = await context.newCDPSession(page);
const errors = [], boundaryResponses = [], v2Requests = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() !== 'error') return;
  const text = message.text();
  if (/^Failed to load resource: the server responded with a status of \d+/.test(text)) {
    boundaryResponses.push(text);
    return;
  }
  errors.push(text);
});
page.on('response', response => {
  if (response.status() >= 400) boundaryResponses.push(`${response.status()} ${response.url()}`);
});
page.on('request', request => {
  if (new URL(request.url()).pathname.startsWith('/api/v2/')) v2Requests.push(request.url());
});

try {
  await openSettings(page);
  await cdp.send('HeapProfiler.collectGarbage');
  await page.waitForTimeout(150);
  const heapInitial = await heap(page, 'initial-after-open-and-gc');
  await page.evaluate(() => {
    window.__oipSettings = {deltas: [], longTasks: [], stop: false};
    let previous = performance.now();
    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) window.__oipSettings.longTasks.push({start: entry.startTime, duration: entry.duration});
      }).observe({entryTypes: ['longtask']});
    } catch {}
    function frame(now) {
      window.__oipSettings.deltas.push(now - previous);
      previous = now;
      if (!window.__oipSettings.stop) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });

  const applicationMs = [], settingsSelectMs = [];
  let start = performance.now();
  await category(page, 'General');
  await page.getByText('Application Settings', {exact: true}).waitFor();
  applicationMs.push(performance.now() - start);

  for (let index = 0; index < 6; index++) {
    const row = page.getByRole('button', {name: /Setting history_page_size/}).first();
    await row.waitFor();
    await row.scrollIntoViewIfNeeded();
    start = performance.now();
    await row.click({force: true});
    await page.getByText('SETTING INSPECTOR', {exact: true}).first().waitFor();
    settingsSelectMs.push(performance.now() - start);
    await page.waitForTimeout(40);
  }

  const searchMs = [], toolSelectMs = [], inspectorMs = [];
  await category(page, 'MCP & Agents');
  await section(page, 'Tools & Capabilities');
  await page.getByText('18 registrierte Tools', {exact: false}).waitFor({timeout: 30000});
  for (const query of ['not-present', 'oip_settings_read', 'settings', '']) {
    start = performance.now();
    await search(page, query);
    await page.waitForTimeout(20);
    searchMs.push(performance.now() - start);
  }
  for (let index = 0; index < 6; index++) {
    await search(page, 'oip_settings_read');
    const row = page.getByRole('button', {name: /MCP Tool oip_settings_read/}).first();
    await row.waitFor();
    start = performance.now();
    await row.click({force: true});
    await page.getByText('TOOL INSPECTOR', {exact: true}).first().waitFor();
    toolSelectMs.push(performance.now() - start);
    inspectorMs.push(performance.now() - start);
    await page.waitForTimeout(40);
  }
  const jsonRenderMs = [];
  const viewport = page.viewportSize();
  for (let index = 0; index < 6; index++) {
    start = performance.now();
    // The inspector is a bounded 660px list; scroll once to the JSON block and
    // its schema toggles, then measure a full output/input re-render cycle.
    await page.mouse.move(viewport.width - 140, viewport.height * 0.55);
    await page.mouse.wheel(0, 900);
    await page.getByRole('button', {name: 'Schema kopieren', exact: true}).first().waitFor({timeout: 10000});
    await page.getByRole('button', {name: 'Output Schema', exact: true}).first().click({force: true});
    await page.waitForTimeout(60);
    await page.getByRole('button', {name: 'Input Schema', exact: true}).first().click({force: true});
    await page.waitForTimeout(60);
    jsonRenderMs.push(performance.now() - start);
  }

  // Bounded state: each module re-entry performs its section read once, and the
  // workstation is idle (no timer/polling) between entries.
  await search(page, '');
  const beforeIdle = v2Requests.length;
  await page.waitForTimeout(3000);
  const idleRequests = v2Requests.length - beforeIdle;
  assert.equal(idleRequests, 0, 'idle management polling');

  const navigationMs = [];
  const perEntry = [];
  for (let index = 0; index < 5; index++) {
    const before = v2Requests.length;
    start = performance.now();
    await nav(page, 'Übersicht');
    await page.getByText('Operations Workstation', {exact: true}).waitFor();
    await nav(page, 'Einstellungen');
    await page.getByText('MCP Tool & Capability Explorer', {exact: true}).waitFor({timeout: 30000});
    navigationMs.push(performance.now() - start);
    await page.waitForTimeout(350);
    perEntry.push(v2Requests.length - before);
  }
  // Bound: tools section = primary tools read + optional server read.
  assert.ok(perEntry.every(count => count <= 2), `per-entry management reads ${perEntry.join(',')}`);
  assert.ok(Math.max(...perEntry) - Math.min(...perEntry) <= 2, 'no per-entry growth');

  const semanticsBefore = await page.locator('flt-semantics').count();
  for (let index = 0; index < 5; index++) {
    await nav(page, 'Übersicht');
    await nav(page, 'Einstellungen');
    await page.getByText('MCP Tool & Capability Explorer', {exact: true}).waitFor({timeout: 30000});
  }
  await page.waitForTimeout(300);
  const semanticsAfter = await page.locator('flt-semantics').count();
  assert.ok(semanticsAfter - semanticsBefore < 120, `semantics grew ${semanticsBefore} -> ${semanticsAfter}`);

  await page.waitForTimeout(1600);
  const heapFinal = await heap(page, 'final-after-idle');
  await cdp.send('HeapProfiler.collectGarbage');
  await page.waitForTimeout(150);
  const heapAfterGC = await heap(page, 'final-after-explicit-gc');
  const measured = await page.evaluate(() => {
    window.__oipSettings.stop = true;
    return {deltas: window.__oipSettings.deltas.slice(1), longTasks: window.__oipSettings.longTasks};
  });
  const frames = stats(measured.deltas);

  assert.deepEqual(errors, []);
  assert.ok(boundaryResponses.every(line => /(403|404)/.test(line)), 'only expected 4xx boundaries');
  const result = {
    verdict: 'PASS',
    fixture_only: true,
    real_event_ingestion: false,
    backend_scaling_proof: false,
    browser: await browser.version(),
    base,
    conditions: 'Chrome headless, release CanvasKit, 1440x1000, DPR 1, sanitized OIP-008.4 contract fixture served with x-oip-contract-fixture; v1 data from isolated local Core through the server-side test harness.',
    catalogTools: 18,
    catalogSettings: 3,
    frameMedianMs: frames.medianMs,
    frameP95Ms: frames.p95Ms,
    frameMaxMs: frames.maxMs,
    frames: measured.deltas.length,
    longTasks: measured.longTasks,
    applicationSectionMs: stats(applicationMs),
    settingSelectionMs: stats(settingsSelectMs),
    toolSearchMs: stats(searchMs),
    toolSelectionMs: stats(toolSelectMs),
    toolSelectionToInspectorMs: stats(inspectorMs),
    jsonSchemaRenderMs: stats(jsonRenderMs),
    navigationRoundTripMs: stats(navigationMs),
    branches: {
      idleManagementRequestsIn3s: idleRequests,
      managementReadsPerModuleEntry: perEntry,
      semanticsNodesBefore: semanticsBefore,
      semanticsNodesAfter: semanticsAfter,
    },
    heap: {
      initial: heapInitial,
      final: heapFinal,
      afterGC: heapAfterGC,
      usedDelta: heapInitial.used == null ? null : heapFinal.used - heapInitial.used,
      retainedDeltaAfterGC: heapInitial.used == null ? null : heapAfterGC.used - heapInitial.used,
    },
    errors,
    expectedHttpBoundaryResponses: boundaryResponses,
    method: 'Fresh requestAnimationFrame frame pacing and PerformanceObserver longtask measurements while switching settings sections, selecting settings and tools, rendering JSON schemas and navigating modules. Action latency includes Playwright IPC and keyboard delay. management.memory is sampled after opening, after idle and after final explicit GC. UI-only contract-fixture benchmark; no real ingestion, backend throughput, SLA, production capacity or memory-leak certification.',
  };
  await writeFile(resolve(out, 'performance-settings-2027.json'), `${JSON.stringify(result, null, 2)}\n`);
  console.log(JSON.stringify({
    verdict: result.verdict,
    frameMedianMs: result.frameMedianMs,
    frameP95Ms: result.frameP95Ms,
    longTasks: result.longTasks.length,
    retainedDeltaAfterGC: result.heap.retainedDeltaAfterGC,
    idleManagementRequestsIn3s: idleRequests,
    managementReadsPerModuleEntry: perEntry,
  }, null, 2));
} finally {
  await browser.close();
}

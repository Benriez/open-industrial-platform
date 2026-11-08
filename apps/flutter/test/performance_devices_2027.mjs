const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/performance-devices-2027');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const scenarios = [
  {mode: 'zero', count: 0, base: process.env.OIP_DEVICES_ZERO_URL ?? 'http://127.0.0.1:18924'},
  {mode: 'one', count: 1, base: process.env.OIP_DEVICES_ONE_URL ?? 'http://127.0.0.1:18925', rows: [['Fixture M-01', 'M-01']]},
  {mode: 'seventeen', count: 17, base: process.env.OIP_DEVICES_SEVENTEEN_URL ?? 'http://127.0.0.1:18926', rows: [['Fixture M-01', 'M-01'], ['Fixture sz-01', 'sz-01']]},
  {mode: 'large', count: 120, base: process.env.OIP_DEVICES_LARGE_URL ?? 'http://127.0.0.1:18927', rows: [['Fixture inv-001', 'inv-001'], ['Fixture inv-002', 'inv-002']]},
];
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const stats = values => {
  if (!values.length) return {samples: [], medianMs: null, p95Ms: null, maxMs: null};
  const sorted = [...values].sort((a, b) => a - b);
  const q = p => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  return {samples: values, medianMs: q(.5), p95Ms: q(.95), maxMs: sorted.at(-1)};
};
async function heap(page, label) {
  return {label, ...(await page.evaluate(() => performance.memory ? {
    used: performance.memory.usedJSHeapSize,
    total: performance.memory.totalJSHeapSize,
    limit: performance.memory.jsHeapSizeLimit,
  } : {used: null, total: null, limit: null}))};
}
async function nav(page, label) {
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
}
async function boot(page, base, mode) {
  await page.goto(`${base}/?performance-devices=${mode}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav(page, 'Geräte & Dienste');
  await page.getByText('DEVICES & SERVICES · ENGINEERING WORKSTATION', {exact: true}).waitFor();
  await page.waitForTimeout(700);
}
async function setSearch(page, value) {
  // Escape clears a previously focused Devices search without Select-All.
  await page.keyboard.press('Escape');
  await page.keyboard.press('/');
  if (value) await page.keyboard.type(value, {delay: 4});
  await page.waitForTimeout(60);
}

const results = [];
try {
  for (const scenario of scenarios) {
    const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    const errors = [], failedResources = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error') errors.push(message.text());
    });
    page.on('response', response => {
      if (response.status() >= 400) failedResources.push(`${response.status()} ${response.url()}`);
    });
    await boot(page, scenario.base, scenario.mode);
    await page.getByText(`${scenario.count} von ${scenario.count} Geräten · Simuliertes Inventar`, {exact: true}).waitFor();
    await cdp.send('HeapProfiler.collectGarbage');
    await page.waitForTimeout(150);
    const heapInitial = await heap(page, 'initial-after-settle-and-gc');
    await page.evaluate(() => {
      window.__oipDevices = {deltas: [], longTasks: [], stop: false};
      let previous = performance.now();
      try {
        new PerformanceObserver(list => {
          for (const entry of list.getEntries()) window.__oipDevices.longTasks.push({start: entry.startTime, duration: entry.duration});
        }).observe({entryTypes: ['longtask']});
      } catch {}
      function frame(now) {
        window.__oipDevices.deltas.push(now - previous);
        previous = now;
        if (!window.__oipDevices.stop) requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    });

    const filterMs = [], selectionMs = [], inspectorMs = [], navigationMs = [];
    for (const query of ['not-present', 'Fixture', 'M-01', '']) {
      const start = performance.now();
      await setSearch(page, query);
      filterMs.push(performance.now() - start);
    }

    if (scenario.rows) {
      for (let index = 0; index < 8; index++) {
        const [name, id] = scenario.rows[index % scenario.rows.length];
        const row = page.getByRole('button', {name: new RegExp(`Gerät ${escape(name)} ${escape(id)} auswählen`)}).first();
        await row.scrollIntoViewIfNeeded();
        const start = performance.now();
        await row.click({force: true});
        await page.getByText('ENGINEERING WORKSPACE', {exact: true}).waitFor();
        selectionMs.push(performance.now() - start);
        await page.getByText(name, {exact: true}).first().waitFor();
        inspectorMs.push(performance.now() - start);
        await page.waitForTimeout(35);
      }
    }

    for (let index = 0; index < 4; index++) {
      const start = performance.now();
      await nav(page, 'Übersicht');
      await page.getByText('Operations Workstation', {exact: true}).waitFor();
      await nav(page, 'Geräte & Dienste');
      await page.getByText('DEVICES & SERVICES · ENGINEERING WORKSTATION', {exact: true}).waitFor();
      navigationMs.push(performance.now() - start);
    }

    let paginationMs = null;
    if (scenario.mode === 'large') {
      const start = performance.now();
      await page.getByRole('button', {name: 'Nächste Geräte', exact: true}).click();
      await page.getByText('Seite 2 / 3', {exact: true}).waitFor();
      await page.getByRole('button', {name: 'Vorherige Geräte', exact: true}).click();
      await page.getByText('Seite 1 / 3', {exact: true}).waitFor();
      paginationMs = performance.now() - start;
    }

    await page.waitForTimeout(1800);
    const heapFinal = await heap(page, 'final-after-idle');
    await cdp.send('HeapProfiler.collectGarbage');
    await page.waitForTimeout(150);
    const heapAfterGC = await heap(page, 'final-after-explicit-gc');
    const measured = await page.evaluate(() => {
      window.__oipDevices.stop = true;
      return {deltas: window.__oipDevices.deltas.slice(1), longTasks: window.__oipDevices.longTasks};
    });
    const frames = stats(measured.deltas);
    assert.deepEqual(errors, [], `${scenario.mode}: ${errors.join('\n')}`);
    assert.deepEqual(failedResources, [], `${scenario.mode}: failed resources`);
    const result = {
      verdict: 'PASS', mode: scenario.mode, inventoryDevices: scenario.count,
      fixture_only: true, synthetic_inventory: true, real_ingestion: false, backend_scaling_proof: false,
      browser: await browser.version(), base: scenario.base,
      conditions: 'Chrome headless, release CanvasKit, 1440x1000, DPR 1, explicit local synthetic UI fixture.',
      frameMedianMs: frames.medianMs, frameP95Ms: frames.p95Ms, frameMaxMs: frames.maxMs,
      frames: measured.deltas.length, longTasks: measured.longTasks,
      filterMs: stats(filterMs), selectionMs: stats(selectionMs),
      selectionToInspectorMs: stats(inspectorMs), navigationRoundTripMs: stats(navigationMs),
      paginationNextPreviousMs: paginationMs,
      heap: {
        initial: heapInitial, final: heapFinal, afterGC: heapAfterGC,
        usedDelta: heapInitial.used == null ? null : heapFinal.used - heapInitial.used,
        retainedDeltaAfterGC: heapInitial.used == null ? null : heapAfterGC.used - heapInitial.used,
      },
      errors, failedResources,
      method: 'Fresh requestAnimationFrame frame pacing and PerformanceObserver longtask measurements during filter, selection, inspector and module-navigation workflows. Action latency includes Playwright IPC and keyboard delay. performance.memory is sampled after initial GC, after idle, and after final explicit GC for retained-delta evidence. UI-only fixture benchmark; no real ingestion, backend throughput, SLA, memory-leak certification, or server-side pagination claim.',
    };
    results.push(result);
    await writeFile(resolve(out, `performance-devices-${scenario.mode}.json`), JSON.stringify(result, null, 2));
    console.log(JSON.stringify({mode: scenario.mode, verdict: result.verdict, frameP95Ms: result.frameP95Ms, retainedDeltaAfterGC: result.heap.retainedDeltaAfterGC}));
    await context.close();
  }
  await writeFile(resolve(out, 'performance-devices-summary.json'), JSON.stringify({
    verdict: 'PASS', fixture_only: true, real_ingestion: false, backend_scaling_proof: false,
    inventories: results.map(result => ({mode: result.mode, devices: result.inventoryDevices, frameMedianMs: result.frameMedianMs, frameP95Ms: result.frameP95Ms, longTaskCount: result.longTasks.length, retainedDeltaAfterGC: result.heap.retainedDeltaAfterGC})),
    results,
  }, null, 2));
} finally {
  await browser.close();
}

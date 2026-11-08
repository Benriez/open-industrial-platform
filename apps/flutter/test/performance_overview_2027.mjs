const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18910';
const baseline = process.env.OIP_PERF_BASELINE === '1';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/performance-overview-phase2');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined), headless: true});
const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
const page = await context.newPage();
const cdp = await context.newCDPSession(page);
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
const stats = values => {
  const sorted = [...values].sort((a, b) => a - b);
  const q = p => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  return {samples: values, medianMs: q(.5), p95Ms: q(.95), maxMs: sorted.at(-1)};
};
async function heap(label) {
  return {label, ...(await page.evaluate(() => performance.memory ? {
    used: performance.memory.usedJSHeapSize,
    total: performance.memory.totalJSHeapSize,
    limit: performance.memory.jsHeapSizeLimit,
  } : {used: null, total: null, limit: null}))};
}

try {
  const scenario = await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: 'normal'}});
  if (scenario.status() !== 200) throw new Error(`scenario ${scenario.status()}`);
  await page.goto(`${base}/?performance-overview=${baseline ? 'baseline' : '2027'}`, {waitUntil: 'domcontentloaded'});
  await page.getByText(baseline ? 'Deine Infrastruktur. Ein Bild.' : 'Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  if (!baseline) await page.getByText('OPERATIONAL FOCUS · SESSION TELEMETRY', {exact: true}).waitFor();
  await page.waitForTimeout(1200);
  await cdp.send('HeapProfiler.collectGarbage');
  await page.waitForTimeout(250);
  const heapInitial = await heap('initial-after-settle-and-gc');
  await page.evaluate(() => {
    window.__oipOverview = {deltas: [], longTasks: [], stop: false};
    let previous = performance.now();
    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) window.__oipOverview.longTasks.push({start: entry.startTime, duration: entry.duration});
      }).observe({entryTypes: ['longtask']});
    } catch {}
    function frame(now) {
      window.__oipOverview.deltas.push(now - previous);
      previous = now;
      if (!window.__oipOverview.stop) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });

  const sampleMs = [], filterMs = [], navigationMs = [], themeMs = [];
  const traceEvents = [];
  cdp.on('Tracing.dataCollected', event => traceEvents.push(...event.value));
  await cdp.send('Tracing.start', {categories: 'devtools.timeline', transferMode: 'ReportEvents'});
  if (!baseline) {
    for (let index = 0; index < 12; index++) {
      const start = performance.now();
      await page.getByRole('button', {name: index % 2 ? 'Vorheriges Sample' : 'Nächstes Sample', exact: true}).click();
      await page.waitForTimeout(45);
      sampleMs.push(performance.now() - start);
    }
    for (const label of ['Alle gelieferten', 'Reconnected', 'ConnectionLost', 'Alle gelieferten']) {
      const start = performance.now();
      await page.getByRole('button', {name: /^EVENT-TYP/}).click();
      await page.getByText(label, {exact: true}).last().click();
      await page.waitForTimeout(60);
      filterMs.push(performance.now() - start);
    }
  }
  for (let index = 0; index < 6; index++) {
    const start = performance.now();
    await page.getByRole('button', {name: 'Navigation OPC-UA-Browser', exact: true}).click();
    await page.getByText('Namespace 2', {exact: true}).waitFor();
    await page.getByRole('button', {name: 'Navigation Übersicht', exact: true}).click();
    await page.getByText(baseline ? 'Deine Infrastruktur. Ein Bild.' : 'Operations Workstation', {exact: true}).waitFor();
    navigationMs.push(performance.now() - start);
  }
  for (let index = 0; index < 6; index++) {
    const start = performance.now();
    await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
    await page.waitForTimeout(80);
    themeMs.push(performance.now() - start);
  }
  const traceComplete = new Promise(resolve => cdp.once('Tracing.tracingComplete', resolve));
  await cdp.send('Tracing.end');
  await traceComplete;
  await page.waitForTimeout(2500);
  const heapFinal = await heap('final-after-idle');
  await cdp.send('HeapProfiler.collectGarbage');
  await page.waitForTimeout(250);
  const heapAfterGC = await heap('final-after-explicit-gc');
  const metrics = await page.evaluate(() => {
    window.__oipOverview.stop = true;
    return {deltas: window.__oipOverview.deltas.slice(1), longTasks: window.__oipOverview.longTasks};
  });
  const frameStats = stats(metrics.deltas);
  const result = {
    verdict: errors.length === 0 ? 'PASS' : 'FAIL', baseline, browser: await browser.version(), base,
    conditions: 'Chrome headless, release CanvasKit, 1440x1000, DPR 1, actual local normal demo scenario.',
    frameMedianMs: frameStats.medianMs, frameP95Ms: frameStats.p95Ms, frameMaxMs: frameStats.maxMs,
    frames: metrics.deltas.length, longTasks: metrics.longTasks,
    sampleSelectionMs: baseline ? null : stats(sampleMs),
    eventFilterMs: baseline ? null : stats(filterMs),
    navigationRoundTripMs: stats(navigationMs), themeSwitchMs: stats(themeMs),
    chartRenderingTrace: {
      paintEvents: traceEvents.filter(event => event.name === 'Paint').length,
      rasterTasks: traceEvents.filter(event => event.name === 'RasterTask').length,
      drawFrames: traceEvents.filter(event => event.name === 'DrawFrame').length,
    },
    heap: {
      initial: heapInitial,
      final: heapFinal,
      afterGC: heapAfterGC,
      usedDelta: heapInitial.used == null ? null : heapFinal.used - heapInitial.used,
      retainedDeltaAfterGC: heapInitial.used == null ? null : heapAfterGC.used - heapInitial.used,
    },
    errors,
    method: 'requestAnimationFrame frame pacing, PerformanceObserver longtask, Playwright action latency including IPC, devtools.timeline Paint/RasterTask/DrawFrame, performance.memory before/after plus explicit-GC retained snapshots. UI rendering benchmark only; no backend throughput claim.',
  };
  await writeFile(resolve(out, baseline ? 'performance-overview-baseline.json' : 'performance-overview.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
  if (errors.length) process.exitCode = 1;
} finally {
  await browser.close();
}

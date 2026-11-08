const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18772';
const baseline = process.env.OIP_PERF_BASELINE === '1';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/performance');
await mkdir(out, {recursive: true});
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
const page = await context.newPage();
const cdp = await context.newCDPSession(page);
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const quantile = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
const stats = values => {
  const sorted = [...values].sort((a, b) => a - b);
  return {samples: values, medianMs: quantile(sorted, .5), p95Ms: quantile(sorted, .95), maxMs: sorted.at(-1)};
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
  await page.goto(`${base}/?performance-network=${baseline ? 'baseline' : 'phase2'}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await page.getByRole('button', {name: 'Navigation Netzwerk & VPN', exact: true}).click();
  await page.getByText('Logische Topologie', {exact: true}).first().waitFor();
  await page.getByText('5 PFADE', {exact: true}).waitFor();
  await page.waitForTimeout(1000);
  const heapInitial = await heap('initial-after-settle');

  await page.evaluate(() => {
    window.__oipNet = {deltas: [], longTasks: [], stop: false};
    let previous = performance.now();
    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) {
          window.__oipNet.longTasks.push({start: entry.startTime, duration: entry.duration});
        }
      }).observe({entryTypes: ['longtask']});
    } catch {}
    function frame(now) {
      window.__oipNet.deltas.push(now - previous);
      previous = now;
      if (!window.__oipNet.stop) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });

  const searchMs = [], explorerSelectionMs = [];
  if (!baseline) {
    for (const query of ['Remote', 'pi3', 'evo', 'router', 'no-such-device']) {
      const start = performance.now();
      await page.keyboard.press('ControlOrMeta+K');
      await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.type(query, {delay: 8});
      await page.waitForTimeout(100);
      searchMs.push(performance.now() - start);
    }
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(250);

    for (const name of ['Remote-Linux-Server', 'RDP-Server', 'AMD EVO-X2', 'Remote-Windows-Server']) {
      const start = performance.now();
      await page.getByRole('button', {name: new RegExp(`Gerät ${escape(name)} auswählen`)}).click();
      await page.getByText('IDENTITY', {exact: true}).waitFor();
      await page.waitForTimeout(80);
      explorerSelectionMs.push(performance.now() - start);
    }
  }

  // This graph/dialog workload is supported by both the recovery baseline and
  // Phase 2, allowing a like-for-like regression comparison.
  const graphSelectionMs = [];
  for (const name of ['Remote-Linux-Server', 'RDP-Server', 'AMD EVO-X2', 'Remote-Windows-Server']) {
    const start = performance.now();
    await page.getByRole('button', {name: new RegExp(`Details ${escape(name)},`)}).first().click();
    await page.getByRole('button', {name: /Details schließen/}).click();
    await page.waitForTimeout(100);
    graphSelectionMs.push(performance.now() - start);
  }

  const traceEvents = [];
  cdp.on('Tracing.dataCollected', event => traceEvents.push(...event.value));
  await cdp.send('Tracing.start', {categories: 'devtools.timeline', transferMode: 'ReportEvents'});
  const zoomMs = [];
  for (let index = 0; index < 6; index++) {
    const start = performance.now();
    await page.getByRole('button', {name: 'Vergrößern', exact: true}).click();
    await page.getByRole('button', {name: 'Verkleinern', exact: true}).click();
    zoomMs.push(performance.now() - start);
  }
  const fitStart = performance.now();
  await page.getByRole('button', {name: 'Topologie einpassen', exact: true}).click();
  const fitMs = performance.now() - fitStart;

  await page.mouse.move(700, 700);
  const panStart = performance.now();
  for (let index = 0; index < 12; index++) {
    await page.mouse.wheel(0, 140);
    await page.waitForTimeout(30);
  }
  const panMs = performance.now() - panStart;
  const traceComplete = new Promise(resolve => cdp.once('Tracing.tracingComplete', resolve));
  await cdp.send('Tracing.end');
  await traceComplete;

  const modeMs = [];
  for (const mode of ['Verbindungspfade', 'VPN', 'Diagnostik', 'Topologie']) {
    const start = performance.now();
    await page.getByText(mode, {exact: true}).first().click();
    await page.waitForTimeout(150);
    modeMs.push(performance.now() - start);
  }

  // Repeat bounded selection/mode workflows to expose accumulating work. Pins,
  // recents and compare collections remain bounded by the widget contract.
  if (!baseline) {
    for (let index = 0; index < 12; index++) {
      const name = index % 2 ? 'AMD EVO-X2' : 'Remote-Linux-Server';
      await page.getByRole('button', {name: new RegExp(`Gerät ${escape(name)} auswählen`)}).click();
      await page.getByText('IDENTITY', {exact: true}).waitFor();
      await page.waitForTimeout(40);
    }
  }
  await page.waitForTimeout(2500);
  const heapFinal = await heap('final-after-idle');
  const metrics = await page.evaluate(() => {
    window.__oipNet.stop = true;
    const deltas = window.__oipNet.deltas.slice(1).sort((a, b) => a - b);
    const quantile = p => deltas[Math.min(deltas.length - 1, Math.floor(p * deltas.length))];
    return {
      frames: deltas.length,
      medianMs: quantile(.5),
      p95Ms: quantile(.95),
      maxMs: deltas[deltas.length - 1],
      longTasks: window.__oipNet.longTasks,
    };
  });
  const paintEvents = traceEvents.filter(event => event.name === 'Paint').length;
  const rasterTasks = traceEvents.filter(event => event.name === 'RasterTask').length;
  const drawFrames = traceEvents.filter(event => event.name === 'DrawFrame').length;

  const result = {
    verdict: errors.length === 0 ? 'PASS' : 'FAIL',
    baseline,
    browser: await browser.version(),
    base,
    conditions: 'Chrome headless, release CanvasKit, 1440x1000, DPR 1, normal scenario, one local Core with 17 registered demo nodes and five logical demo paths.',
    frames: metrics.frames,
    medianMs: metrics.medianMs,
    p95Ms: metrics.p95Ms,
    maxMs: metrics.maxMs,
    longTasks: metrics.longTasks,
    heap: {initial: heapInitial, final: heapFinal, usedDelta: heapInitial.used == null ? null : heapFinal.used - heapInitial.used},
    searchMs: baseline ? null : stats(searchMs),
    explorerSelectionAndInspectorMs: baseline ? null : stats(explorerSelectionMs),
    graphSelectionAndDialogMs: stats(graphSelectionMs),
    zoomPairMs: stats(zoomMs),
    fitMs,
    workspaceSwitchMs: stats(modeMs),
    panScrollMs: panMs,
    graphTrace: {paintEvents, rasterTasks, drawFrames, categories: 'devtools.timeline during six zoom pairs, fit and twelve wheel-pan steps'},
    errors,
    method: 'requestAnimationFrame deltas and PerformanceObserver longtask during search, selection, Inspector, zoom, fit, workspace switches and graph scrolling. Chrome devtools.timeline counts Paint/RasterTask/DrawFrame during graph interactions. Heap values are non-GC-forced performance.memory samples. Action latency includes Playwright IPC and is comparative, not pure Dart execution time. Browser frame pacing, not a native Flutter DevTools profile. No scale claim beyond the 17 delivered demo nodes.',
  };
  await writeFile(resolve(out, baseline ? 'performance-network-baseline.json' : 'performance-network.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
} finally {
  await browser.close();
}

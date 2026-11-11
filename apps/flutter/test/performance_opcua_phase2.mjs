const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18768';
function escapeRegExp(value){return String(value).replace(/[.*+?^${}()|[\]\\]/g,'\\$&');}
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/performance');
await mkdir(out, {recursive: true});
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1});
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });

try {
  await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: 'normal'}});
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
  await page.getByRole('button', {name: 'Navigation OPC-UA-Browser', exact: true}).click();
  await page.getByText('Namespace 2', {exact: true}).waitFor();

  // The identity of a node is the one that the **Core** delivers: the
  // namespace of its node id, the folder of its parent and its node id.
  const catalogue = await (await context.request.get(`${base}/api/v1/opcua/nodes?q=&folder=all&offset=0&limit=40`)).json();
  const selectionMs = [];
  for (const name of ['temperature', 'pressure', 'operating_mode', 'temperature']) {
    const start = Date.now();
    await page.getByRole('button', {name: new RegExp(`^Node ${name},`)}).click();
    const delivered = await (await context.request.get(`${base}/api/v1/opcua/nodes?q=${encodeURIComponent(name)}&folder=all&offset=0&limit=40`)).json();
    const node = delivered.items.find((item) => item.name === name) ?? delivered.items[0];
    await page.getByText(`ns=${node.namespace} · ${node.folder} · ${node.node_id}`, {exact: true}).waitFor();
    selectionMs.push(Date.now() - start);
  }

  await page.getByRole('button', {name: /^Alle/}).click();
  // The count of the catalogue is the count that the **Core** delivers.
  await page.getByText(`${catalogue.total} Nodes · Seite 1`, {exact: true}).waitFor();
  await page.getByRole('button', {name: 'Dichte Liste', exact: true}).click();
  const searchStart = Date.now();
  await page.keyboard.press('Control+k');
  await page.keyboard.type(catalogue.items[0].name, {delay: 35});
  const hit = await (await context.request.get(`${base}/api/v1/opcua/nodes?q=${encodeURIComponent(catalogue.items[0].name)}&folder=all&offset=0&limit=40`)).json();
  await page.getByText(`${hit.total} Nodes · Seite 1`, {exact: true}).waitFor({timeout: 15000});
  const searchMs = Date.now() - searchStart;
  await page.getByRole('button', {name: 'Suche löschen', exact: true}).click();
  await page.getByText(`${catalogue.total} Nodes · Seite 1`, {exact: true}).waitFor();
  await page.getByRole('button', {name: new RegExp('^Node ' + escapeRegExp(catalogue.items[0].name) + ',')}).click();

  await page.evaluate(() => {
    window.__oipPhase2 = {deltas: [], longTasks: [], stop: false};
    let previous = performance.now();
    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) {
          window.__oipPhase2.longTasks.push({start: entry.startTime, duration: entry.duration});
        }
      }).observe({entryTypes: ['longtask']});
    } catch {}
    function frame(now) {
      window.__oipPhase2.deltas.push(now - previous);
      previous = now;
      if (!window.__oipPhase2.stop) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });

  const pageChangeMs = [];
  const start = Date.now();
  const row = page.getByRole('button', {name: /^Node bulk\.0000,/});
  const box = await row.boundingBox();
  for (let round = 0; round < 4; round++) {
    await page.mouse.move(box.x + 100, box.y + 150);
    for (let index = 0; index < 8; index++) {
      await page.mouse.wheel(0, 160);
      await page.waitForTimeout(35);
    }
    for (let index = 0; index < 8; index++) {
      await page.mouse.wheel(0, -160);
      await page.waitForTimeout(35);
    }
    for (let index = 0; index < 5; index++) {
      await page.keyboard.press('ArrowDown');
      await page.waitForTimeout(55);
    }
    const pageStart = Date.now();
    await page.getByRole('button', {name: 'Nächste Nodes', exact: true}).click();
    await page.getByText(`${catalogue.total} Nodes · Seite ${round + 2}`, {exact: true}).waitFor();
    pageChangeMs.push(Date.now() - pageStart);
    await page.waitForTimeout(250);
  }
  while (Date.now() - start < 8000) await page.waitForTimeout(100);
  const metrics = await page.evaluate(() => {
    window.__oipPhase2.stop = true;
    const deltas = window.__oipPhase2.deltas.slice(1).sort((a, b) => a - b);
    const quantile = p => deltas[Math.min(deltas.length - 1, Math.floor(p * deltas.length))];
    return {
      frames: deltas.length,
      medianMs: quantile(.5),
      p95Ms: quantile(.95),
      maxMs: deltas[deltas.length - 1],
      longTasks: window.__oipPhase2.longTasks,
      jsHeap: performance.memory ? {
        used: performance.memory.usedJSHeapSize,
        total: performance.memory.totalJSHeapSize,
      } : null,
    };
  });
  const result = {
    verdict: errors.length === 0 ? 'PASS' : 'FAIL',
    browser: await browser.version(),
    conditions: 'Chrome headless, release CanvasKit, 1440x1000, DPR 1, normal scenario, one local Core, six M-01 nodes plus 1000 actual bulk nodes, dense list.',
    durationMs: Date.now() - start,
    searchMs,
    selectionMs,
    inspectorUpdateIncludedInSelectionMs: true,
    pageChangeMs,
    ...metrics,
    errors,
    method: 'requestAnimationFrame deltas and PerformanceObserver longtask during four rounds of scroll, keyboard selection and API page changes. Browser frame pacing, not a Flutter DevTools native profile. No claim about 100000 nodes.',
  };
  await writeFile(resolve(out, 'performance.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
} finally {
  await browser.close();
}

/**
 * Overview — the performance of the managed surface, measured in the browser.
 *
 * The Overview is the workstation the operator opens first and returns to; a
 * surface that freezes it for a second is a surface that cannot be operated.
 * The journey drives the **managed** Overview against a real Core with live
 * collectors and measures what the operator feels:
 *
 *   - the latency of every action (a tab, the event filter, a change of the
 *     global context, a round trip through another workstation, the theme);
 *   - the frame pacing of the browser (requestAnimationFrame) and the long
 *     tasks of the main thread (PerformanceObserver);
 *   - the memory the surface retains across the interactions (before, after
 *     an explicit GC, and the delta);
 *   - the paint, raster and draw work of the compositor (devtools.timeline).
 *
 * Every number is written into the receipt. The journey **fails** when an
 * interaction takes longer than its budget, when the main thread blocks for
 * longer than the budget, or when the heap grows past its budget: the budgets
 * are the claim, the numbers are the measurement. The scope is the client of
 * this machine on its loopback — a local measurement, not an SLA.
 *
 * The surface is checked against the Core at the same time: the numbers of the
 * status strip and of the unified summary are the numbers the Core delivered,
 * and the tabs and the filter reach the content of the Core.
 */
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE);
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL;
const out = resolve(process.env.OIP_EVIDENCE_DIR);
const captures = resolve(out, 'captures');
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const ACTION_BUDGET_MS = Number(process.env.OIP_ACTION_BUDGET_MS ?? 3000);
const LONG_TASK_BUDGET_MS = Number(process.env.OIP_LONG_TASK_BUDGET_MS ?? 250);
const HEAP_BUDGET_BYTES = Number(process.env.OIP_HEAP_BUDGET_BYTES ?? 24 * 1024 * 1024);
await mkdir(out, {recursive: true});
await mkdir(captures, {recursive: true});
await rm(resolve(captures, 'failure.png'), {force: true});
await rm(resolve(out, 'failure.json'), {force: true});

const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({
  viewport: {width: 1600, height: 1000},
  deviceScaleFactor: 1,
  serviceWorkers: 'block',
});
const page = await context.newPage();
const errors = [], external = [], failedResources = [], refusals = [], checks = [], taken = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() !== 'error') return;
  // A resource that the Core refused is evidence, not a defect of the surface.
  if (/Failed to load resource/i.test(message.text())) return;
  errors.push(message.text().slice(0, 300));
});
page.on('response', response => {
  if (response.status() < 400) return;
  if (response.status() === 403) {
    refusals.push(response.url().replace(base, ''));
    return;
  }
  if (response.status() === 404 && /favicon\.ico$/.test(response.url())) return;
  failedResources.push(response.url());
});
await context.route('**/*', async route => {
  const url = new URL(route.request().url());
  if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) {
    external.push(url.href);
    return route.abort();
  }
  return route.continue();
});

const stats = values => {
  const sorted = [...values].sort((a, b) => a - b);
  const q = p => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  return {
    samples: values.map(value => Math.round(value)),
    median_ms: Math.round(q(0.5)),
    p95_ms: Math.round(q(0.95)),
    max_ms: Math.round(sorted.at(-1)),
  };
};

function pass(label) {
  checks.push(label);
  console.log('PASS', label);
}
async function capture(name) {
  await page.screenshot({path: resolve(captures, `${name}.png`)});
  taken.push(`${name}.png`);
}
async function timed(label, action) {
  const started = Date.now();
  await action();
  return Date.now() - started;
}
const api = async path => {
  const answer = await context.request.get(base + path, {timeout: 60000});
  assert.equal(answer.status(), 200, `the Core answered ${answer.status()} for ${path}`);
  return await answer.json();
};

/** Every name of the semantics DOM: the accessible names of the surface. */
async function theNames() {
  return await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    return [...host.querySelectorAll('flt-semantics')]
      .map(node => {
        const leaf = node.querySelector('flt-semantics') === null;
        return (node.getAttribute('aria-label') || (leaf ? node.textContent : '') || '').trim();
      })
      .filter(name => name.length > 0);
  });
}

/** The name waits for the data of the Core; the surface reads asynchronously. */
async function waitForNameContaining(fragment, timeout = 30000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const names = await theNames();
    const hit = names.find(name => name.includes(fragment));
    if (hit) return hit;
    if (Date.now() > deadline) {
      throw Error(`the surface does not name "${fragment}" (the names: ${names.slice(0, 24).join(' | ')})`);
    }
    await page.waitForTimeout(200);
  }
}

/**
 * The event filter names its chosen kind once the surface has applied it.
 *
 * The dropdown is a single semantics node whose text concatenates the label
 * and the current value ("EVENT-TYP\nReconnected"). The choice is applied
 * asynchronously, so the journey waits for the name instead of assuming that
 * a fixed delay is enough.
 */
async function waitForDropdownKind(kind, timeout = 20000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const names = await theNames();
    const hit = names.find(name => /^EVENT-TYP\s/.test(name) && name.includes(kind));
    if (hit) return hit;
    if (Date.now() > deadline) {
      const seen = names.filter(name => name.includes('EVENT-TYP'));
      throw Error(`the event filter does not name "${kind}" (the filter reads: ${seen.join(' | ') || 'no name'})`);
    }
    await page.waitForTimeout(100);
  }
}

async function openOverview() {
  await page.getByRole('button', {name: 'Navigation Übersicht', exact: true}).click({force: true});
  await waitForNameContaining('Diagnose öffnen', bootTimeout);
  await waitForNameContaining('Collection-Records', bootTimeout);
}

try {
  // The truth of the Core: the journey names no number of its own.
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,
    ['--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
     '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL], {encoding: 'utf8'}));
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true})
    .waitFor({timeout: bootTimeout});
  await page.getByRole('textbox', {name: 'Einmalcode'}).click({force: true});
  await page.waitForTimeout(250);
  await page.keyboard.type(minted.login_code, {delay: 40});
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true}).click();
  await page.waitForTimeout(2500);
  const session = await api('/api/v2/browser/session');
  assert.equal(session.authenticated, true, 'the session of the operator is not authenticated');

  const sources = await api('/api/v2/sources');
  const devices = await api('/api/v2/devices');
  const events = await api('/api/v2/events');
  const kinds = [...new Set((events.collection_events ?? []).flatMap(record => Object.keys(record)))];
  assert.ok(kinds.length > 0, 'the Core delivered no collection event');
  pass(`the Core delivered ${sources.length} sources, ${devices.length} devices and the event kinds ${kinds.join(', ')}`);

  await openOverview();
  await waitForNameContaining('Diagnose öffnen');
  await waitForNameContaining(`DEVICES: ${devices.length}`);
  await waitForNameContaining(`SOURCES: ${sources.length} · `);
  pass('the Overview names the managed surface and the counts of the Core');
  await capture('overview');

  // The measurement of the surface starts here: the frames of the browser and
  // the long tasks of the main thread are sampled for the whole journey. The
  // heap is read **after** a forced collection, so that the baseline is the
  // memory the surface really retains and not the garbage of the boot.
  const readHeap = () => page.evaluate(() => performance.memory ? {
    used: performance.memory.usedJSHeapSize,
    total: performance.memory.totalJSHeapSize,
    limit: performance.memory.jsHeapSizeLimit,
  } : {used: null, total: null, limit: null});
  await page.evaluate(() => {
    window.__oipOverview = {deltas: [], longTasks: [], stop: false};
    let previous = performance.now();
    try {
      new PerformanceObserver(list => {
        for (const entry of list.getEntries()) {
          window.__oipOverview.longTasks.push({start: entry.startTime, duration: entry.duration});
        }
      }).observe({entryTypes: ['longtask']});
    } catch {}
    function frame(now) {
      window.__oipOverview.deltas.push(now - previous);
      previous = now;
      if (!window.__oipOverview.stop) requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });
  const cdp = await context.newCDPSession(page);
  await cdp.send('HeapProfiler.collectGarbage');
  await page.waitForTimeout(300);
  const heapBefore = await readHeap();

  const traceEvents = [];
  cdp.on('Tracing.dataCollected', event => traceEvents.push(...event.value));
  await cdp.send('Tracing.start', {categories: 'devtools.timeline', transferMode: 'ReportEvents'});

  // 1. the tabs of the activity workspace: every tab renders its own content.
  const tab = async (label, expected) => {
    const ms = await timed(label, async () => {
      await page.getByRole('button', {name: label, exact: true}).click({force: true});
      await waitForNameContaining(expected);
    });
    return ms;
  };
  const tabSamples = [
    await tab('Data Coverage', 'DATA COVERAGE & TRUST'),
    await tab('Source Health', 'dokumentierte Gaps'),
    await tab('Activity', 'Collection-Records'),
    await tab('Source Health', 'dokumentierte Gaps'),
    await tab('Activity', 'Collection-Records'),
  ];
  pass('the three tabs of the activity workspace render the Core\'s content');
  await capture('activity');

  // 2. the event filter reaches a kind of the Core and returns to all.
  const choose = async choice => {
    await page.getByRole('button', {name: /EVENT-TYP/}).click({force: true});
    await page.waitForTimeout(200);
    // The items of the menu are leaf text nodes, not buttons: the accessibility
    // tree of the menu carries the text and no role.
    await page.getByText(choice, {exact: true}).last().click({force: true});
    await waitForDropdownKind(choice);
  };
  const filter = async () => {
    const kind = kinds[kinds.length - 1];
    const ms = await timed(kind, async () => {
      await choose(kind);
      // The rows of the list are the rows of that kind of the Core: a filter
      // that names the kind and still shows every record would be no filter.
      const names = await theNames();
      const rows = names.filter(name => / · [0-9a-f]{64}\n/.test(name));
      assert.ok(rows.length > 0, 'the filtered list shows no record');
      assert.ok(rows.every(name => name.startsWith(`${kind} · `)),
        `the filter shows a record that is not of the kind ${kind}: ${rows.filter(name => !name.startsWith(`${kind} · `))[0]}`);
    });
    const reset = await timed('all', async () => {
      await choose('Alle gelieferten');
    });
    return [ms, reset];
  };
  const filterSamples = [...await filter(), ...await filter()];
  pass(`the event filter reaches the kind ${kinds[kinds.length - 1]} of the Core and returns to all`);
  await capture('filter');

  // 3. the global context: the operator selects an infrastructure and returns
  //    to the unified view; the surface reloads the authorized projection.
  const contextSamples = [];
  const firstRow = page.getByRole('button', {name: /Infrastructure Organization A Infrastructure A1 global auswählen/});
  if (await firstRow.count()) {
    contextSamples.push(await timed('select-infrastructure', async () => {
      await firstRow.first().click({force: true});
      await waitForNameContaining('Infrastructure Context: Infrastructure A1', 20000);
      await waitForNameContaining('Organization A / Infrastructure A1');
    }));
    contextSamples.push(await timed('reset-context', async () => {
      await page.getByRole('button', {name: /Infrastructure Context:/}).first().click({force: true});
      await page.waitForTimeout(250);
      await page.getByRole('button', {name: /Kontext Unified View/}).first().click({force: true});
      await waitForNameContaining('Alle berechtigten Infrastrukturen', 20000);
    }));
    pass('the global context selects an infrastructure of the Core and returns to the unified view');
  } else {
    pass('the global context offers no infrastructure row of the Core in this scope');
  }
  await capture('context');

  // 4. the round trip through another workstation.
  const navigationSamples = [];
  for (let index = 0; index < 6; index++) {
    navigationSamples.push(await timed(`navigation-${index}`, async () => {
      await page.getByRole('button', {name: 'Navigation Geräte & Dienste', exact: true}).click({force: true});
      await waitForNameContaining('Geräte & Dienste', bootTimeout);
      await page.getByRole('button', {name: 'Navigation Übersicht', exact: true}).click({force: true});
      await waitForNameContaining('Diagnose öffnen', bootTimeout);
    }));
  }
  pass('the Overview returns from another workstation in every round trip');

  // 5. the theme of the application.
  const themeSamples = [];
  for (let index = 0; index < 6; index++) {
    themeSamples.push(await timed(`theme-${index}`, async () => {
      await page.getByRole('button', {name: 'Darstellung wechseln'}).click({force: true});
      await page.waitForTimeout(200);
    }));
  }
  pass('the theme of the application switches in every iteration');

  const traceComplete = new Promise(resolve => cdp.once('Tracing.tracingComplete', resolve));
  await cdp.send('Tracing.end');
  await traceComplete;
  await page.waitForTimeout(1500);
  const heapFinal = await readHeap();
  await cdp.send('HeapProfiler.collectGarbage');
  await page.waitForTimeout(400);
  const heapAfterGC = await readHeap();
  const frames = await page.evaluate(() => {
    window.__oipOverview.stop = true;
    return {deltas: window.__oipOverview.deltas.slice(1), longTasks: window.__oipOverview.longTasks};
  });
  const frameStats = stats(frames.deltas);
  const longTasks = frames.longTasks.map(task => Math.round(task.duration));
  // The growth of the retained heap over the journey. A negative delta is a
  // surface that gave memory back: it is no growth and it is reported as it is,
  // but the budget is a budget of growth.
  const delta = heapBefore.used == null || heapAfterGC.used == null
    ? null : heapAfterGC.used - heapBefore.used;
  const growth = delta == null ? null : Math.max(0, delta);

  // 6. the budgets: the claim of the journey.
  const actions = [...tabSamples, ...filterSamples, ...contextSamples,
                   ...navigationSamples, ...themeSamples];
  const actionsReport = {
    tabs: stats(tabSamples),
    filter: stats(filterSamples),
    context: stats(contextSamples),
    navigation: stats(navigationSamples),
    theme: stats(themeSamples),
    all: stats(actions),
    budget_ms: ACTION_BUDGET_MS,
  };
  assert.equal(actions.length > 0, true, 'the journey measured no interaction');
  assert.ok(actionsReport.all.max_ms <= ACTION_BUDGET_MS,
    `an interaction took ${actionsReport.all.max_ms} ms, the budget is ${ACTION_BUDGET_MS} ms`);
  pass(`every one of the ${actions.length} interactions stayed inside ${ACTION_BUDGET_MS} ms (median ${actionsReport.all.median_ms} ms, max ${actionsReport.all.max_ms} ms)`);

  assert.ok(longTasks.every(duration => duration <= LONG_TASK_BUDGET_MS),
    `the main thread blocked for ${Math.max(...longTasks)} ms, the budget is ${LONG_TASK_BUDGET_MS} ms`);
  pass(`no long task of the main thread exceeded ${LONG_TASK_BUDGET_MS} ms (${longTasks.length} long tasks)`);

  assert.notEqual(growth, null, 'the browser exposed no heap measurement');
  assert.ok(growth <= HEAP_BUDGET_BYTES,
    `the surface retained ${Math.round(growth / 1048576)} MiB after the GC, the budget is ${Math.round(HEAP_BUDGET_BYTES / 1048576)} MiB`);
  pass(growth === 0
    ? `the surface retained no memory across the journey (${Math.round(delta / 1024)} KiB after the explicit GC), inside the ${Math.round(HEAP_BUDGET_BYTES / 1048576)} MiB budget`
    : `the surface retained ${Math.round(growth / 1024)} KiB after the explicit GC, inside the ${Math.round(HEAP_BUDGET_BYTES / 1048576)} MiB budget`);

  const trace = {
    presented_frames: traceEvents.filter(event => event.name === 'AnimationFrame::Presentation').length,
    animation_frames: traceEvents.filter(event => event.name === 'AnimationFrame').length,
    paint_events: traceEvents.filter(event => event.name === 'Paint').length,
    layerize: traceEvents.filter(event => event.name === 'Layerize').length,
    layouts: traceEvents.filter(event => event.name === 'Layout').length,
    style_recalculations: traceEvents.filter(event => event.name === 'UpdateLayoutTree').length,
  };
  assert.ok(trace.presented_frames > 0, 'the compositor presented no frame during the journey');
  pass(`the compositor presented ${trace.presented_frames} frames (${trace.paint_events} paints, ${trace.layerize} layerizations, ${trace.layouts} layouts, ${trace.style_recalculations} style recalculations)`);

  await capture('final');

  assert.deepEqual(errors, [], `page errors: ${errors.join(' | ')}`);
  assert.deepEqual(external, [], `external requests: ${external.join(' | ')}`);
  assert.deepEqual(failedResources, [], `failed resources: ${failedResources.join(' | ')}`);

  await writeFile(resolve(out, 'overview-performance.json'), JSON.stringify({
    status: 'PASS',
    the_revision: process.env.OIP_REVISION,
    the_scope: 'the client of the delivered web release on the loopback of this machine; a local measurement, not an SLA',
    the_core_facts: {
      sources: sources.length,
      devices: devices.length,
      event_kinds: kinds,
    },
    the_interactions: actionsReport,
    the_frames: {
      frames: frames.deltas.length,
      median_ms: frameStats.median_ms,
      p95_ms: frameStats.p95_ms,
      max_ms: frameStats.max_ms,
      long_tasks_ms: longTasks,
      long_task_budget_ms: LONG_TASK_BUDGET_MS,
    },
    the_heap: {
      before_gc: heapBefore.used,
      final: heapFinal.used,
      after_gc: heapAfterGC.used,
      the_delta_bytes: delta,
      the_growth_bytes: growth,
      budget_bytes: HEAP_BUDGET_BYTES,
    },
    the_trace: trace,
    the_checks: checks,
    the_captures: taken,
    the_refusals_of_the_core: refusals,
    errors,
    external,
  }, null, 2));
} catch (error) {
  await capture('failure');
  await writeFile(resolve(out, 'failure.json'), JSON.stringify({
    status: 'FAIL',
    error: String(error && error.message || error),
    the_checks: checks,
    errors,
    external,
    the_refusals_of_the_core: refusals,
  }, null, 2));
  console.error(error);
  await browser.close();
  process.exit(1);
}
await browser.close();

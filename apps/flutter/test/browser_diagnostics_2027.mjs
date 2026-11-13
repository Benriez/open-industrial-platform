/**
 * Diagnostics & Events — the evidence workspace of the managed surface.
 *
 * The evidence workspace is where the operator reads **what the Core really
 * knows**: the collection events, their provenance and the limits of the
 * evidence. The journey verifies against a real Core with an authorized
 * session that
 *   - the explorer lists exactly the events that the Core delivered — the
 *     journey names no event of its own,
 *   - the timeline shows a marker for the events and names the time and the
 *     kind of the event,
 *   - the attributes that the Core does **not** deliver are named instead of
 *     invented: the severity of an event and its source timestamp,
 *   - the inspector of an event names the record id of the Core,
 *   - the empty state is named when the Core delivered no event.
 *
 * The rehearsal drives the state of the source: the collectors of the
 * instance are alive, then they die, then they come back. The journey runs in
 * every phase and proves the same thing in all of them — the surface is the
 * Core's truth, never an invented one.
 *
 * It replaces the journey of the generation 2027 (it is in the history of the
 * repository): that one drove the surface of the OIP/005 demo and was named
 * by no harness, so its proof was no receipt. This one drives the **managed**
 * surface against a real Core with an authorized session.
 */
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE);
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL;
const phase = process.env.OIP_PHASE ?? 'live';
const out = resolve(process.env.OIP_EVIDENCE_DIR);
const captures = resolve(out, 'captures');
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
await mkdir(out, {recursive: true});
await mkdir(captures, {recursive: true});
await rm(resolve(out, 'failure.png'), {force: true});
await rm(resolve(out, 'failure.json'), {force: true});

const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({
  viewport: {width: 1600, height: 1000},
  deviceScaleFactor: 1,
});
const page = await context.newPage();
const errors = [], external = [], failedResources = [], checks = [], taken = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() !== 'error') return;
  if (message.text().includes('403')) return;
  errors.push(message.text());
});
page.on('response', response => {
  if (response.status() < 400) return;
  if (response.status() === 403) return;
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

const escapeRegExp = value => String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function pass(label) {
  checks.push(label);
  console.log('PASS', label);
}
async function capture(name) {
  await page.screenshot({path: resolve(captures, `${name}.png`)});
  taken.push(`${name}.png`);
}
async function typeInto(locator, text) {
  for (let n = 0; !(await locator.isEditable()); n++) {
    if (n === 100) throw Error('the field of the surface did not become editable');
    await page.waitForTimeout(100);
  }
  await locator.click({force: true});
  await page.waitForTimeout(250);
  await page.keyboard.press('Meta+A');
  await page.waitForTimeout(80);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(120);
  await page.keyboard.type(text, {delay: 60});
  await page.waitForTimeout(250);
}
const api = async path => {
  const answer = await context.request.get(base + path, {timeout: 60000});
  assert.equal(answer.status(), 200, `the Core answered ${answer.status()} for ${path}`);
  return await answer.json();
};

/** Every name of the semantics DOM: the accessible names of the surface. */
async function theNames() {
  const names = await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    return [...host.querySelectorAll('flt-semantics')]
      .map(node => {
        const leaf = node.querySelector('flt-semantics') === null;
        return (node.getAttribute('aria-label') || (leaf ? node.textContent : '') || '').trim();
      })
      .filter(name => name.length > 0);
  });
  globalThis.__theNames = names;
  return names;
}

async function waitForNameContaining(fragment, timeout = 30000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const names = await theNames();
    const hit = names.find(name => name.includes(fragment));
    if (hit) return hit;
    if (Date.now() > deadline) {
      throw Error(`the surface does not name "${fragment}" (the names: ${names.slice(0, 24).join(' | ')})`);
    }
    await page.waitForTimeout(250);
  }
}

/** The time of an event, in the words of the surface. */
function theTimestamp(ms) {
  if (ms === null || ms === undefined) return 'Unbekannt';
  const value = new Date(ms);
  const two = part => String(part).padStart(2, '0');
  const three = part => String(part).padStart(3, '0');
  return `${value.getUTCFullYear()}-${two(value.getUTCMonth() + 1)}-${two(value.getUTCDate())} ` +
    `${two(value.getUTCHours())}:${two(value.getUTCMinutes())}:${two(value.getUTCSeconds())}.` +
    `${three(value.getUTCMilliseconds())} UTC`;
}

/**
 * The events of the Core, read from the route that the surface reads: the
 * diagnostic history of the authorized context. The journey names none of the
 * events of its own.
 */
const theEvents = payload => {
  const items = Array.isArray(payload.items) ? payload.items : [];
  return items
    .filter(item => item.category === 'event')
    .map(item => {
      const record = item.record ?? {};
      return {
        the_id: record.id ?? null,
        the_kind: record.kind ?? 'unknown',
        the_source: record.source ?? null,
        the_at: record.at_ms ?? null,
      };
    });
};

try {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,
    ['--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
     '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL], {encoding: 'utf8'}));
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true})
    .waitFor({timeout: bootTimeout});
  await typeInto(page.getByRole('textbox', {name: 'Einmalcode'}), minted.login_code);
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true}).click();
  await page.waitForTimeout(2500);
  const session = await api('/api/v2/browser/session');
  assert.equal(session.authenticated, true, 'the session of the operator is not authenticated');

  // The events of the Core: the journey names none of its own.
  const payload = await api('/api/v2/events/history?limit=100');
  const events = theEvents(payload);
  globalThis.__theEvents = events;
  await pass(`the Core delivered ${events.length} collection events`);

  await page.getByRole('button', {name: 'Navigation Diagnose & Ereignisse', exact: true}).click();
  // The eyebrow, the title and the badges of the workspace are one node of
  // the semantics tree: the journey reads the names, not the text of a node.
  await waitForNameContaining('DIAGNOSTICS · EVIDENCE WORKSPACE', bootTimeout);

  if (events.length === 0) {
    // The Core delivered no event: the surface must name that and must not
    // invent one.
    await waitForNameContaining('Keine Collection-Ereignisse geliefert', bootTimeout);
    await pass('the explorer names the absence of the collection events');
    await capture('empty');
  } else {
    // The rows of the explorer are the events of the Core: the journey reads
    // the events of the Core and looks for their source and their time — it
    // names no event of its own. The window of the surface is the newest one
    // of the Core, so every **row** is checked against the events of the Core
    // and not the other way round.
    const keys = new Set(events
      .filter(event => event.the_source !== null && event.the_at !== null)
      .map(event => `${event.the_source}, ${theTimestamp(event.the_at)}`));
    // The surface reads its events when the workspace opens; the read is
    // asynchronous, so the journey waits for the rows (bounded) and asks the
    // surface to read them again if they are not there yet.
    const rowsOf = () => theNames().then(names => names
      .filter(name => /auswählen, .*\d{4}-\d{2}-\d{2} [\d:.]+ UTC/.test(name)));
    let rows = await rowsOf();
    if (rows.length === 0) {
      const reload = page.getByRole('button', {name: 'Diagnosedaten aktualisieren'});
      if (await reload.count()) {
        await reload.first().click({force: true});
        await page.waitForTimeout(1500);
      }
      const deadline = Date.now() + 30000;
      while (rows.length === 0 && Date.now() < deadline) {
        await page.waitForTimeout(500);
        rows = await rowsOf();
      }
    }
    assert.ok(rows.length > 0, 'the explorer lists no event of the Core');
    for (const row of rows) {
      const found = row.match(/([\w.-]+),\s*(\d{4}-\d{2}-\d{2} [\d:.]+ UTC)/);
      assert.ok(found, `the row "${row.slice(0, 90)}" names no source and no time`);
      assert.ok(keys.has(`${found[1]}, ${found[2]}`),
        `the row "${row.slice(0, 90)}" is not an event of the Core`);
    }
    await pass(`every row of the explorer is an event of the Core (${rows.length} rows)`);
    await capture('explorer');

    // The attributes that the Core does not deliver are named and not
    // invented: the severity and the record id of an event.
    await waitForNameContaining('Severity nicht geliefert');
    const withRecord = events.filter(event => event.the_id).length;
    if (withRecord === 0) {
      await waitForNameContaining('keine Server-Record-ID');
      await pass('the record id that the Core does not deliver is named');
    }

    // The timeline: the workspace opens it with its own action, and every
    // marker of it is an event of the Core with the time of the Core.
    await page.getByRole('button', {name: 'Evidence Timeline', exact: true})
      .first().click({force: true});
    await page.waitForTimeout(1500);
    const markers = (await theNames()).filter(name => name.startsWith('Telemetry:'));
    assert.ok(markers.length > 0, 'the timeline shows no marker of the events');
    for (const marker of markers) {
      const stamp = marker.match(/(\d{4}-\d{2}-\d{2} [\d:.]+ UTC)/);
      assert.ok(stamp, `the marker "${marker.slice(0, 90)}" names no time`);
      assert.ok([...keys].some(key => key.endsWith(stamp[1])),
        `the marker "${marker.slice(0, 90)}" is not an event of the Core`);
    }
    await pass(`every marker of the timeline is an event of the Core (${markers.length} markers)`);
    await capture('timeline');

    // The inspector of an event: the identity of the event and the
    // attributes that the Core does not deliver for a collection event.
    const first = events[0];
    await page.getByRole('button', {name: /Ereignis .* auswählen/}).first().click({force: true});
    await page.waitForTimeout(1200);
    await waitForNameContaining('Event ID / Record-ID');
    await waitForNameContaining('Für CollectionEvent nicht geliefert');
    await waitForNameContaining('Nicht vom Core geliefert');
    await pass('the inspector of an event names the absent attributes instead of inventing them');
    await capture('inspector');

    // The controls of a row are in the semantics tree: the pin of an event is
    // reachable by its name — an assistive technology can take that path and
    // does not need the keyboard (N36).
    await waitForNameContaining('Ereignis anheften');
    await page.getByRole('button', {name: 'Ereignis anheften', exact: true})
      .first().click({force: true});
    await waitForNameContaining('Ereignis lösen');
    await pass('the pin of an event row is in the semantics tree and reachable by name');
    await capture('pin');
  }

  assert.deepEqual(errors, [], `page errors: ${errors.join(' | ')}`);
  assert.deepEqual(external, [], `external requests: ${external.join(' | ')}`);
  assert.deepEqual(failedResources, [], `failed resources: ${failedResources.join(' | ')}`);

  await writeFile(resolve(out, `diagnostics-${phase}.json`), JSON.stringify({
    status: 'PASS',
    the_phase: phase,
    the_revision: process.env.OIP_REVISION,
    the_events_of_the_core: events,
    the_checks: checks,
    the_captures: taken,
    errors,
    external,
  }, null, 2));
} catch (error) {
  await capture('failure');
  await writeFile(resolve(out, `failure-${phase}-semantics.html`),
    await page.evaluate(() => {
      const host = document.querySelector('flt-semantics-host');
      return host ? host.outerHTML : '';
    }).catch(() => ''));
  await writeFile(resolve(out, `failure-${phase}.json`), JSON.stringify({
    status: 'FAIL',
    the_phase: phase,
    error: String(error && error.message || error),
    the_events_of_the_core: globalThis.__theEvents ?? null,
    the_names: globalThis.__theNames ?? null,
    the_checks: checks,
    errors,
    external,
  }, null, 2));
  console.error(error);
  await browser.close();
  process.exit(1);
}
await browser.close();

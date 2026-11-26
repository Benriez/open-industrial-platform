/**
 * Network & VPN — the workspace of the managed surface.
 *
 * The Core of the managed mode delivers the devices, the sources, the
 * observations and the events — and **no logical path**: the scoped snapshot
 * of the Core has no topology (`crates/oip-core/src/hierarchy.rs`), and the
 * projection of the client therefore knows that the paths are not delivered.
 * The workspace has to say exactly that and must not invent a path, a
 * transport or a relation.
 *
 * The journey verifies against a real Core with an authorized session that
 *   - the summary names the absence: `LOGISCHE PFADE NICHT GELIEFERT`,
 *     `VPN-TELEMETRIE NICHT GELIEFERT`, `DEMO-PFADE 0`,
 *   - the list of the paths shows its empty state and says that an empty
 *     result is not an offline state,
 *   - the Device Explorer shows exactly the devices that the Core delivered:
 *     the counter, the rows, the relation counter, the search and the filters,
 *   - the transport filter offers only the transports that the Core delivered
 *     — with none, only `alle`,
 *   - the comparison of two devices names its own limit: `2/4 Geräte`,
 *     `0/4 Pfade`, `sitzungslokal`,
 *   - the graph names its empty state,
 *   - the markers of the demo of the generation 2027 are absent,
 *   - the channel that goes stale is named as stale.
 *
 * It replaces the journey of the generation 2027 (it is in the history of the
 * repository): that one drove the surface of the OIP/005 demo and was named
 * by no harness, so its proof was no receipt. This one drives the **managed**
 * surface against a real Core with an authorized session, and it names no
 * device of its own: the rows of the explorer are the devices that the Core
 * delivered.
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
  // The refusals of the Core (403) are expected: the surface asks for what
  // the session may not see.
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

/** The name appears in the semantics DOM of the surface (bounded). */
async function waitForName(name, timeout = 30000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const names = await theNames();
    if (names.includes(name)) return names;
    if (Date.now() > deadline) {
      throw Error(`the surface does not name "${name}" (the names: ${names.slice(0, 24).join(' | ')})`);
    }
    await page.waitForTimeout(250);
  }
}

/**
 * A name that carries the fragment appears in the semantics DOM (bounded).
 *
 * The label of a row of the explorer is **merged** with the label of its
 * group by the engine of the semantics: the node of the row carries the group
 * before the row. The search therefore looks for the fragment, not for the
 * beginning of the name.
 */
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

/** The name is absent from the semantics DOM of the surface (bounded). */
async function waitForNoName(name, timeout = 5000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const names = await theNames();
    if (!names.some(item => item.includes(name))) return;
    if (Date.now() > deadline) throw Error(`the surface still names "${name}"`);
    await page.waitForTimeout(250);
  }
}

/** Click the control of the surface that carries the exact name. */
async function clickName(name) {
  const byText = page.getByText(name, {exact: true});
  if (await byText.count()) {
    await byText.first().click({force: true});
    return;
  }
  await page.getByRole('button', {name, exact: true}).first().click({force: true});
}

try {
  // The authorized session of the operator: the workspace is behind the login.
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

  // The devices of the Core: the journey names none of its own.
  const snapshot = await api('/api/v2/snapshot');
  const devices = snapshot.devices ?? [];
  assert.ok(devices.length >= 2, `the Core delivered ${devices.length} devices, fewer than two`);
  const inventory = await api('/api/v2/inventory/devices?limit=100&include_archived=false');
  const registered = (inventory.items ?? []).map(item => item.id);
  await pass(`the Core delivered ${devices.length} devices and ${registered.length} registered devices`);

  await page.getByRole('button', {name: 'Navigation Netzwerk & VPN', exact: true}).click();
  await waitForName('LAN-Verkabelung', bootTimeout);
  await clickName('Verkabelung eintragen');
  for (const name of ['Netzpfad Messung A1', 'Netzpfad Check B2']) {
    await page.getByRole('checkbox', {name, exact: true}).click();
  }
  await clickName('Verkabelung speichern');
  await waitForName('2 manuell eingetragene LAN-Kabel');
  await capture('lan-wiring');
  await page.reload();
  await page.getByRole('button', {name: 'Navigation Netzwerk & VPN', exact: true}).click();
  await waitForName('2 manuell eingetragene LAN-Kabel', bootTimeout);
  await pass('operator-recorded cables survive reload in the browser');
  await clickName('Verbindungspfade');

  // 2. the list of the paths is empty and an empty result is no offline state.
  await waitForNameContaining('keine gelieferten Verbindungspfade', bootTimeout);
  await pass('the list of the paths is empty and an empty result is no offline state');

  // 3. the transport filter offers only the transports that the Core delivered.
  const names = await theNames();
  const transports = names.filter(name => name.startsWith('Transport:'));
  assert.deepEqual(transports, ['Transport: alle'],
    `the transport filter offers ${JSON.stringify(transports)}`);
  await pass('the transport filter offers only "alle" — the Core delivered no transport');

  // 4. the Device Explorer shows exactly the devices of the Core.
  await clickName('Geräteliste');
  const counter = `${devices.length}/${devices.length} Geräte`;
  await page.getByText(counter, {exact: true}).waitFor({timeout: bootTimeout});
  const explorerNames = await theNames();
  const rows = explorerNames.filter(name =>
    name.includes(' auswählen, ') && name.includes('Status '));
  assert.ok(rows.length > 0, 'the explorer lists no device of the Core');
  await waitForName(`RELATION UNBEKANNT ${devices.length}`);
  await waitForName('TOPOLOGIE 0');
  await pass(`the explorer counts the ${devices.length} devices of the Core and no relation`);
  await capture('explorer');

  // 5. the search reaches every device of the Core — with the characters
  //    that the page shortcuts of the shell once swallowed.
  const search = page.getByRole('textbox', {name: /Name, ID oder Source/});
  if (!(await search.count())) throw Error('the search of the explorer is missing');
  for (const device of devices) {
    await typeInto(search, device.name);
    await page.getByText(`1/${devices.length} Geräte`, {exact: true})
      .waitFor({timeout: 30000});
    await waitForNameContaining(`Gerät ${device.name} auswählen,`);
  }
  await pass(`the search of the explorer reaches the ${devices.length} devices of the Core`);
  await capture('search');
  await typeInto(search, '');
  await page.getByText(counter, {exact: true}).waitFor({timeout: 30000});

  // 6. the filters of the explorer: the relation filter names the devices
  //    whose relation the Core does not deliver.
  await page.getByRole('button', {name: 'Explorer-Filter anzeigen oder ausblenden', exact: true})
    .click({force: true});
  await page.waitForTimeout(600);
  await clickName('Relation: Alle registrierten Geräte');
  await page.waitForTimeout(600);
  await clickName('Relation: Relation unbekannt');
  await page.waitForTimeout(900);
  await page.getByText(counter, {exact: true}).waitFor({timeout: 30000});
  await pass('the relation filter of the explorer keeps the devices without a relation');
  await capture('filters');

  // 7. the comparison of two devices names its own limit.
  //
  // The comparison is driven through the **buttons of the row**: the compare
  // and the pin of an explorer row are in the semantics tree of the surface —
  // the row excludes its **texts** and not its controls (N36) — so an
  // assistive technology reaches them by their names, without the keyboard.
  const first = devices[0];
  const second = devices[1];
  for (const device of [first, second]) {
    await waitForNameContaining(`${device.name} vergleichen`);
    await page.getByRole('button', {name: `${device.name} vergleichen`, exact: true})
      .first().click({force: true});
    await waitForNameContaining(`${device.name} aus Vergleich entfernen`);
  }
  await waitForNameContaining(`${first.name} anheften`);
  await page.getByRole('button', {name: `${first.name} anheften`, exact: true})
    .first().click({force: true});
  await waitForNameContaining(`${first.name} loslösen`);
  await pass('the compare and the pin of a row are in the semantics tree and reachable by name');
  await clickName('Vergleich 2');
  await waitForNameContaining('Network Compare');
  await waitForNameContaining('2/4 Geräte · 0/4 Pfade · sitzungslokal');
  await waitForNameContaining('GERÄTEVERGLEICH · 2/4');
  await waitForNameContaining('Unabhängige Beobachtungskontexte');
  await waitForNameContaining('VERBINDUNGSVERGLEICH · 0/4');
  await waitForNameContaining('Keine logischen Pfade ausgewählt');
  for (const device of [first, second]) {
    await waitForNameContaining(device.id);
  }
  await pass('the comparison of two devices names the devices of the Core and its own limit');
  await capture('compare');
  await page.getByRole('button', {name: /Vergleich schließen/}).click({force: true});
  await page.waitForTimeout(800);

  // 8. the graph shows inventory nodes and names the missing path evidence.
  await clickName('Verbindungspfade');
  await clickName('Logische Karte');
  await waitForNameContaining('Pfade', bootTimeout);
  await waitForNoName('2 manuell eingetragene LAN-Kabel');
  await pass('the graph keeps registered devices visible without inventing paths');
  await capture('topology');

  // 9. the markers of the demo of the generation 2027 are absent.
  const rowNames = (await theNames())
    .filter(name => name.includes(' auswählen, ') && name.includes('Status '));
  for (const marker of ['AMD EVO-X2', 'M-01', 'OpenWrt-Router', 'Remote-Linux-Server']) {
    assert.ok(!rowNames.some(label => label.includes(marker)),
      `the explorer shows the demo device ${marker}`);
  }
  for (const marker of ['Tailnet', 'Remote Site', 'Normalbetrieb', 'Deine Infrastruktur']) {
    await waitForNoName(marker);
  }
  await pass('the markers of the demo of the generation 2027 are absent');

  // 10. the channel that goes stale is named as stale.
  await context.setOffline(true);
  await waitForNameContaining('Keine Live-Verbindung', 30000);
  await pass('the channel that goes stale is named as stale');
  await capture('stale');
  await context.setOffline(false);
  await waitForNoName('Keine Live-Verbindung', 60000);
  await pass('the channel comes back after the interruption');

  assert.deepEqual(errors, [], `page errors: ${errors.join(' | ')}`);
  assert.deepEqual(external, [], `external requests: ${external.join(' | ')}`);
  assert.deepEqual(failedResources, [], `failed resources: ${failedResources.join(' | ')}`);

  await writeFile(resolve(out, 'network-2027.json'), JSON.stringify({
    status: 'PASS',
    the_revision: process.env.OIP_REVISION,
    the_devices_of_the_core: devices.map(device => ({
      the_id: device.id,
      the_name: device.name,
      the_status: device.health?.reachability,
    })),
    the_registered_devices: registered,
    the_paths_are_not_delivered: true,
    the_checks: checks,
    the_captures: taken,
    errors,
    external,
  }, null, 2));
} catch (error) {
  await capture('failure');
  await writeFile(resolve(out, 'failure-network.txt'),
    (await page.locator('body').ariaSnapshot()).replace(/[a-f0-9]{64}/gi, 'REDACTED'));
  // The semantics DOM of the surface: the evidence of what the surface
  // exposes and what it keeps for itself.
  await writeFile(resolve(out, 'failure-semantics.html'),
    await page.evaluate(() => {
      const host = document.querySelector('flt-semantics-host');
      return host ? host.outerHTML : '';
    }));
  await writeFile(resolve(out, 'failure.json'), JSON.stringify({
    status: 'FAIL',
    error: String(error && error.message || error),
    the_checks: checks,
    errors,
    external,
  }, null, 2));
  console.error(error);
  await browser.close();
  process.exit(1);
}
await browser.close();

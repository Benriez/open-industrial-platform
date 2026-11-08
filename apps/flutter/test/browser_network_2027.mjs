const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18772';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-network-phase2');
await mkdir(out, {recursive: true});
for (const file of ['browser-network-failure.json', 'failure.png']) {
  await rm(resolve(out, file), {force: true});
}
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const errors = [], external = [], failedResources = [], expectedFaults = [], checks = [], captures = [], geometry = [];
const known = [
  ['router', 'OpenWrt-Router'], ['M-01', 'OPC-UA-Sensoren · M-01'],
  ['evo', 'AMD EVO-X2'], ['remote-linux', 'Remote-Linux-Server'],
  ['remote-windows', 'Remote-Windows-Server'], ['rdp', 'RDP-Server'],
];
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function isOip009IdentityProbe(url, status) {
  return status === 403 && new URL(url).pathname === '/api/v2/organizations';
}
function observe(page) {
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    if (message.text().includes('403')) {
      expectedFaults.push(message.text());
    } else {
      errors.push(message.text());
    }
  });
  page.on('response', response => {
    if (response.status() >= 400) {
      (isOip009IdentityProbe(response.url(), response.status()) ? expectedFaults : failedResources)
          .push(`${response.status()} ${response.url()}`);
    }
  });
}
function pass(label) { checks.push(label); console.log('PASS', label); }
async function capture(page, name) {
  await page.screenshot({path: resolve(out, `${name}.png`)});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, name);
}
async function scenario(context, name) {
  const response = await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: name}});
  assert.equal(response.status(), 200);
}
async function nav(page, label) {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (await menu.count()) {
    await menu.click();
    await page.getByText('Dismiss', {exact: true}).waitFor({state: 'visible'});
  }
  await page.getByRole('button', {name: `Navigation ${label}`, exact: true}).click();
  if (await menu.count()) await page.getByText('Dismiss', {exact: true}).waitFor({state: 'hidden'});
}
async function boot(context, width, height) {
  const page = await context.newPage();
  observe(page);
  await page.setViewportSize({width, height});
  await page.goto(`${base}/?network-phase2=${width}x${height}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav(page, 'Netzwerk & VPN');
  await page.getByRole('button', {name: 'Topologie', exact: true}).click();
  if (width >= 1080) {
    await page.getByRole('button', {name: /Detail-Inspector manuell öffnen/}).click();
  }
  await page.getByText('Logische Topologie', {exact: true}).first().waitFor();
  if (width >= 1200) await page.getByText('DEVICE EXPLORER', {exact: true}).waitFor();
  await page.getByText('6 TOPOLOGIE-NODES', {exact: true}).waitFor();
  await page.getByText('5 PFADE', {exact: true}).waitFor();
  await page.waitForTimeout(650);
  return page;
}
function graphNode(page, name) {
  return page.getByRole('button', {name: new RegExp(`Details ${escape(name)},`)}).first();
}
function explorerNode(page, name) {
  return page.getByRole('button', {name: new RegExp(`Gerät ${escape(name)} auswählen`)}).first();
}
async function measureGeometry(page, label, expectAll = true) {
  const viewport = await page.locator('flt-semantics[aria-label="Topologie-Viewport"]').boundingBox();
  assert.ok(viewport, `${label}: viewport`);
  const nodes = [];
  for (const [id, name] of known) {
    const locator = graphNode(page, name);
    if (!await locator.count()) continue;
    const box = await locator.boundingBox();
    if (box) nodes.push({id, name, ...box});
  }
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i], b = nodes[j];
      const overlap = Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)) *
        Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
      assert.ok(overlap <= 1, `${label}: overlap ${a.id}/${b.id} = ${overlap}`);
    }
  }
  if (expectAll) {
    assert.equal(nodes.length, 6, `${label}: six known endpoints exposed`);
    for (const node of nodes) {
      assert.ok(node.x >= viewport.x - 1 && node.y >= viewport.y - 1 &&
        node.x + node.width <= viewport.x + viewport.width + 1 &&
        node.y + node.height <= viewport.y + viewport.height + 1,
      `${label}: ${node.id} outside viewport ${JSON.stringify({node, viewport})}`);
    }
  }
  const report = {label, viewport, nodes, allVisible: expectAll};
  geometry.push(report);
  return report;
}
async function tab(page, name) {
  await page.getByText(name, {exact: true}).first().click();
  await page.waitForTimeout(250);
}
async function setRelation(page, label) {
  const relation = page.locator('flt-semantics').filter({hasText: /^Relation:/}).last();
  if (!await relation.count()) {
    await page.getByRole('button', {name: /Explorer-Filter anzeigen/}).click();
  }
  await relation.click();
  await page.getByText(`Relation: ${label}`, {exact: true}).last().click();
  await page.waitForTimeout(350);
}
async function search(page, value) {
  const field = page.getByRole('textbox').first();
  await page.keyboard.press('ControlOrMeta+K');
  await field.waitFor({state: 'visible'});
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.type(value, {delay: 12});
  await page.waitForTimeout(350);
}
async function compareDevice(page, name) {
  await search(page, name);
  await explorerNode(page, name).click();
  await page.getByRole('button', {name: 'Zum Vergleich hinzufügen (C)', exact: true}).click();
  await page.getByRole('button', {name: 'Suche löschen', exact: true}).click();
  await page.waitForTimeout(250);
}
async function pageViewportScroll(page) {
  await page.locator('flt-semantics[aria-label="Topologie-Viewport"]')
    .evaluate(element => element.scrollIntoView({block: 'center'}));
  await page.waitForTimeout(300);
}

async function workflow(width, height) {
  const context = await browser.newContext({viewport: {width, height}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  await context.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) {
      external.push(url.href);
      return route.abort();
    }
    return route.continue();
  });
  await scenario(context, 'normal');
  const page = await boot(context, width, height);
  const suffix = `${width}x${height}`;
  await measureGeometry(page, `initial-${suffix}`);
  await capture(page, `network-initial-${suffix}`);
  pass(`${suffix}: initial three-pane fit contains six non-overlapping known endpoints`);

  const router = graphNode(page, 'OpenWrt-Router');
  const beforeUpdate = await router.boundingBox();
  await page.waitForTimeout(1500);
  const afterUpdate = await router.boundingBox();
  assert.ok(Math.abs(beforeUpdate.x - afterUpdate.x) < 1 && Math.abs(beforeUpdate.y - afterUpdate.y) < 1);
  pass(`${suffix}: live snapshot updates preserve graph geometry and camera`);

  await page.getByRole('button', {name: 'Topologie einpassen', exact: true}).click();
  await measureGeometry(page, `explicit-fit-${suffix}`);
  const zoomNode = graphNode(page, 'OPC-UA-Sensoren · M-01');
  const beforeZoom = (await zoomNode.boundingBox()).width;
  await page.getByRole('button', {name: 'Vergrößern', exact: true}).click();
  await page.waitForTimeout(250);
  const afterZoom = (await zoomNode.boundingBox()).width;
  assert.ok(afterZoom > beforeZoom * 1.15);
  await page.getByRole('button', {name: 'Topologie einpassen', exact: true}).click();
  await page.waitForTimeout(300);
  pass(`${suffix}: explicit fit and centre zoom change real rendered bounds`);

  const viewportBeforeSelection = await page.locator('flt-semantics[aria-label="Topologie-Viewport"]').boundingBox();
  const visibleBeforeSelection = await graphNode(page, 'Remote-Linux-Server').boundingBox();
  await explorerNode(page, 'Remote-Linux-Server').click();
  await page.getByText('IDENTITY', {exact: true}).waitFor();
  const viewportAfterSelection = await page.locator('flt-semantics[aria-label="Topologie-Viewport"]').boundingBox();
  const visibleAfterSelection = await graphNode(page, 'Remote-Linux-Server').boundingBox();
  for (const key of ['x', 'y']) {
    const before = visibleBeforeSelection[key] - viewportBeforeSelection[key];
    const after = visibleAfterSelection[key] - viewportAfterSelection[key];
    assert.ok(Math.abs(before - after) < 1,
      `visible Explorer selection preserved viewport-relative ${key}: ${before} -> ${after}`);
  }
  for (const key of ['width', 'height']) {
    assert.ok(Math.abs(visibleBeforeSelection[key] - visibleAfterSelection[key]) < 1,
      `visible Explorer selection preserved ${key}`);
  }
  await page.getByText(/Direkte logische Nachbarn: 1/).waitFor();
  assert.equal(await page.getByRole('button', {name: /Details schließen/}).count(), 0);
  await capture(page, `network-device-selected-${suffix}`);
  pass(`${suffix}: Explorer selection focuses graph and opens technical Node Inspector without dialog`);

  await page.getByRole('button', {name: 'Topologie einpassen', exact: true}).click();
  await page.getByRole('button', {name: /Verbindung router nach remote-linux/}).click();
  await page.getByText(/Verbindungsinspektion\./).waitFor();
  await page.getByText(/RTT: 36\.0 ms · Fixture/).waitFor();
  await capture(page, `network-edge-selected-${suffix}`);
  await page.getByRole('button', {name: 'Pfad zum Vergleich hinzufügen (C)', exact: true}).click();
  pass(`${suffix}: graph edge selects delivered endpoints and honest fixture metrics`);

  await setRelation(page, 'Relation unbekannt');
  await page.getByText('11/17 Geräte', {exact: true}).waitFor();
  assert.equal(await page.locator('flt-semantics[aria-label="Topologie-Viewport"]').count(), 0);
  await capture(page, `network-relation-unknown-list-${suffix}`);
  await search(page, 'pi3');
  await explorerNode(page, 'Raspberry Pi 3B').click();
  await page.getByText(/Relation unbekannt · keine bekannten Pfade/).waitFor({state: 'attached'});
  assert.equal(await graphNode(page, 'Raspberry Pi 3B').count(), 0);
  assert.equal(await page.getByText('Show Direct Neighbors', {exact: true}).count(), 0);
  await capture(page, `network-relation-unknown-explorer-${suffix}`);
  pass(`${suffix}: eleven relation-unknown devices remain searchable without fake graph edges`);

  await setRelation(page, 'Alle registrierten Geräte');
  await search(page, 'Remote');
  await page.getByText(/Geräte/).first().waitFor();
  await capture(page, `network-search-${suffix}`);
  await page.getByRole('button', {name: 'Suche löschen', exact: true}).click();
  pass(`${suffix}: Explorer search and relation filters drive list and graph`);

  await compareDevice(page, 'AMD EVO-X2');
  await compareDevice(page, 'OpenWrt-Router');
  await page.getByRole('button', {name: /Network Compare öffnen/}).click();
  await page.getByText('2/4 Geräte · 1/4 Pfade · sitzungslokal', {exact: true}).waitFor();
  await page.getByText(/Unabhängige Beobachtungskontexte/).waitFor({state: 'attached'});
  await capture(page, `network-compare-${suffix}`);
  await page.mouse.move(width * .57, height * .72);
  await page.mouse.wheel(0, 700);
  await page.waitForTimeout(400);
  await capture(page, `network-compare-links-${suffix}`);
  pass(`${suffix}: Compare combines two devices and one link without time-alignment claims`);

  await tab(page, 'Verbindungspfade');
  await page.getByText('5/5', {exact: true}).waitFor();
  await page.getByText('Transport: alle', {exact: true}).click();
  await page.getByText('Transport: Tailnet', {exact: true}).last().click();
  await page.getByText('1/5', {exact: true}).waitFor();
  await capture(page, `network-connections-${suffix}`);
  await page.getByText('Transport: Tailnet', {exact: true}).first().click();
  await page.getByText('Transport: alle', {exact: true}).last().click();
  pass(`${suffix}: all five logical paths and transport filtering remain available`);

  await tab(page, 'VPN');
  await page.getByText(/Keine VPN-Telemetrie verbunden/).waitFor({state: 'attached'});
  await capture(page, `network-vpn-${suffix}`);
  await page.mouse.move(width * .57, height * .72);
  await page.mouse.wheel(0, 650);
  await page.waitForTimeout(350);
  await capture(page, `network-vpn-peers-${suffix}`);
  pass(`${suffix}: VPN workstation exposes real capability boundaries without invented peers`);

  await scenario(context, 'vpn');
  await tab(page, 'Diagnostik');
  await page.getByText(/Network Events \/ Link History/).waitFor();
  await page.getByText(/Instabile VPN-Verbindung/).waitFor();
  await capture(page, `network-diagnostics-${suffix}`);
  await scenario(context, 'normal');
  pass(`${suffix}: Diagnostics separates collection evidence, demo incidents and missing history`);

  await tab(page, 'Topologie');
  await page.getByRole('button', {name: 'Edge Labels ausblenden', exact: true}).click();
  await page.waitForTimeout(350);
  assert.equal(await page.getByRole('button', {name: /Verbindung .* nach/}).count(), 0);
  await page.getByRole('button', {name: 'Edge Labels anzeigen', exact: true}).click();
  await page.waitForTimeout(350);
  assert.equal(await page.getByRole('button', {name: /Verbindung .* nach/}).count(), 5);
  pass(`${suffix}: Edge Labels toggle preserves keyboard-selectable paths in Connections`);

  await context.setOffline(true);
  await page.getByText('API STALE / UNBEKANNT', {exact: true}).waitFor({timeout: 30000});
  await context.setOffline(false);
  await page.getByText('API CONNECTED', {exact: true}).first().waitFor({timeout: 40000});
  pass(`${suffix}: transport outage remains stale/unknown and recovers without false offline claims`);

  await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
  await page.getByText('DAYLIGHT', {exact: true}).waitFor();
  await capture(page, `network-daylight-${suffix}`);
  await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
  await page.getByText('GRAPHITE', {exact: true}).waitFor();
  await capture(page, `network-graphite-${suffix}`);
  await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
  await page.getByText('SPECTRUM', {exact: true}).waitFor();

  await nav(page, 'OPC-UA-Browser');
  await page.getByText('QUELLE', {exact: true}).waitFor();
  await page.getByText('Namespace 2', {exact: true}).waitFor();
  await capture(page, `opcua-phase2-reference-${suffix}`);
  pass(`${suffix}: unchanged OPC-UA Phase 2 remains available in the same release build`);
  await context.close();
}

try {
  await workflow(1440, 1000);
  await workflow(1920, 1080);

  for (const [width, height] of [
    [320, 740], [375, 812], [390, 844], [768, 1024], [834, 1112], [1024, 768],
  ]) {
    const context = await browser.newContext({viewport: {width, height}, deviceScaleFactor: 1, serviceWorkers: 'block'});
    await context.route('**/*', route => {
      const url = new URL(route.request().url());
      if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) {
        external.push(url.href);
        return route.abort();
      }
      return route.continue();
    });
    const page = await boot(context, width, height);
    if (width < 600) {
      await pageViewportScroll(page);
      const report = await measureGeometry(page, `initial-${width}x${height}`, false);
      const mobileRouter = report.nodes.find(node => node.id === 'router');
      assert.ok(mobileRouter && mobileRouter.width >= 98, 'unclipped mobile node stays readable');
      await capture(page, `network-initial-${width}x${height}`);
      if (width === 390) {
        await page.evaluate(() => scrollTo(0, 0));
        await page.waitForTimeout(300);
        await page.getByRole('radio', {name: 'Explorer', exact: true}).click();
        await setRelation(page, 'Relation unbekannt');
        await page.getByText('11/17 Geräte', {exact: true}).waitFor();
        await capture(page, 'network-relation-unknown-explorer-390x844');
      }
    } else {
      await measureGeometry(page, `initial-${width}x${height}`);
      if (width === 1024) await pageViewportScroll(page);
      await capture(page, `network-initial-${width}x${height}`);
    }
    await context.close();
  }
  pass('Responsive geometry verified at 320/375/390/768/834/1024 in addition to 1440/1920');

  assert.deepEqual(errors, []);
  assert.deepEqual(external, []);
  assert.deepEqual(failedResources, []);
  await writeFile(resolve(out, 'browser-network.json'), JSON.stringify({
    verdict: 'PASS', browser: await browser.version(), base, checks, captures, geometry,
    errors, external, failedResources,
  }, null, 2));
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length, captures: captures.length, geometry: geometry.length}, null, 2));
} catch (error) {
  await writeFile(resolve(out, 'browser-network-failure.json'), JSON.stringify({
    verdict: 'FAIL', error: String(error), checks, geometry, errors, external, failedResources,
  }, null, 2));
  throw error;
} finally {
  await browser.close();
}

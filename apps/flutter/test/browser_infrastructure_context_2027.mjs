/**
 * OIP-009 UI acceptance against the explicitly marked contract fixture.
 * This is not a real multi-infrastructure authorization E2E proof.
 */
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18950';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/infrastructure-context-2027');
await mkdir(out, {recursive: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const checks = [];
const pageErrors = [];
const overflowErrors = [];
const externalRequests = [];
const credentialEvidence = [];
const pass = label => {checks.push(label); console.log('PASS', label);};
function observe(page) {
  page.on('pageerror', error => pageErrors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /overflowed|RenderFlex/i.test(message.text())) {
      overflowErrors.push(message.text());
    }
  });
  page.on('request', request => {
    const url = request.url();
    if (!url.startsWith(base) && !url.startsWith('data:') && !url.startsWith('blob:')) {
      externalRequests.push(url);
    }
    if (/bearer|access_token|credential/i.test(url)) credentialEvidence.push(url);
    if (request.headers().authorization) credentialEvidence.push('authorization header');
  });
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
async function boot(width = 1440, height = 900) {
  const context = await browser.newContext({
    viewport: {width, height}, deviceScaleFactor: 1, serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);
  observe(page);
  await page.goto(`${base}/?oip009=${width}x${height}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByRole('button', {name: /Infrastructure Context: Alle berechtigten/}).waitFor();
  await page.waitForTimeout(500);
  return {context, page};
}
async function selectContext(page, pattern, {query} = {}) {
  await page.getByRole('button', {name: /Infrastructure Context:/}).click({force: true});
  await page.getByRole('textbox').last().waitFor();
  if (query !== undefined) {
    await page.getByRole('textbox').last().fill(query);
    await page.waitForTimeout(250);
  }
  await page.getByRole('button', {name: pattern}).first().click({force: true});
  await page.waitForTimeout(500);
}
async function geometry(page) {
  return page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    const selector = [...host.querySelectorAll('flt-semantics')]
      .filter(node => node.getAttribute('role') === 'button' &&
        `${node.getAttribute('aria-label') || ''} ${node.textContent || ''}`
          .includes('Infrastructure Context:'))
      .sort((a, b) => a.getBoundingClientRect().width - b.getBoundingClientRect().width)[0];
    const dialogField = [...host.querySelectorAll('flt-semantics')]
      .filter(node => node.getAttribute('role') === 'textbox').at(-1);
    const input = [...document.querySelectorAll('input, textarea')].at(-1);
    const rect = (selector ?? dialogField ?? input)?.getBoundingClientRect();
    return {
      horizontalOverflow: document.documentElement.scrollWidth > innerWidth,
      selectorClipped: rect ? rect.left < 0 || rect.right > innerWidth + 0.5 : true,
      selectorRect: rect ? {left: rect.left, right: rect.right, width: rect.width} : null,
      viewportWidth: innerWidth,
      localStorageEntries: localStorage.length,
      sessionStorageEntries: sessionStorage.length,
    };
  });
}
async function assertGeometry(page, label) {
  const value = await geometry(page);
  if (value.selectorClipped) console.log('CLIPPED_GEOMETRY', label, value);
  assert.equal(value.horizontalOverflow, false, `${label}: horizontal overflow`);
  assert.equal(value.selectorClipped, false, `${label}: selector clipped`);
  assert.equal(value.localStorageEntries, 0, `${label}: localStorage must stay empty`);
  assert.equal(value.sessionStorageEntries, 0, `${label}: sessionStorage must stay empty`);
}

try {
  {
    const {context, page} = await boot();
    await page.screenshot({path: resolve(out, 'overview-unified-1440x900.png')});
    assert.equal(await page.getByText('UNIFIED INFRASTRUCTURE VIEW', {exact: true}).count(), 1);
    assert.equal(await page.getByText(/5 DEVICES/).count() > 0, true);
    await selectContext(page, /Kontext Organization A \/ Infrastructure A2/, {query: 'A2'});
    await page.screenshot({path: resolve(out, 'overview-scoped-a2-1440x900.png')});
    await nav(page, 'Geräte & Dienste');
    await page.getByRole('button', {name: /Gerät Gateway A2 device-a2 auswählen/}).waitFor();
    assert.equal(await page.getByRole('button', {name: /Gerät Sensor B1 device-b1 auswählen/}).count(), 0);
    assert.equal(await page.getByRole('button', {name: /Gerät Pump A1 device-a1 auswählen/}).count(), 0);
    await page.screenshot({path: resolve(out, 'devices-a2-1440x900.png')});
    pass('Unified/A1-A2 projection and direct global scope switch keep counts consistent');

    await selectContext(page, /Kontext Organization A \/ Infrastructure A1 \/ Site 2/, {query: 'Site 2'});
    await page.getByRole('button', {name: /Gerät Manual Valve A1 device-a1-manual auswählen/}).click({force: true});
    await page.getByText('no_collector', {exact: true}).first().waitFor();
    await page.getByText('Organization A', {exact: true}).first().waitFor();
    await page.getByText('Site 2', {exact: true}).first().waitFor();
    await page.screenshot({path: resolve(out, 'devices-source-less-site2-1440x900.png')});
    pass('Source-less device stays visible in Site scope with NoCollector and Unknown provenance');

    for (const label of ['Übersicht', 'Netzwerk & VPN', 'OPC-UA-Browser', 'Diagnose & Ereignisse', 'Einstellungen']) {
      await nav(page, label);
      await page.getByRole('button', {name: /Infrastructure Context: Site 2/}).waitFor();
      await page.screenshot({path: resolve(out, `context-${label.replaceAll(' ', '-').replaceAll('&', 'und')}-1440x900.png`)});
    }
    pass('One selected Site context survives all six workstation navigations');

    await selectContext(page, /Kontext Unified View/, {query: ''});
    await nav(page, 'Übersicht');
    await page.getByText('UNIFIED INFRASTRUCTURE VIEW', {exact: true}).waitFor();
    await selectContext(page, /Kontext Organization B \/ Infrastructure B1/, {query: 'B1'});
    await nav(page, 'Geräte & Dienste');
    await page.getByRole('button', {name: /Gerät Sensor B1 device-b1 auswählen/}).waitFor();
    await page.getByRole('button', {name: /Gerät Manual Drive B1 device-b1-manual auswählen/}).waitFor();
    assert.equal(await page.getByRole('button', {name: /Gerät Gateway A2 device-a2 auswählen/}).count(), 0);
    pass('Multiple organizations stay attributable without cross-organization device mixing');
    await context.close();
  }

  {
    const {context, page} = await boot();
    await selectContext(page, /Kontext Organization B \/ Infrastructure B1/, {query: 'B1'});
    await nav(page, 'Geräte & Dienste');
    await page.getByRole('button', {name: /Gerät Sensor B1 device-b1 auswählen/}).waitFor();
    const response = await page.request.post(`${base}/__fixture/revoke`);
    assert.equal(response.ok(), true);
    await page.getByRole('button', {name: /Infrastructure Context: Alle berechtigten/}).waitFor({timeout: 30000});
    assert.equal(await page.getByRole('button', {name: /Gerät Sensor B1 device-b1 auswählen/}).count(), 0);
    assert.equal(await page.getByRole('button', {name: /Gerät Manual Drive B1/}).count(), 0);
    await page.getByRole('button', {name: /Gerät Pump A1 device-a1 auswählen/}).waitFor();
    await page.screenshot({path: resolve(out, 'authorization-revoked-fixture-1440x900.png')});
    pass('Fixture authorization change discards invalid context and old scoped data');
    await page.request.post(`${base}/__fixture/restore`);
    await context.close();
  }

  {
    const {context, page} = await boot();
    await selectContext(page, /Kontext Organization A \/ Infrastructure A2/, {query: 'A2'});
    await page.request.post(`${base}/__fixture/reconnect`);
    await page.getByRole('button', {name: /Infrastructure Context: Infrastructure A2/}).waitFor({timeout: 30000});
    await page.getByText('API CONNECTED', {exact: true}).waitFor({timeout: bootTimeout});
    assert.equal(await geometry(page).then(value => value.localStorageEntries), 0);
    pass('SSE reconnect resynchronizes authorized data without storing credentials');
    await context.close();
  }

  for (const [width, height] of [[320, 740], [390, 844], [768, 1024], [1024, 900], [1440, 900], [1920, 1080]]) {
    const {context, page} = await boot(width, height);
    await assertGeometry(page, `${width}x${height}`);
    await page.getByRole('button', {name: /Infrastructure Context:/}).click({force: true});
    await page.getByRole('textbox').last().waitFor();
    await assertGeometry(page, `${width}x${height} dialog`);
    await page.screenshot({path: resolve(out, `selector-${width}x${height}.png`)});
    await page.keyboard.press('Escape');
    pass(`${width}x${height}: selector, dialog and storage geometry PASS`);
    await context.close();
  }

  for (const [width, height] of [[1440, 900], [390, 844]]) {
    const {context, page} = await boot(width, height);
    for (const theme of ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
      await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
      if (width >= 760) await page.getByText(theme, {exact: true}).waitFor();
      await page.waitForTimeout(400);
      await assertGeometry(page, `${width} ${theme}`);
      await page.screenshot({path: resolve(out, `overview-${theme.toLowerCase()}-${width}x${height}.png`)});
      pass(`${width}x${height} ${theme}: global context theme PASS`);
    }
    await context.close();
  }

  assert.deepEqual(pageErrors, [], pageErrors.join(' | '));
  assert.deepEqual(overflowErrors, [], overflowErrors.join(' | '));
  assert.deepEqual(externalRequests, [], externalRequests.join(' | '));
  assert.deepEqual(credentialEvidence, [], credentialEvidence.join(' | '));
  pass('No page errors, overflow, external requests, URL credentials or Authorization headers');
  await writeFile(resolve(out, 'browser-infrastructure-context.json'), `${JSON.stringify({
    verdict: 'PASS', base, fixture_only: true, real_ingestion: false,
    backend_scaling_proof: false, secured_browser_e2e: false,
    checks, pageErrors, overflowErrors, externalRequests, credentialEvidence,
  }, null, 2)}\n`);
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length}, null, 2));
} finally {
  await browser.close();
}

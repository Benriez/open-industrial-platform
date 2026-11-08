const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18920';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-devices-2027');
await mkdir(out, {recursive: true});
await rm(resolve(out, 'browser-devices-failure.json'), {force: true});
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const errors = [], external = [], failedResources = [], expectedFaults = [], checks = [], captures = [];
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
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) external.push(url.href);
  });
}
function pass(label) { checks.push(label); console.log('PASS', label); }
async function capture(page, name) {
  await page.screenshot({path: resolve(out, `${name}.png`)});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `${name}: document overflow`);
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
async function boot(context, width = 1440, height = 1000) {
  const page = await context.newPage();
  observe(page);
  await page.setViewportSize({width, height});
  await page.goto(`${base}/?devices-2027=${width}x${height}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav(page, 'Geräte & Dienste');
  await page.getByText('DEVICES & SERVICES · OBJECT WORKSPACE', {exact: true}).waitFor();
  await page.getByText(/\d+ von \d+ Geräten · Simuliertes Inventar/).waitFor();
  await page.waitForTimeout(350);
  return page;
}
async function search(page, value) {
  await page.keyboard.press('/');
  await page.keyboard.type(value, {delay: 15});
  await page.waitForTimeout(250);
}
async function selectDevice(page, name, id) {
  // DOM scrollIntoView cannot scroll Flutter's inner canvas list. Use the
  // actual search contract so the target row is present and pointer-visible.
  const field = page.getByRole('textbox').first();
  await field.click();
  await page.keyboard.press('Escape');
  await field.click();
  await page.keyboard.type(name, {delay: 8});
  const row = page.getByRole('button', {name: new RegExp(`Gerät ${escape(name)} ${escape(id)} auswählen`)}).first();
  await row.waitFor();
  const viewport = page.viewportSize();
  for (let attempt = 0; attempt < 8; attempt++) {
    const box = await row.boundingBox();
    if (box && box.y >= 0 && box.y + box.height <= viewport.height) break;
    await page.mouse.move(viewport.width / 2, viewport.height * .65);
    await page.mouse.wheel(0, !box || box.y > viewport.height ? 520 : -520);
    await page.waitForTimeout(180);
  }
  await row.click({force: true});
  await page.getByText('ENGINEERING WORKSPACE', {exact: true}).waitFor();
}
async function scenario(context, name = 'normal') {
  const response = await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: name}});
  assert.equal(response.status(), 200);
}

try {
  const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  await scenario(context);
  const inventoryResponse = await context.request.get(`${base}/api/v1/devices`);
  assert.equal(inventoryResponse.status(), 200);
  const inventory = await inventoryResponse.json();
  assert.equal(inventory.length, 17);
  const page = await boot(context);
  await capture(page, 'devices-initial-1440x1000');
  pass('Real Core renders the 17-device Explorer, empty Workspace, Inspector and Comparison');

  await search(page, 'AMD');
  await page.getByText('1 von 17 Geräten · Simuliertes Inventar', {exact: true}).waitFor();
  await selectDevice(page, 'AMD EVO-X2', 'evo');
  await page.getByText('Keine Telemetrie für dieses Gerät verfügbar', {exact: true}).waitFor();
  await page.getByText('CONTEXT INSPECTOR', {exact: true}).waitFor();
  await capture(page, 'devices-search-selected-1440x1000');
  pass('Slash search and selection drive Workspace and Inspector without substitute telemetry');

  await page.keyboard.press('p');
  await page.getByText('Pinned 1', {exact: true}).waitFor();
  await page.keyboard.press('c');
  await page.getByText('Comparison 1/4', {exact: true}).waitFor();
  pass('P and C act on the selected device with bounded session-local state');

  await page.keyboard.press('Escape');
  assert.equal(await page.getByText('Gerät für die technische Untersuchung auswählen', {exact: true}).count(), 0);
  // Escape in the focused input clears the query and restores the inventory.
  await page.getByRole('textbox').first().click();
  await page.keyboard.press('Escape');
  await page.getByText('17 von 17 Geräten · Simuliertes Inventar', {exact: true}).waitFor();
  await selectDevice(page, 'OPC-UA-Sensoren · M-01', 'M-01');
  await page.getByText('Fünf unabhängige Statusdimensionen', {exact: true}).waitFor();
  await page.getByText('Erreichbar · SIMULATED / REPORTED', {exact: true}).first().waitFor();
  await page.getByText('Unbekannt · kein aktiver Probe ausgeführt', {exact: true}).waitFor();
  await page.keyboard.press('c');
  await page.getByText('Comparison 2/4', {exact: true}).waitFor();
  await capture(page, 'devices-comparison-1440x1000');
  pass('Reported/simulated reachability stays separate from active probes and comparison accepts a second device');

  await page.getByText('Services', {exact: true}).click();
  await page.getByText('Kein autorisiertes Service-Inventar verfügbar.', {exact: true}).waitFor();
  await page.getByText(/keine Service-\/Service-Instance-\/Endpoint-\/Protocol-Registry/).waitFor();
  assert.equal(await page.getByText('AMD EVO-X2', {exact: true}).count(), 0);
  await capture(page, 'devices-services-missing-1440x1000');
  pass('Services is an explicit missing-capability state and never infers services from names or kind');

  await page.getByText('Inventory Health', {exact: true}).click();
  await page.getByText('17 Geräte im v1-Snapshot', {exact: true}).waitFor();
  await page.getByText('Unbekannt · Capability fehlt', {exact: true}).waitFor();
  await capture(page, 'devices-inventory-health-1440x1000');
  pass('Inventory Health distinguishes registry, source, telemetry and missing service coverage');

  await page.getByText('Devices', {exact: true}).click();
  await page.getByRole('button', {name: 'Network Explorer öffnen · Modulziel, kein ID-Deep-Link', exact: true}).click();
  await page.getByText('NETWORK ENGINEERING EXPLORER · READ-ONLY', {exact: true}).waitFor();
  await nav(page, 'Geräte & Dienste');
  await page.getByText('CONTEXT INSPECTOR', {exact: true}).waitFor();
  await page.getByText('OPC-UA-Sensoren · M-01', {exact: true}).first().waitFor();
  await page.getByText(/temperature\s+/).first().waitFor();
  assert.equal(await page.getByText('Keine Telemetrie für dieses Gerät verfügbar', {exact: true}).count(), 0);
  pass('Cross-module action opens Network; selection and DeviceDetail reload on return');

  for (const theme of ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
    await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
    await page.getByText(theme, {exact: true}).waitFor();
    await capture(page, `devices-${theme.toLowerCase()}-1440x1000`);
  }
  pass('Spectrum, Graphite and Daylight preserve the same selected engineering context');
  await page.close();

  for (const [width, height] of [
    [320, 740], [375, 812], [390, 844], [768, 1024], [834, 1112], [1024, 900], [1920, 1080],
  ]) {
    const responsive = await boot(context, width, height);
    const suffix = `${width}x${height}`;
    await capture(responsive, `devices-initial-${suffix}`);
    await selectDevice(responsive, 'OPC-UA-Sensoren · M-01', 'M-01');
    await responsive.getByText('ENGINEERING WORKSPACE', {exact: true}).waitFor();
    if (width <= 768) {
      await responsive.getByText('Inspector', {exact: true}).click();
      await responsive.getByText('CONTEXT INSPECTOR', {exact: true}).waitFor();
      await responsive.getByText('Explorer', {exact: true}).click();
    }
    await capture(responsive, `devices-selected-${suffix}`);
    await responsive.close();
  }
  pass('Responsive selection and mobile Inspector navigation verified at 320/375/390/768/834/1024/1920 plus 1440');

  assert.deepEqual(errors, [], errors.join('\n'));
  assert.deepEqual(external, []);
  assert.deepEqual(failedResources, []);
  await writeFile(resolve(out, 'browser-devices.json'), JSON.stringify({
    verdict: 'PASS', browser: await browser.version(), base, realCoreInventory: inventory.length,
    checks, captures, errors, external, failedResources, expectedFaults,
    limits: 'Real local demo Core interactions. 0/1/17/120 and multi-source synthetic fixture evidence is reported separately; no backend scaling claim.',
  }, null, 2));
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length, captures: captures.length}, null, 2));
  await context.close();
} catch (error) {
  for (const context of browser.contexts()) {
    for (const page of context.pages()) await page.screenshot({path: resolve(out, 'devices-failure.png')}).catch(() => {});
  }
  await writeFile(resolve(out, 'browser-devices-failure.json'), JSON.stringify({
    verdict: 'FAIL', error: String(error), checks, captures, errors, external, failedResources, expectedFaults,
  }, null, 2));
  throw error;
} finally {
  await browser.close();
}

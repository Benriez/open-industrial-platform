const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18768';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-phase2');
await mkdir(out, {recursive: true});
for (const file of ['phase2-failure.png', 'browser-phase2-failure.json']) {
  await rm(resolve(out, file), {force: true});
}
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1});
context.grantPermissions(['clipboard-read', 'clipboard-write'], {origin: base});
const page = await context.newPage();
const errors = [], external = [], failedResources = [], expectedFaults = [], checks = [], captures = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() !== 'error') return;
  const expected = message.text().includes('403');
  (expected ? expectedFaults : errors).push(message.text());
});
page.on('response', response => {
  if (response.status() < 400) return;
  const expected = response.status() === 403 && new URL(response.url()).pathname === '/api/v2/organizations';
  (expected ? expectedFaults : failedResources).push(response.url());
});
await context.route('**/*', route => {
  const url = new URL(route.request().url());
  if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) {
    external.push(url.href);
    return route.abort();
  }
  return route.continue();
});

async function pass(label) { checks.push(label); console.log('PASS', label); }
async function capture(name) {
  await page.screenshot({path: resolve(out, `${name}.png`)});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, name);
}
async function nav() {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (await menu.count()) {
    await menu.click();
    await page.getByText('Dismiss', {exact: true}).waitFor({state: 'visible'});
  }
  await page.getByRole('button', {name: 'Navigation OPC-UA-Browser', exact: true}).click();
  if (await menu.count()) await page.getByText('Dismiss', {exact: true}).waitFor({state: 'hidden'});
  await page.getByText('Namespace 2', {exact: true}).waitFor();
}
async function selectNode(name) {
  await page.getByRole('button', {name: new RegExp(`^Node ${name.replace('.', '\\.')},`)}).click();
}
async function chooseValueMode(label) {
  await page.getByText(/^(Original|Lokalisiert|Wissenschaft|Technisch)$/).first().click();
  await page.getByText(label, {exact: true}).last().click();
}

try {
  const scenario = await context.request.post(`${base}/api/v1/demo/scenario`, {data: {scenario: 'normal'}});
  assert.equal(scenario.status(), 200);
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav();
  await page.getByText('QUELLE', {exact: true}).waitFor();
  const runtimeSources = await context.request.get(`${base}/api/v1/sources`);
  assert.equal(runtimeSources.status(), 200);
  assert.equal((await runtimeSources.json())[0].id, 'oip-local-simulation-v1');
  await pass('Existing /sources capability drives visible source context');
  await capture('desktop-overview');

  await selectNode('temperature');
  await page.getByText('Historische API nicht verfügbar', {exact: true}).waitFor();
  await page.getByText('Keine Referenzhierarchie verfügbar', {exact: true}).waitFor();
  await pass('History and hierarchy limitations are explicit');
  await page.mouse.move(1200, 800);
  await page.mouse.wheel(0, 500);
  await page.waitForTimeout(300);
  const technical = page.getByText(/Technische OPC-UA-Details/);
  await technical.waitFor();
  await technical.click();
  await page.getByText('ValueRank', {exact: true}).waitFor();
  await page.getByText('Nicht von API geliefert', {exact: true}).first().waitFor();
  await pass('Missing OPC UA attributes are not invented');
  await capture('inspector-technical');
  await page.mouse.wheel(0, -1800);
  await page.waitForTimeout(300);

  const original = await page.getByText(/^\d+\.\d °C$/).first().innerText();
  await page.getByRole('button', {name: 'Unveränderten API-Wert kopieren', exact: true}).click();
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  // Live values may advance between reading the hero and clicking Copy.
  // Exact original-vs-formatted equality is covered deterministically in Flutter tests.
  assert.match(copied, /^\d+(\.\d+)?$/);
  assert.ok(original.length > 0);
  await chooseValueMode('Lokalisiert');
  await page.getByText('Formatierte Ansicht · Original bleibt per Kopieraktion abrufbar', {exact: true}).waitFor();
  await chooseValueMode('Wissenschaft');
  await page.getByText(/e-?\d+ °C/).first().waitFor();
  await chooseValueMode('Technisch');
  await page.getByText(/e-?\d+ °C/).first().waitFor();
  await pass('Original copy and localized/scientific/engineering value modes');
  await capture('value-engineering');

  await page.keyboard.press('Control+k');
  await page.keyboard.type('bulk.0999', {delay: 35});
  await page.getByRole('button', {name: /^Bulk Massendaten/}).click();
  await page.getByText('1 Nodes · Seite 1', {exact: true}).waitFor({timeout: 15000});
  await selectNode('bulk.0999');
  await page.getByText('Einzelabfrage', {exact: true}).first().waitFor();
  await pass('Keyboard-focused server search reaches bulk.0999 before pagination');
  await capture('server-search');

  await page.getByRole('button', {name: 'Suche löschen', exact: true}).click();
  await page.getByRole('button', {name: /^M-01/}).first().click();
  await page.getByText('6 Nodes · Seite 1', {exact: true}).waitFor();
  await page.getByRole('button', {name: 'Seitenfilter für Typ und Quality', exact: true}).click();
  await page.getByText('Typ: alle', {exact: true}).click();
  await page.getByText('Typ: Boolean', {exact: true}).last().click();
  await page.getByText('2/6 auf dieser Seite', {exact: true}).waitFor();
  await pass('Type filter is explicitly limited to the loaded six-node page');
  await capture('page-filter');
  await page.getByRole('button', {name: 'Seitenfilter zurücksetzen', exact: true}).click();
  await page.getByRole('button', {name: 'Seitenfilter für Typ und Quality', exact: true}).click();

  await selectNode('temperature');
  await page.keyboard.press('p');
  await page.keyboard.press('c');
  await page.getByRole('button', {name: 'Vergleich schließen (Esc)', exact: true}).waitFor();
  assert.equal(await page.getByRole('button', {name: /aus Vergleich entfernen/}).count(), 1);
  await page.getByRole('button', {name: 'Vergleich schließen (Esc)', exact: true}).click();
  await selectNode('pressure');
  await page.keyboard.press('c');
  await page.getByRole('button', {name: 'Vergleich schließen (Esc)', exact: true}).waitFor();
  assert.equal(await page.getByRole('button', {name: /aus Vergleich entfernen/}).count(), 2);
  await pass('P/C keyboard workflow compares real temperature and pressure data');
  await capture('node-compare');

  for (const [name, width, height] of [['tablet', 768, 1024], ['mobile', 390, 844]]) {
    await page.setViewportSize({width, height});
    await page.waitForTimeout(300);
    await capture(`compare-${name}`);
    await page.keyboard.press('Escape');
    await capture(`workstation-${name}`);
  }
  await page.setViewportSize({width: 1440, height: 1000});
  for (const theme of ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
    await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
    await page.getByText(theme, {exact: true}).waitFor();
    await capture(`theme-${theme.toLowerCase()}`);
  }
  await pass('Desktop/tablet/mobile and Spectrum/Graphite/Daylight captures');

  assert.deepEqual(errors, []);
  assert.deepEqual(external, []);
  assert.deepEqual(failedResources, []);
  await writeFile(resolve(out, 'browser-phase2.json'), JSON.stringify({
    verdict: 'PASS', browser: await browser.version(), base, checks, captures,
    errors, external, failedResources,
  }, null, 2));
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length, captures: captures.length}, null, 2));
} catch (error) {
  await capture('phase2-failure').catch(() => {});
  await writeFile(resolve(out, 'browser-phase2-failure.json'), JSON.stringify({
    verdict: 'FAIL', error: String(error), checks, errors, external, failedResources,
  }, null, 2));
  throw error;
} finally {
  await browser.close();
}

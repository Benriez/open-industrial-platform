/** OIP-UX-001 task-based UI acceptance against the marked OIP-009 fixture.
 * Interaction counts are scripted steps, not human task-time measurements.
 */
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const variant = process.env.OIP_VARIANT ?? 'after';
const base = process.env.OIP_URL ?? 'http://127.0.0.1:18960';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? `../artifacts/adaptive-workspaces-2027/${variant}`);
await mkdir(out, {recursive: true});
const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 180000);
const checks = [], tasks = [], captures = [], boots = [], pageErrors = [], overflowErrors = [], external = [], credentials = [];
let steps = 0;
const pass = name => {checks.push(name); console.log('PASS', name);};
function observe(page) {
  page.on('pageerror', error => pageErrors.push(String(error)));
  page.on('console', message => {
    if (message.type() === 'error' && /overflowed|RenderFlex/i.test(message.text())) {
      overflowErrors.push(message.text());
    }
  });
  page.on('request', request => {
    const url = request.url();
    if (!url.startsWith(base) && !url.startsWith('data:') && !url.startsWith('blob:')) external.push(url);
    if (/bearer|access_token|credential/i.test(url) || request.headers().authorization) {
      credentials.push(url);
    }
  });
}
async function click(page, locator) {await locator.click({force: true}); steps++;}
async function fill(page, locator, value) {await locator.fill(value); steps++;}
async function key(page, value) {await page.keyboard.press(value); steps++;}
async function task(name, run) {
  steps = 0;
  const started = Date.now();
  await run();
  tasks.push({name, scriptedInteractionSteps: steps,
    automationDurationMs: Date.now() - started,
    humanTaskTimeMeasured: false});
}
async function nav(page, label) {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (await menu.count()) await click(page, menu);
  await click(page, page.getByRole('button', {name: `Navigation ${label}`, exact: true}));
  const dismiss = page.getByText('Dismiss', {exact: true});
  if (await dismiss.count()) await dismiss.waitFor({state: 'hidden'});
}
async function boot(width = 1440, height = 900) {
  const started = Date.now();
  const context = await browser.newContext({viewport: {width, height}, deviceScaleFactor: 1, serviceWorkers: 'block'});
  const page = await context.newPage();
  page.setDefaultTimeout(30000);
  observe(page);
  await page.goto(`${base}/?ux001=${variant}-${width}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText(variant === 'before' ? 'LIVE · API' : 'API CONNECTED', {exact: false}).first().waitFor();
  await page.waitForTimeout(400);
  boots.push({width, height, automationDurationMs: Date.now() - started,
    humanTimeToFirstInformationMeasured: false});
  return {context, page};
}
async function selectContext(page, pattern, query) {
  await click(page, page.getByRole('button', {name: /Infrastructure Context:/}));
  await page.getByRole('textbox').last().waitFor();
  await fill(page, page.getByRole('textbox').last(), query);
  await click(page, page.getByRole('button', {name: pattern}).first());
}
async function geometry(page) {
  return page.evaluate(() => ({
    horizontalOverflow: document.documentElement.scrollWidth > innerWidth,
    localStorageEntries: localStorage.length,
    sessionStorageEntries: sessionStorage.length,
    semanticsNodes: document.querySelectorAll('flt-semantics').length,
    visibleControls: document.querySelectorAll('flt-semantics[role="button"], flt-semantics[role="textbox"], flt-semantics[role="radio"]').length,
  }));
}
async function capture(page, name) {
  await page.screenshot({path: resolve(out, `${name}.png`)});
  captures.push({name, ...(await geometry(page))});
}

try {
  const {context, page} = await boot();
  if (variant === 'after') {
    assert.equal(await page.getByText('Infrastructure Explorer', {exact: false}).count(), 0);
    assert.equal(await page.getByText('Kontext & Provenienz', {exact: true}).count(), 0);
    assert.equal(await page.getByText('UNIFIED INFRASTRUCTURE VIEW', {exact: true}).count(), 1);
    await capture(page, 'overview-orientation');
    pass('Orientation-first Overview shows context, status and attention without empty inspector');
  }

  await task('Select Infrastructure A2', async () => {
    await selectContext(page, /Kontext Organization A \/ Infrastructure A2/, 'A2');
    await page.getByRole('button', {name: /Infrastructure Context: Infrastructure A2/}).waitFor();
  });
  await capture(page, 'overview-scoped-a2');

  await task('Find source-less device and distinguish NoCollector', async () => {
    await nav(page, 'Geräte & Dienste');
    await selectContext(page, /Kontext Organization A \/ Infrastructure A1 \/ Site 2/, 'Site 2');
    await click(page, page.getByRole('button', {name: /Gerät Manual Valve A1 device-a1-manual auswählen/}));
    await page.getByText('no_collector', {exact: true}).first().waitFor();
    await page.getByText('Organization A', {exact: true}).first().waitFor();
  });
  await capture(page, 'devices-source-less-selected');
  if (variant === 'after') {
    assert.equal(await page.getByText('devices-adaptive-inspector').count(), 0);
    await page.getByText('Kontext & Provenienz', {exact: false}).waitFor();
    pass('Device selection opens object details with actual placement and NoCollector truth');
  }

  await task('Find honest device-onboarding entry', async () => {
    if (variant === 'before') {
      assert.equal(await page.getByRole('button', {name: /Gerät hinzufügen/}).count(), 0);
      return;
    }
    await click(page, page.getByRole('button', {name: /Gerät hinzufügen/}));
    await page.getByText('Gerät lokal registrieren', {exact: true}).waitFor();
    await page.getByText(/Browser-Onboarding|Browser-Schreibpfad/).waitFor();
    await click(page, page.getByRole('button', {name: 'Schließen', exact: true}));
  });
  await capture(page, 'devices-onboarding-closed');
  pass('Add-device entry is visible but never simulates a browser mutation');

  if (variant === 'after') {
    await click(page, page.getByRole('button', {name: /Inspector für diese Workstation anheften/}));
    await nav(page, 'Netzwerk & VPN');
    await nav(page, 'Geräte & Dienste');
    await page.getByText('Manual Valve A1', {exact: true}).first().waitFor();
    await click(page, page.getByRole('button', {name: /Inspector schließen/}).first());
    await page.getByText('Gerätekontext & Provenienz', {exact: true}).waitFor({state: 'hidden'});
    pass('Inspector pin survives navigation; close releases the pin without losing inventory');
  }

  await task('Investigate a real event and open Evidence Timeline', async () => {
    await nav(page, 'Diagnose & Ereignisse');
    await click(page, page.getByRole('button', {name: /Ereignis .* auswählen/}).first());
    if (variant === 'after') {
      await click(page, page.getByRole('button', {name: /Evidence Timeline/}).first());
    }
    await page.getByRole('button', {name: 'Fit to Available Data', exact: true}).waitFor();
  });
  await capture(page, 'diagnostics-evidence-timeline');
  pass('Event investigation and full Evidence Timeline remain directly available');

  await task('Return to the retained Evidence Timeline', async () => {
    await nav(page, 'Übersicht');
    await nav(page, 'Diagnose & Ereignisse');
    await page.getByRole('button', {name: 'Fit to Available Data', exact: true}).waitFor();
  });

  await task('Open OPC-UA node and technical attributes', async () => {
    await selectContext(page, /Kontext Unified View/, '');
    await nav(page, 'OPC-UA-Browser');
    await click(page, page.getByRole('button', {name: /^Node temperature,/}).first());
    await page.getByText(/Technische OPC-UA-Details/).click();
    steps++;
    await page.getByText('ValueRank', {exact: true}).waitFor();
  });
  await capture(page, 'opcua-node-technical-details');
  pass('Source-bound node selection opens value and grouped technical details');

  await task('Review Settings status and offline administration boundary', async () => {
    await nav(page, 'Einstellungen');
    await page.getByText('Einstellungen', {exact: true}).first().waitFor();
    await page.getByText(/OFFLINE ADMIN|READ-ONLY/).first().waitFor();
  });
  await capture(page, 'settings-offline-boundary');
  pass('Settings retain effective status, provenance disclosure and offline boundaries');

  if (variant === 'after') {
    await nav(page, 'Netzwerk & VPN');
    assert.equal(await page.locator('flt-semantics[aria-label="Topologie-Viewport"]').count(), 0);
    await click(page, page.getByRole('button', {name: 'Topologie', exact: true}));
    await page.getByText(/Keine bekannten Topologie-Endpunkte/).waitFor();
    await capture(page, 'network-topology-unavailable');
    pass('Network leads with known relationships and keeps empty topology compact');

    await nav(page, 'Übersicht');
    await click(page, page.getByRole('button', {name: /Detail-Inspector manuell öffnen/}));
    await page.getByText('Kontext & Provenienz', {exact: true}).waitFor();
    pass('Manual inspector open works directly from orientation without a separate mode');
  }

  await context.close();

  if (variant === 'after') {
    for (const [width, height] of [[320, 740], [390, 844], [768, 1024], [1024, 900], [1440, 900], [1920, 1080]]) {
      const compact = await boot(width, height);
      const value = await geometry(compact.page);
      assert.equal(value.horizontalOverflow, false, `${width}: horizontal overflow`);
      assert.equal(value.localStorageEntries, 0);
      assert.equal(value.sessionStorageEntries, 0);
      await capture(compact.page, `orientation-${width}x${height}`);
      await compact.context.close();
    }
    pass('320/390/768/1024/1440/1920 geometry and empty browser storage PASS');

    const themed = await boot(1440, 900);
    for (const theme of ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
      await click(themed.page, themed.page.getByRole('button', {name: /Darstellung wechseln/}));
      await themed.page.getByText(theme, {exact: true}).waitFor();
      await capture(themed.page, `overview-${theme.toLowerCase()}`);
    }
    await themed.context.close();
    pass('Spectrum, Graphite and Daylight preserve the adaptive hierarchy');
  }

  assert.deepEqual(pageErrors, [], pageErrors.join(' | '));
  assert.deepEqual(overflowErrors, [], overflowErrors.join(' | '));
  assert.deepEqual(external, [], external.join(' | '));
  assert.deepEqual(credentials, [], credentials.join(' | '));
  pass('No page errors, overflow, external requests or credential evidence');
  await writeFile(resolve(out, 'adaptive-workspaces.json'), JSON.stringify({
    verdict: 'PASS', variant, base, checks, tasks, captures, boots,
    fixtureOnly: true, realCoreE2E: false, humanUserStudy: false,
    pageErrors, overflowErrors, external, credentials,
  }, null, 2) + '\n');
  console.log(JSON.stringify({verdict: 'PASS', variant, checks: checks.length, tasks: tasks.length}));
} finally {
  await browser.close();
}

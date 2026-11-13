/**
 * Devices & Services — the geometry of the workspace.
 *
 * The layout of the workspace is a claim of the release: the operator accepts
 * the visible result (G12), and the numbers of the layout are the evidence
 * that the acceptance can look at. The journey measures the geometry in the
 * **four states** of the workspace — no selection, a device selected, the
 * secondary filters open and the comparison — at 1440 px and 1920 px, and it
 * proves that the document never scrolls horizontally in any of them.
 *
 * It replaces the journey of the generation 2027 (it is in the history of the
 * repository): that one drove the surface of the OIP/005 demo, waited for the
 * title of the old overview and named demo devices, and it was named by no
 * harness, so its proof was no receipt. This one drives the **managed**
 * surface against a real Core with an authorized session, and it names no
 * device of its own: the device it selects is a device that the Core
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

const checks = [], taken = [];
const pageErrors = [], overflowErrors = [];
const escapeRegExp = value => String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function pass(label) {
  checks.push(label);
  console.log('PASS', label);
}
let current = null;
async function capture(name) {
  await current.screenshot({path: resolve(captures, `${name}.png`)});
  taken.push(`${name}.png`);
}

function observe(page) {
  page.on('pageerror', error => pageErrors.push(String(error)));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const text = message.text();
    if (/overflowed|A RenderFlex overflowed|RenderFlex/i.test(text)) overflowErrors.push(text);
  });
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

/** The geometry of the rendered surface, read from the semantics DOM. */
async function measure(page) {
  return await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    const nodes = [...host.querySelectorAll('flt-semantics')].map(node => {
      const rect = node.getBoundingClientRect();
      const leaf = node.querySelector('flt-semantics') === null;
      const label = (node.getAttribute('aria-label') || (leaf ? node.textContent : '') || '').trim();
      return {
        role: node.getAttribute('role') || '',
        label,
        x: rect.x,
        right: rect.right,
        y: rect.y,
        bottom: rect.bottom,
        width: rect.width,
        height: rect.height,
      };
    }).filter(node => node.width > 0 && node.height > 0);

    const byLabel = needle => nodes.find(node => node.label === needle);
    const byPrefix = needle => nodes.find(node => node.label.startsWith(needle));

    const eyebrow = byLabel('DEVICES & SERVICES · OBJECT WORKSPACE');
    const countLine = nodes.find(node => /^\d+ von \d+ Geräten/.test(node.label));
    const workspaceEyebrow = byLabel('ENGINEERING WORKSPACE');
    const comparison = byLabel('SESSION-LOCAL · keine Persistenz');

    // The filter toolbar of the current surface.
    const filterPattern =
      /^(TYP|SOURCE|STANDORT|QUALIT|FRESHNESS|CONNECTIVITY|SORT)/;
    const filters = nodes.filter(node =>
      node.role === 'button' && filterPattern.test(node.label));
    const input = host.querySelector('input, textarea');
    const inputRect = input ? input.getBoundingClientRect() : null;
    const search = inputRect
      ? {x: inputRect.x, y: inputRect.y, right: inputRect.right, bottom: inputRect.bottom,
         width: inputRect.width, height: inputRect.height}
      : null;
    const reset = nodes.find(node =>
      node.role === 'button' && node.label === 'Filter zurücksetzen');
    const more = nodes.find(node =>
      node.role === 'button' && /^Weitere Filter/.test(node.label));

    const filterNodes = [...filters, search, reset, more].filter(Boolean);
    const filterTop = Math.min(...filterNodes.map(node => node.y));
    const filterBottom = Math.max(...filterNodes.map(node => node.bottom));
    const filterRows =
      new Set(filterNodes.map(node => Math.round(node.y / 4) * 4)).size;

    // The rows of the inventory: the row action buttons carry one node per
    // row, so the vertical pitch between them is the rendered row height.
    const deviceRows = nodes.filter(node =>
      node.role === 'button' && node.label.startsWith('Gerät '));
    const deviceRow = deviceRows[0] ?? null;
    const rowActions = nodes
      .filter(node => node.role === 'button' &&
        (node.label.startsWith('Gerät pinnen') || node.label.startsWith('Pin entfernen')))
      .sort((a, b) => a.y - b.y);
    const pitches = [];
    for (let index = 1; index < rowActions.length; index++) {
      pitches.push(rowActions[index].y - rowActions[index - 1].y);
    }
    pitches.sort((a, b) => a - b);
    const rowPitch = pitches.length ? pitches[Math.floor(pitches.length / 2)] : null;

    const bottomMost = nodes.reduce((max, node) => Math.max(max, node.bottom), 0);

    return {
      headerToInventoryPx: eyebrow ? Math.round(eyebrow.height) : null,
      countLineTopPx: countLine ? Math.round(countLine.y) : null,
      filterBarHeightPx: Math.round(filterBottom - filterTop),
      filterControlCount: filters.length,
      filterRowsDetected: filterRows,
      filterHasDisclosure: Boolean(more),
      searchFieldHeightPx: search ? Math.round(search.height) : null,
      resetButtonHeightPx: reset ? Math.round(reset.height) : null,
      explorerRowHeightPx: rowPitch !== null ? Math.round(rowPitch) : null,
      explorerRowSemanticHeightPx: deviceRow ? Math.round(deviceRow.height) : null,
      explorerRowWidthPx: deviceRow ? Math.round(deviceRow.width) : null,
      explorerContentLeftPx: deviceRow ? Math.round(deviceRow.x) : null,
      explorerContentRightPx: deviceRow ? Math.round(deviceRow.right) : null,
      workspaceContentLeftPx: workspaceEyebrow ? Math.round(workspaceEyebrow.x) : null,
      contentBottomPx: Math.round(bottomMost),
      comparisonStripTopPx: comparison ? Math.round(comparison.y) : null,
      documentScrollHeightPx: document.documentElement.scrollHeight,
      documentScrollWidthPx: document.documentElement.scrollWidth,
      viewportHeightPx: innerHeight,
      viewportWidthPx: innerWidth,
    };
  });
}

/** The authorized session of the operator: the managed surface asks for it. */
async function login(page) {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,
    ['--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
     '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL], {encoding: 'utf8'}));
  const code = page.getByRole('textbox', {name: 'Einmalcode'});
  for (let n = 0; !(await code.isEditable()); n++) {
    if (n === 100) throw Error('the code field did not become editable');
    await page.waitForTimeout(100);
  }
  await code.click({force: true});
  await page.waitForTimeout(300);
  await page.keyboard.type(minted.login_code, {delay: 40});
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true}).click();
  await page.waitForTimeout(2500);
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

try {
  for (const [width, height] of [[1440, 900], [1920, 1080]]) {
    const context = await browser.newContext({
      viewport: {width, height},
      deviceScaleFactor: 1,
      serviceWorkers: 'block',
    });
    const page = await context.newPage();
    current = page;
    page.setDefaultTimeout(20000);
    observe(page);
    await page.goto(`${base}/?devices-geometry=${width}x${height}`,
      {waitUntil: 'domcontentloaded'});
    await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true})
      .waitFor({timeout: bootTimeout});
    await login(page);
    await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
    await page.getByText('API CONNECTED', {exact: false}).waitFor();
    await nav(page, 'Geräte & Dienste');
    await page.getByText('DEVICES & SERVICES · OBJECT WORKSPACE', {exact: true})
      .waitFor({timeout: bootTimeout});
    await page.getByText(/\d+ von \d+ Geräten/).first().waitFor({timeout: bootTimeout});
    await page.waitForTimeout(700);

    // The device of the Core: the journey names none of its own.
    const answer = await context.request.get(`${base}/api/v2/inventory/devices?limit=100&include_archived=false`,
      {timeout: 60000});
    assert.equal(answer.status(), 200, 'the Core answered the inventory');
    const inventory = await answer.json();
    // The inventory of the Core: the record of a device carries the device.
    const devices = (inventory.items ?? []).map(item => ({
      the_id: item.record?.device?.id ?? item.id,
      the_name: item.record?.device?.display_name ?? item.name,
    }));
    assert.ok(devices.length > 0, 'the Core delivered no device');
    const wanted = devices[0];

    const geometry = {the_viewport: {width, height}, the_devices_of_the_core: devices};

    // 1. no device selected
    geometry.noSelection = await measure(page);
    await capture(`${width}x${height}-1-no-selection`);

    // 2. the device of the Core is selected
    await page.getByRole('button', {
      name: new RegExp(`Gerät ${escapeRegExp(wanted.the_name)} .* auswählen`)})
      .first().click({force: true});
    await page.waitForTimeout(900);
    geometry.selected = await measure(page);
    await capture(`${width}x${height}-2-device-selected`);

    // 3. the secondary filters are open
    const more = page.getByRole('button', {name: /Weitere Filter/}).first();
    const hasDisclosure = (await more.count()) > 0;
    if (hasDisclosure) {
      await more.click({force: true});
      await page.waitForTimeout(600);
    }
    geometry.filtersOpen = await measure(page);
    geometry.filtersDisclosurePresent = hasDisclosure;
    await capture(`${width}x${height}-3-filters-open`);
    if (hasDisclosure) {
      await more.click({force: true});
      await page.waitForTimeout(450);
    }

    // 4. the comparison of the device
    await page.getByRole('button', {
      name: new RegExp(`Gerät ${escapeRegExp(wanted.the_name)} .* auswählen`)})
      .first().click({force: true});
    await page.waitForTimeout(600);
    await page.keyboard.press('c');
    await page.waitForTimeout(700);
    geometry.comparison = await measure(page);
    await capture(`${width}x${height}-4-comparison`);

    for (const state of ['noSelection', 'selected', 'filtersOpen', 'comparison']) {
      assert.equal(geometry[state].documentScrollWidthPx <= width, true,
        `${width}: the ${state} state scrolls horizontally`);
    }
    assert.ok(geometry.noSelection.explorerRowHeightPx,
      `${width}: the inventory renders no row`);
    pass(`${width}x${height}: the four states of the workspace are measured, no horizontal overflow`);

    await writeFile(resolve(out, `geometry-${width}x${height}.json`),
      `${JSON.stringify(geometry, null, 2)}\n`);
    await context.close();
  }

  assert.deepEqual(pageErrors, [], `page errors: ${pageErrors.join(' | ')}`);
  pass('no page errors in any captured state');
  assert.deepEqual(overflowErrors, [], `overflow errors: ${overflowErrors.join(' | ')}`);
  pass('no RenderFlex overflow errors in any captured state');

  await writeFile(resolve(out, 'devices-geometry.json'), JSON.stringify({
    status: 'PASS',
    the_revision: process.env.OIP_REVISION,
    the_checks: checks,
    the_captures: taken,
    the_page_errors: pageErrors,
    the_overflow_errors: overflowErrors,
  }, null, 2));
  console.log(JSON.stringify({status: 'PASS', checks: checks.length}, null, 2));
} catch (error) {
  await capture('failure');
  await writeFile(resolve(out, 'failure-semantics.html'),
    await current.evaluate(() => {
      const host = document.querySelector('flt-semantics-host');
      return host ? host.outerHTML : '';
    }).catch(() => ''));
  await writeFile(resolve(out, 'failure.json'), JSON.stringify({
    status: 'FAIL',
    error: String(error && error.message || error),
    the_checks: checks,
  }, null, 2));
  console.error(error);
  await browser.close();
  process.exit(1);
}
await browser.close();

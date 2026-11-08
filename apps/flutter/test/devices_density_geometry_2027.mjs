/**
 * Devices & Services 2027 — density / geometry measurement and before-after
 * capture.
 *
 * Runs against the release build served by the live harness. The script is
 * build-agnostic: it works with the pre-refactor layout (filters always open)
 * and with the post-refactor layout (compact toolbar + "Weitere Filter").
 *
 * All geometry is read from the real Flutter semantics DOM of the release
 * build, never from a source-code constant.
 *
 * Usage:
 *   OIP_URL=http://127.0.0.1:18948 \
 *   OIP_EVIDENCE_DIR=../artifacts/devices-density-2027 \
 *   OIP_PHASE=before|after \
 *   node test/devices_density_geometry_2027.mjs
 */
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18948';
const phase = process.env.OIP_PHASE ?? 'after';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/devices-density-2027', phase);
await mkdir(out, {recursive: true});

const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});

const checks = [];
const pass = label => {
  checks.push(label);
  console.log('PASS', label);
};

const pageErrors = [];
const overflowErrors = [];

function observe(page) {
  page.on('pageerror', error => pageErrors.push(String(error)));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const text = message.text();
    if (/overflowed|A RenderFlex overflowed|RenderFlex/i.test(text)) overflowErrors.push(text);
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

async function selectDevice(page, name, id) {
  const field = page.getByRole('textbox').first();
  await field.click();
  await page.keyboard.press('Escape');
  await field.click();
  await page.keyboard.type(name, {delay: 8});
  const row = page.getByRole('button', {name: new RegExp(`Gerät ${name} ${id} auswählen`)}).first();
  await row.waitFor();
  await row.click({force: true});
  await page.getByText('ENGINEERING WORKSPACE', {exact: true}).waitFor();
  await page.waitForTimeout(350);
}

async function clearSearch(page) {
  const field = page.getByRole('textbox').first();
  await field.click();
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
}

/**
 * Reads the Flutter semantics DOM and derives the page geometry from it.
 * Executed inside the page, so the numbers are the rendered ones.
 */
async function measure(page) {
  return await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    const nodes = [...host.querySelectorAll('flt-semantics')]
      .map(node => {
        const rect = node.getBoundingClientRect();
        const leaf = node.querySelector('flt-semantics') === null;
        const raw = node.getAttribute('aria-label') ||
          (leaf ? (node.textContent || '') : '');
        return {
          role: node.getAttribute('role') || '',
          label: raw.trim(),
          x: rect.x,
          y: rect.y,
          right: rect.right,
          bottom: rect.bottom,
          width: rect.width,
          height: rect.height,
        };
      })
      .filter(node => node.width > 0 && node.height > 0);

    const byLabel = needle => nodes.find(node => node.label === needle);
    const byPrefix = needle => nodes.find(node => node.label.startsWith(needle));

    const eyebrow = byLabel('DEVICES & SERVICES · ENGINEERING WORKSTATION');
    const explorerLabel = byLabel('INVENTORY EXPLORER');
    const countLine = nodes.find(node => /^\d+ von \d+ Geräten/.test(node.label));
    const workspaceEyebrow = byLabel('ENGINEERING WORKSPACE');
    const inspectorEyebrow = byLabel('CONTEXT INSPECTOR');

    // Filter controls: the dropdown semantics carry "LABEL\nvalue".
    const filterPattern =
      new RegExp('^(TYP|SOURCE|STANDORT|QUALIT' + String.fromCharCode(196) + 'T|FRESHNESS|CONNECTIVITY|SORT'
        + 'IERUNG)' + String.fromCharCode(10));
    const filters = nodes.filter(node =>
      node.role === 'button' && filterPattern.test(node.label),
    );
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

    const note = nodes.find(node => node.label.startsWith('v1-Snapshot'));
    const filterNodes = [...filters, search, reset, more, note].filter(Boolean);
    const filterTop = Math.min(...filterNodes.map(node => node.y));
    const filterBottom = Math.max(...filterNodes.map(node => node.bottom));
    const filterRows =
      new Set(filterNodes.map(node => Math.round(node.y / 4) * 4)).size;

    // Explorer rows. The row action buttons carry one node per row, so the
    // vertical pitch between them is the rendered row height.
    const deviceRows = nodes.filter(node => node.role === 'button' && node.label.startsWith('Gerät '));
    const deviceRow = deviceRows[0] ?? null;
    const rowActions = nodes
        .filter(node =>
          node.role === 'button' &&
          (node.label.startsWith('Ger\u00e4t pinnen') ||
           node.label.startsWith('Pin entfernen')))
        .sort((a, b) => a.y - b.y);
    const pitches = [];
    for (let index = 1; index < rowActions.length; index++) {
      pitches.push(rowActions[index].y - rowActions[index - 1].y);
    }
    pitches.sort((a, b) => a - b);
    const rowPitch = pitches.length ? pitches[Math.floor(pitches.length / 2)] : null;

    // Inspector and comparison markers.
    const comparison = byLabel('SESSION-LOCAL · keine Persistenz');
    const scopeChip = byPrefix('Pinned');

    const bottomMost = nodes.reduce((max, node) => Math.max(max, node.bottom), 0);

    return {
      headerToInventoryPx: eyebrow && explorerLabel ? Math.round(explorerLabel.y - eyebrow.y) : null,
      inventoryTopFromViewportPx: explorerLabel ? Math.round(explorerLabel.y) : null,
      countLineTopPx: countLine ? Math.round(countLine.y) : null,
      filterBarHeightPx: Math.round(filterBottom - filterTop),
      filterControlCount: filters.length,
      filterRowsDetected: filterRows,
      filterHasDisclosure: Boolean(more),
      searchFieldHeightPx: search ? Math.round(search.height) : null,
      resetButtonHeightPx: reset ? Math.round(reset.height) : null,
      explorerRowHeightPx: rowPitch !== null ? Math.round(rowPitch) : null,
      explorerRowSemanticHeightPx: deviceRow ? Math.round(deviceRow.height) : null,
      explorerChromePx:
        explorerLabel && rowActions.length
          ? Math.round(rowActions[0].y - explorerLabel.y)
          : null,
      explorerRowWidthPx: deviceRow ? Math.round(deviceRow.width) : null,
      explorerContentLeftPx: deviceRow ? Math.round(deviceRow.x) : null,
      explorerContentRightPx: deviceRow ? Math.round(deviceRow.right) : null,
      workspaceContentLeftPx: workspaceEyebrow ? Math.round(workspaceEyebrow.x) : null,
      inspectorContentLeftPx: inspectorEyebrow ? Math.round(inspectorEyebrow.x) : null,
      visibleGutterExplorerToWorkspacePx:
        deviceRow && workspaceEyebrow ? Math.round(workspaceEyebrow.x - deviceRow.right) : null,
      visibleGutterWorkspaceToInspectorPx:
        workspaceEyebrow && inspectorEyebrow
          ? Math.round(inspectorEyebrow.x - workspaceEyebrow.right)
          : null,
      scopeChipTopPx: scopeChip ? Math.round(scopeChip.y) : null,
      comparisonStripTopPx: comparison ? Math.round(comparison.y) : null,
      contentBottomPx: Math.round(bottomMost),
      documentScrollHeightPx: document.documentElement.scrollHeight,
      viewportHeightPx: innerHeight,
    };
  });
}

async function openAdvancedFilters(page) {
  const toggle = page.getByRole('button', {name: /Weitere Filter/}).first();
  if (await toggle.count()) {
    await toggle.click({force: true});
    await page.waitForTimeout(450);
    return true;
  }
  return false;
}

try {
  for (const [width, height] of [[1440, 900], [1920, 1080]]) {
    const context = await browser.newContext({
      viewport: {width, height},
      deviceScaleFactor: 1,
      serviceWorkers: 'block',
    });
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    observe(page);
    await page.goto(`${base}/?devices-density=${width}x${height}`, {waitUntil: 'domcontentloaded'});
    await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: 60000});
    await page.getByText('API CONNECTED', {exact: false}).waitFor();
    await nav(page, 'Geräte & Dienste');
    await page.getByText('DEVICES & SERVICES · ENGINEERING WORKSTATION', {exact: true}).waitFor();
    await page.getByText(/\d+ von \d+ Geräten/).first().waitFor();
    await page.waitForTimeout(700);

    const geometry = {};

    // 1. no device selected
    geometry.noSelection = await measure(page);
    await page.screenshot({path: resolve(out, `${width}x${height}-1-no-selection.png`)});

    // 2. device selected
    await selectDevice(page, 'AMD EVO-X2', 'evo');
    geometry.selected = await measure(page);
    await page.screenshot({path: resolve(out, `${width}x${height}-2-device-selected.png`)});

    // 3. filters opened
    const hasDisclosure = await openAdvancedFilters(page);
    geometry.filtersOpen = await measure(page);
    geometry.filtersDisclosurePresent = hasDisclosure;
    await page.screenshot({path: resolve(out, `${width}x${height}-3-filters-open.png`)});
    if (hasDisclosure) {
      await page.getByRole('button', {name: /Weitere Filter/}).first().click({force: true});
      await page.waitForTimeout(350);
    }

    // 4. comparison view
    await clearSearch(page);
    await selectDevice(page, 'OPC-UA-Sensoren · M-01', 'M-01');
    await page.keyboard.press('c');
    await page.waitForTimeout(450);
    geometry.comparison = await measure(page);
    await page.screenshot({path: resolve(out, `${width}x${height}-4-comparison.png`)});

    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
      false,
      `${width}: no horizontal overflow`,
    );
    pass(`${width}x${height}: four states captured, no horizontal overflow`);

    geometry.viewport = {width, height};
    await writeFile(resolve(out, `geometry-${width}x${height}.json`), `${JSON.stringify(geometry, null, 2)}\n`);
    await context.close();
  }

  assert.deepEqual(pageErrors, [], `page errors: ${pageErrors.join(' | ')}`);
  pass('no page errors in any captured state');
  assert.deepEqual(overflowErrors, [], `overflow errors: ${overflowErrors.join(' | ')}`);
  pass('no RenderFlex overflow errors in any captured state');

  await writeFile(
    resolve(out, 'density-report.json'),
    `${JSON.stringify({verdict: 'PASS', phase, base, checks, pageErrors, overflowErrors}, null, 2)}\n`,
  );
  console.log(JSON.stringify({verdict: 'PASS', phase, checks: checks.length}, null, 2));
} finally {
  await browser.close();
}

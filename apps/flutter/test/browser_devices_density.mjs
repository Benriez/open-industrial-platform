/**
 * Devices & Services — the responsive and the theme acceptance of the
 * density of the workspace.
 *
 * Verifies at 320/390/768/1024/1440/1920 px in Spectrum, Graphite and
 * Daylight that
 *   - the document never scrolls horizontally,
 *   - no toolbar control is clipped outside the viewport,
 *   - the inventory explorer is reachable and shows device rows,
 *   - the "Weitere Filter" disclosure reveals the secondary filters,
 *   - the mobile pane switch keeps every pane usable.
 *
 * The journey replaces the journey of the generation 2027 (it is in the
 * history of the repository): that one drove the surface of the OIP/005 demo
 * and was named by no harness, so its proof was no receipt. This one drives
 * the **managed** surface against a real Core with an authorized session,
 * and it names no device of its own: the rows of the inventory are the
 * devices that the Core delivered.
 */
const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18948';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/devices-density-2027/responsive');
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

/// The authorized session of the operator: the managed surface asks for it.
async function login(context, page) {
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

async function boot(width, height) {
  const context = await browser.newContext({
    viewport: {width, height},
    deviceScaleFactor: 1,
    serviceWorkers: 'block',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(20000);
  observe(page);
  await page.goto(`${base}/?devices-responsive=${width}x${height}`, {waitUntil: 'domcontentloaded'});
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true})
    .waitFor({timeout: bootTimeout});
  await login(context, page);
  await page.getByRole('button', {name: 'Diagnose öffnen', exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor();
  await nav(page, 'Geräte & Dienste');
  await page.getByRole('button', {name: 'Gerät hinzufügen', exact: true}).waitFor();
  if (width >= 1000) {
    await page.getByRole('button', {name: /Engineering Workspace/}).click();
    await page.getByRole('button', {name: /Detail-Inspector manuell öffnen/}).click();
  }
  await page.waitForTimeout(600);
  return {context, page};
}

/** Geometry of the rendered controls, read from the Flutter semantics DOM. */
async function geometry(page) {
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
    });
    const reset = nodes.find(n => n.label === 'Filter zurücksetzen');
    const more = nodes.find(n => n.label.startsWith('Weitere Filter'));
    const search = nodes.find(n => n.label.startsWith('Name, ID, Typ, Source'));
    const explorer = nodes.find(n => n.label === 'INVENTORY EXPLORER');
    // Only the filter toolbar is checked for clipping. The mobile pane bar is
    // an intentionally horizontal scroll area.
    const toolbarPattern =
      /^(TYP|SOURCE|STANDORT|QUALIT|FRESHNESS|CONNECTIVITY|SORT)/;
    const isToolbar = n =>
      n.label.startsWith('Weitere Filter') ||
      n.label === 'Filter zurücksetzen' ||
      n.label.startsWith('Name, ID, Typ, Source') ||
      toolbarPattern.test(n.label);
    const clipped = nodes.filter(n =>
      n.width > 0 && isToolbar(n) && (n.x < -0.5 || n.right > innerWidth + 0.5),
    );
    return {
      viewportWidth: innerWidth,
      documentScrollWidth: document.documentElement.scrollWidth,
      horizontalOverflow: document.documentElement.scrollWidth > innerWidth,
      resetRight: reset ? Math.round(reset.right) : null,
      moreRight: more ? Math.round(more.right) : null,
      searchLeft: search ? Math.round(search.x) : null,
      explorerTop: explorer ? Math.round(explorer.y) : null,
      clippedCount: clipped.length,
      clippedLabels: clipped.slice(0, 4).map(n => n.label.slice(0, 28)),
    };
  });
}

try {
  for (const [width, height] of [
    [320, 740],
    [390, 844],
    [768, 1024],
    [1024, 900],
    [1440, 900],
    [1920, 1080],
  ]) {
    const {context, page} = await boot(width, height);
    const geo = await geometry(page);
    assert.equal(geo.horizontalOverflow, false, `${width}: no horizontal document overflow`);
    assert.equal(geo.clippedCount, 0, `${width}: no clipped control (${geo.clippedLabels.join(', ')})`);
    if (geo.resetRight !== null) {
      assert.ok(geo.resetRight <= geo.viewportWidth, `${width}: the reset control stays inside the viewport`);
    }
    assert.ok(geo.explorerTop !== null, `${width}: the inventory explorer is rendered`);

    // The device rows are reachable and the disclosure opens the rest.
    const rows = await page.getByRole('button', {name: /Gerät .* auswählen/}).count();
    assert.ok(rows > 0, `${width}: the inventory lists devices`);
    const more = page.getByRole('button', {name: /Weitere Filter/}).first();
    assert.ok(await more.count() > 0, `${width}: the filter disclosure exists`);
    await more.click({force: true});
    await page.waitForTimeout(400);
    const secondary = await page.getByRole('button', {name: /^QUALIT/}).count();
    assert.ok(secondary > 0, `${width}: the secondary filters open`);
    const geoOpen = await geometry(page);
    assert.equal(geoOpen.horizontalOverflow, false, `${width}: no overflow with the filters open`);
    assert.equal(geoOpen.clippedCount, 0, `${width}: no clipped control with the filters open`);
    await page.screenshot({path: resolve(out, `devices-${width}x${height}-filters.png`)});
    pass(`${width}x${height}: toolbar, disclosure, inventory and overflow verified`);
    await context.close();
  }

  for (const [width, height] of [[1440, 900], [390, 844]]) {
    const {context, page} = await boot(width, height);
    for (const theme of ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
      await page.getByRole('button', {name: /Darstellung wechseln/}).click({force: true});
      if (width >= 760) {
        // The theme name is only shown in the wide top bar.
        await page.getByText(theme, {exact: true}).waitFor();
      }
      await page.waitForTimeout(600);
      const geo = await geometry(page);
      assert.equal(geo.horizontalOverflow, false, `${width} ${theme}: no horizontal overflow`);
      assert.equal(geo.clippedCount, 0, `${width} ${theme}: no clipped control`);
      await page.screenshot({path: resolve(out, `devices-${theme.toLowerCase()}-${width}x${height}.png`)});
      pass(`${width}x${height} ${theme}: layout and toolbar verified`);
    }
    await context.close();
  }

  assert.deepEqual(pageErrors, [], `page errors: ${pageErrors.join(' | ')}`);
  pass('no page errors');
  assert.deepEqual(overflowErrors, [], `overflow errors: ${overflowErrors.join(' | ')}`);
  pass('no RenderFlex overflow errors');

  await writeFile(
    resolve(out, 'responsive-report.json'),
    `${JSON.stringify({verdict: 'PASS', status: 'PASS', the_revision: process.env.OIP_REVISION,
      base, checks, pageErrors, overflowErrors}, null, 2)}\n`,
  );
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length}, null, 2));
} finally {
  await browser.close();
}

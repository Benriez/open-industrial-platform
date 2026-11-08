const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18945';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/sidebar-cleanup-2027');
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
async function boot(width, height) {
  const context = await browser.newContext({viewport: {width, height}, deviceScaleFactor: 1});
  const page = await context.newPage();
  await page.goto(`${base}/?sidebar-cleanup=${width}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor({timeout: 30000});
  return {context, page};
}
async function openDrawer(page) {
  const menu = page.getByRole('button', {name: /Navigation öffnen/});
  if (!(await menu.count())) return false;
  await menu.click();
  await page.getByText('Dismiss', {exact: true}).waitFor({state: 'visible'});
  return true;
}
async function closeDrawer(page) {
  const dismiss = page.getByText('Dismiss', {exact: true});
  if (await dismiss.count()) {
    await dismiss.click({force: true});
    await dismiss.waitFor({state: 'hidden'});
  }
}

try {
  // --- Desktop -------------------------------------------------------------
  {
    const {context, page} = await boot(1440, 1000);
    await page.waitForTimeout(600);
    assert.equal(await page.getByText('AGENT-FIRST', {exact: true}).count(), 0, 'AGENT-FIRST badge removed');
    assert.equal(await page.getByText('Read-only · Rust-Capabilities.', {exact: true}).count(), 0, 'read-only card removed');
    assert.equal(await page.getByText('MCP · REST/SSE · Flutter.', {exact: true}).count(), 0, 'stack card removed');
    assert.equal(await page.getByText('AGENT-FIRST').count(), 0, 'no AGENT-FIRST anywhere in the shell');
    const navigation = await page.getByRole('button', {name: /^Navigation /}).allTextContents();
    assert.deepEqual(navigation, [
      'Navigation Übersicht',
      'Navigation Geräte & Dienste',
      'Navigation Netzwerk & VPN',
      'Navigation OPC-UA-Browser',
      'Navigation Diagnose & Ereignisse',
      'Navigation Einstellungen',
    ], 'navigation unchanged and ends with Einstellungen');
    pass('Desktop sidebar shows branding and six navigation items only');
    await page.screenshot({path: resolve(out, 'sidebar-desktop-1440.png')});
    // selection state and themes unchanged
    await page.getByRole('button', {name: 'Navigation Geräte & Dienste', exact: true}).click({force: true});
    await page.waitForTimeout(900);
    await page.getByRole('button', {name: 'Navigation Einstellungen', exact: true}).click({force: true});
    await page.getByText('SETTINGS · APPLICATION MANAGEMENT', {exact: true}).waitFor({timeout: 30000});
    pass('Navigation selection state still works after the sidebar change');
    await page.screenshot({path: resolve(out, 'sidebar-desktop-settings-1440.png')});
    await context.close();
  }

  // --- Tablet (drawer) ----------------------------------------------------
  {
    const {context, page} = await boot(768, 1024);
    await openDrawer(page);
    await page.waitForTimeout(400);
    assert.equal(await page.getByText('AGENT-FIRST', {exact: true}).count(), 0, 'tablet drawer: card removed');
    assert.equal(await page.getByText('Read-only · Rust-Capabilities.', {exact: true}).count(), 0, 'tablet drawer: read-only card removed');
    assert.equal(await page.getByRole('button', {name: 'Navigation Einstellungen', exact: true}).count(), 1, 'tablet drawer: Einstellungen present');
    pass('Tablet drawer contains no AGENT-FIRST card and ends with Einstellungen');
    await page.screenshot({path: resolve(out, 'sidebar-tablet-drawer-768.png')});
    await closeDrawer(page);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'tablet overflow');
    await page.screenshot({path: resolve(out, 'sidebar-tablet-768.png')});
    await context.close();
  }

  // --- Mobile -------------------------------------------------------------
  {
    const {context, page} = await boot(320, 740);
    await openDrawer(page);
    await page.waitForTimeout(400);
    assert.equal(await page.getByText('AGENT-FIRST', {exact: true}).count(), 0, 'mobile drawer: card removed');
    assert.equal(await page.getByText('MCP · REST/SSE · Flutter.', {exact: true}).count(), 0, 'mobile drawer: stack card removed');
    assert.equal(await page.getByRole('button', {name: 'Navigation Einstellungen', exact: true}).count(), 1, 'mobile drawer: Einstellungen present');
    pass('Mobile drawer contains no AGENT-FIRST card and ends with Einstellungen');
    await page.screenshot({path: resolve(out, 'sidebar-mobile-drawer-320.png')});
    await closeDrawer(page);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'mobile overflow');
    await page.screenshot({path: resolve(out, 'sidebar-mobile-320.png')});
    await context.close();
  }

  // --- Themes unchanged ----------------------------------------------------
  {
    const {context, page} = await boot(1440, 1000);
    await page.getByRole('button', {name: 'Navigation Einstellungen', exact: true}).click({force: true});
    await page.getByText('SETTINGS · APPLICATION MANAGEMENT', {exact: true}).waitFor({timeout: 30000});
    await page.getByRole('button', {name: /Settings-Kategorie General/}).first().click({force: true});
    await page.waitForTimeout(300);
    await page.getByRole('button', {name: /Settings-Bereich Appearance & Preferences/}).first().click({force: true});
    await page.waitForTimeout(400);
    for (const [theme, file] of [['Graphite', 'sidebar-graphite-1440.png'], ['Daylight', 'sidebar-daylight-1440.png']]) {
      await page.locator(`flt-semantics[aria-label^="Theme ${theme}"]`).first().click({force: true});
      await page.waitForTimeout(700);
      // The Settings page header keeps its own status chip; the sidebar card is
      // proven removed by the absence of its unique texts.
      assert.equal(await page.getByText('Read-only · Rust-Capabilities.', {exact: true}).count(), 0, `${theme}: read-only card removed`);
      assert.equal(await page.getByText('MCP · REST/SSE · Flutter.', {exact: true}).count(), 0, `${theme}: stack card removed`);
      await page.getByRole('button', {name: 'Navigation Übersicht', exact: true}).click({force: true});
      await page.getByText('Operations Workstation', {exact: true}).waitFor();
      await page.waitForTimeout(600);
      assert.equal(await page.getByText('AGENT-FIRST', {exact: true}).count(), 0, `${theme}: no AGENT-FIRST badge outside the Settings page`);
      await page.screenshot({path: resolve(out, file)});
      await page.getByRole('button', {name: 'Navigation Einstellungen', exact: true}).click({force: true});
      await page.getByText('SETTINGS · APPLICATION MANAGEMENT', {exact: true}).waitFor({timeout: 30000});
      await page.getByRole('button', {name: /Settings-Kategorie General/}).first().click({force: true});
      await page.waitForTimeout(300);
      await page.getByRole('button', {name: /Settings-Bereich Appearance & Preferences/}).first().click({force: true});
      await page.waitForTimeout(400);
    }
    pass('Graphite and Daylight keep the cleaned sidebar');
    await context.close();
  }

  const report = {
    verdict: 'PASS',
    base,
    checks: checks.length,
    checkList: checks,
    captures: [
      'sidebar-desktop-1440.png',
      'sidebar-desktop-settings-1440.png',
      'sidebar-tablet-drawer-768.png',
      'sidebar-tablet-768.png',
      'sidebar-mobile-drawer-320.png',
      'sidebar-mobile-320.png',
      'sidebar-graphite-1440.png',
      'sidebar-daylight-1440.png',
    ],
    agentFirstCardRemoved: true,
    sidebarEndsWithSettings: true,
    navigationUnchanged: true,
  };
  await writeFile(resolve(out, 'sidebar-cleanup.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length}, null, 2));
} finally {
  await browser.close();
}

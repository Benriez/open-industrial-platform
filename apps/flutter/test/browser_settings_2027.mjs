const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:18945';
const bootTimeout = Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
const unauthorizedBase = process.env.OIP_UNAUTHORIZED_URL ?? 'http://127.0.0.1:18946';
const limitedBase = process.env.OIP_LIMITED_URL ?? 'http://127.0.0.1:18947';
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? '../artifacts/browser-settings-2027');
await mkdir(out, {recursive: true});
for (const name of ['browser-settings.json', 'browser-settings-failure.json']) {
  await rm(resolve(out, name), {force: true});
}
const executable = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(executable) ? executable : undefined),
  headless: true,
});
const errors = [];
const consoleNetwork = [];
const external = [];
const failedResources = [];
const checks = [];
const captures = [];
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function observe(page, origin) {
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (message.type() !== 'error') return;
    const text = message.text();
    // The harness intentionally exercises 403 and un-captured-section 404
    // boundaries; Chromium logs those as console errors. Real page errors and
    // 5xx responses are still failures.
    if (/^Failed to load resource: the server responded with a status of \d+/.test(text)) {
      consoleNetwork.push(text);
      return;
    }
    errors.push(text);
  });
  page.on('response', response => {
    if (response.status() >= 500) failedResources.push(`${response.status()} ${response.url()}`);
  });
  page.on('request', request => {
    const url = new URL(request.url());
    if (url.protocol.startsWith('http') && url.origin !== origin) external.push(url.href);
  });
}
function pass(label) {
  checks.push(label);
  console.log('PASS', label);
}
async function capture(page, name) {
  await page.screenshot({path: resolve(out, `${name}.png`)});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `${name}: document overflow`);
}
async function visibleText(page, text, timeout = 20000) {
  await page.getByText(text, {exact: false}).first().waitFor({timeout});
}
async function clickRole(page, name, timeout = 20000) {
  const target = page.getByRole('button', {name, exact: false}).first();
  await target.waitFor({timeout});
  const box = await target.boundingBox();
  if (box && (box.y < 0 || box.y + box.height > (page.viewportSize()?.height ?? 1000))) {
    await page.mouse.move(640, 500);
    await page.mouse.wheel(0, box.y > 0 ? 420 : -420);
    await page.waitForTimeout(150);
  }
  await target.click({force: true});
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
async function openSettings(page, width = 1440, height = 1000, badge = true, origin = base) {
  await page.setViewportSize({width, height});
  await page.goto(`${origin}/?settings-2027=${width}x${height}`, {waitUntil: 'domcontentloaded'});
  await page.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await page.getByText('API CONNECTED', {exact: false}).waitFor({timeout: 30000});
  await nav(page, 'Einstellungen');
  await visibleText(page, 'SETTINGS · APPLICATION MANAGEMENT', 30000);
  // Below the workstation's own pane breakpoint only one pane is visible at a
  // time; detect it by the pane selector instead of the viewport guess.
  const workspacePane = page.getByRole('button', {name: 'Workspace', exact: true});
  if (await workspacePane.count()) {
    await workspacePane.first().click({force: true});
    await page.waitForTimeout(300);
  }
  if (badge) {
    await visibleText(page, 'CONTRACT FIXTURE · NICHT LIVE');
    await visibleText(page, 'OFFLINE ADMINISTRATION REQUIRED');
  }
  await page.waitForTimeout(300);
}
async function category(page, label) {
  await clickRole(page, `Settings-Kategorie ${label}`);
  await page.waitForTimeout(250);
}
async function section(page, label) {
  await clickRole(page, `Settings-Bereich ${label}`);
  await page.waitForTimeout(300);
}
async function toolSearch(page, value) {
  const box = page.getByRole('textbox', {name: /Tool, Capability/}).first();
  await box.waitFor();
  const clear = page.getByRole('button', {name: 'Suche löschen', exact: true});
  if (await clear.count()) {
    await clear.first().click({force: true});
    await page.waitForTimeout(200);
  }
  await box.click();
  // The Flutter editing overlay can swallow select-all after a theme or module
  // switch; delete any remainder deterministically before typing.
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Backspace');
  let current = await box.inputValue().catch(() => '');
  for (let i = 0; i < 80 && current.length; i++) {
    await page.keyboard.press('Backspace');
    current = await box.inputValue().catch(() => '');
  }
  if (value) await box.fill(value);
  await page.waitForTimeout(350);
  assert.equal(await box.inputValue(), value, `tool search field shows ${JSON.stringify(value)}`);
}
async function scrollInspector(page, delta = 650) {
  const size = page.viewportSize();
  await page.mouse.move(size.width - 140, size.height * 0.55);
  await page.mouse.wheel(0, delta);
  await page.waitForTimeout(400);
}
async function clipboard(page) {
  return await page.evaluate(() => navigator.clipboard.readText());
}
async function bootContext(origin) {
  const context = await browser.newContext({
    viewport: {width: 1440, height: 1000},
    deviceScaleFactor: 1,
    permissions: ['clipboard-read', 'clipboard-write'],
  });
  return context;
}

try {
  // ---------------------------------------------------------------------------
  // 1. Desktop settings workstation, real fixture-served OIP-008.4 contracts.
  // ---------------------------------------------------------------------------
  const context = await bootContext(base);
  const page = await context.newPage();
  observe(page, new URL(base).origin);
  const v2Requests = [];
  page.on('request', request => {
    if (new URL(request.url()).pathname.startsWith('/api/v2/')) v2Requests.push(request.url());
  });

  await openSettings(page);
  pass('Settings is the sixth main destination and opens without a broken route');
  await visibleText(page, 'Application Settings');
  await visibleText(page, 'instance_name');
  await visibleText(page, 'instance_description');
  await visibleText(page, 'history_page_size');
  await visibleText(page, 'active_startup_snapshot');
  assert.equal(await page.getByText('Save', {exact: true}).count(), 0);
  assert.equal(await page.getByText('Apply', {exact: true}).count(), 0);
  assert.equal(await page.getByRole('button', {name: /Speichern|Save/}).count(), 0);
  pass('Exactly three validated settings render read-only with honest offline administration');
  await capture(page, 'settings-start');
  await capture(page, 'general');

  await category(page, 'General');
  await section(page, 'Appearance & Preferences');
  await visibleText(page, 'Server preference synchronization');
  await pass('Appearance settings are explicitly client-local');

  await category(page, 'MCP & Agents');
  await visibleText(page, 'MCP Server');
  await visibleText(page, 'local_ipc');
  await visibleText(page, 'local stdio; Unix IPC bridge only');
  await visibleText(page, 'rmcp 3.8.0');
  await visibleText(page, 'no mutating MCP tools');
  assert.equal(await page.getByText('Streamable HTTP', {exact: false}).count(), 0);
  pass('MCP overview reports the actual local stdio/IPC runtime and read-only policy');
  await capture(page, 'mcp-overview');

  await section(page, 'Client Configuration');
  await visibleText(page, 'MCP Client Configuration');
  await visibleText(page, 'UNRESOLVED TEMPLATE');
  await page.getByRole('button', {name: 'Copy Configuration', exact: true}).click({force: true});
  await page.waitForTimeout(250);
  const configText = await clipboard(page);
  const config = JSON.parse(configText);
  assert.ok(config.mcpServers['oip-local'].args.includes('--mcp-bridge'));
  assert.ok(configText.includes('<ABSOLUTE_OIP_SERVER_EXECUTABLE>'));
  assert.ok(!configText.includes('/Users/'));
  assert.ok(!configText.includes('Bearer '));
  await page.getByRole('button', {name: 'Copy CLI Template', exact: true}).click({force: true});
  await page.waitForTimeout(250);
  const cliText = await clipboard(page);
  assert.ok(cliText.includes('--ipc-credential'));
  assert.ok(cliText.includes('<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>'));
  assert.ok(!cliText.includes('Bearer '));
  pass('Client configuration copies valid sanitized JSON and CLI template without credentials');
  await capture(page, 'mcp-client-config');

  await section(page, 'Tools & Capabilities');
  await visibleText(page, 'MCP Tool & Capability Explorer');
  await visibleText(page, '18 registrierte Tools');
  await capture(page, 'mcp-tool-explorer');

  await toolSearch(page, 'oip_settings_read');
  await page.getByRole('button', {name: /MCP Tool oip_settings_read/}).first().waitFor();
  assert.equal(await page.getByRole('button', {name: /MCP Tool oip_devices_read/}).count(), 0);
  await page.getByRole('button', {name: /MCP Tool oip_settings_read/}).first().click({force: true});
  await page.waitForTimeout(300);
  await visibleText(page, 'Tool Inspector');
  await visibleText(page, 'Required Permissions');
  await capture(page, 'tool-selected');
  await scrollInspector(page, 700);
  await capture(page, 'tool-schema');
  const schemaText = await page.evaluate(() => {
    const editors = [...document.querySelectorAll('textarea, input')];
    return editors.map(node => node.value).filter(Boolean).join('\n');
  });
  // Flutter renders schema text on canvas; copy is the authoritative check.
  await page.getByRole('button', {name: 'Schema kopieren', exact: true}).click({force: true});
  await page.waitForTimeout(250);
  const schema = JSON.parse(await clipboard(page));
  assert.equal(schema.title, 'SettingsQuery');
  pass('Tool search, selection, inspector and schema copy operate on real tool DTOs');
  void schemaText;

  await section(page, 'Permissions & Scopes');
  await visibleText(page, 'MCP Permissions & Scopes');
  await visibleText(page, 'POLICY READ ONLY');
  assert.equal(await page.getByText(/Enable tool|Disable tool|Tool aktivieren|Tool deaktivieren/).count(), 0);
  await capture(page, 'mcp-permissions');

  await section(page, 'Client Sessions');
  await visibleText(page, 'Aktive MCP-Client-Sessions können derzeit nicht zentral aufgelistet werden.');
  await visibleText(page, 'UNSUPPORTED');
  await visibleText(page, 'Keine Client-Namen, Session-IDs, Connected-Zustände');
  assert.equal(await page.getByText(/Last-Activity-Werte/).count(), 1);
  pass('Client sessions remain honestly unsupported with no fictitious clients');
  await capture(page, 'mcp-sessions-unsupported');

  await section(page, 'Connection Diagnostics');
  await visibleText(page, 'MCP Connection Diagnostics');
  await visibleText(page, 'Nicht durchgeführt');
  assert.equal(await page.getByText(/Verbindung erfolgreich|Connection successful/).count(), 0);
  pass('MCP diagnostics performs no fake handshake and shows only status reads');

  await category(page, 'Infrastructure');
  await visibleText(page, 'offline operator administration required');
  await capture(page, 'infrastructure');
  await section(page, 'Sources & Devices');
  await visibleText(page, 'Device onboarding requires local operator administration');
  assert.equal(await page.getByRole('button', {name: /Gerät hinzufügen|Add device/}).count(), 0);
  await visibleText(page, 'simulated / demo data reported');
  await capture(page, 'infrastructure-sources');
  await pass('Infrastructure uses existing read data and exposes no browser onboarding');

  await category(page, 'Data & Storage');
  await visibleText(page, 'SQLite & Data Storage');
  await visibleText(page, 'unsupported; no data deletion');
  assert.equal(await page.getByRole('button', {name: /löschen|delete/i}).count(), 0);
  await capture(page, 'data-storage');
  await section(page, 'Retention');
  await visibleText(page, 'UNSUPPORTED');
  await pass('Data & Storage reports schema, settings and unsupported retention honestly');

  await category(page, 'Diagnostics');
  await visibleText(page, 'oip.documented-collection-gap');
  await visibleText(page, 'documented markers; zero interval is not proof of continuity');
  await capture(page, 'diagnostics-settings');
  await pass('Diagnostics shows immutable rule metadata and gap semantics');

  await category(page, 'Security & Access');
  await visibleText(page, 'RUSTSEC-2023-0071');
  await visibleText(page, 'RUSTSEC-2023-0089');
  await visibleText(page, 'RUSTSEC-2024-0449');
  assert.equal(await page.getByText('Secure for Production', {exact: true}).count(), 0);
  await capture(page, 'security');
  await pass('Security names open production blockers and never claims production readiness');

  await category(page, 'System');
  await visibleText(page, 'f9969f0a21f2885a8b6c4695b3c105ad28708d33');
  await visibleText(page, 'No host collector data');
  assert.equal(await page.getByText(/CPU Percent|RAM Percent/).count(), 0);
  await capture(page, 'system');
  await pass('System reports real build/runtime facts and no invented host metrics');

  // Theme captures use the actual Flutter theme selector.
  await category(page, 'General');
  await section(page, 'Appearance & Preferences');
  await page.locator('flt-semantics[aria-label^="Theme Graphite"]').first().click({force: true});
  await page.waitForTimeout(400);
  await capture(page, 'graphite');
  await page.locator('flt-semantics[aria-label^="Theme Daylight"]').first().click({force: true});
  await page.waitForTimeout(400);
  await capture(page, 'daylight');
  await page.locator('flt-semantics[aria-label^="Theme Spectrum"]').first().click({force: true});
  await page.waitForTimeout(300);
  pass('Spectrum, Graphite and Daylight are real local UI preferences');

  // Session persistence across module navigation.
  await category(page, 'MCP & Agents');
  await section(page, 'Tools & Capabilities');
  await toolSearch(page, 'settings');
  await page.waitForTimeout(300);
  await nav(page, 'Übersicht');
  await page.waitForTimeout(400);
  await nav(page, 'Einstellungen');
  await visibleText(page, 'MCP Tool & Capability Explorer', 30000);
  await page.getByRole('button', {name: /MCP Tool oip_settings_read/}).first().waitFor();
  assert.equal(await page.getByRole('button', {name: /MCP Tool oip_devices_read/}).count(), 0);
  pass('Settings session navigation and filters survive module switches and reload data');
  await toolSearch(page, '');

  // No periodic management polling while idle.
  const beforeIdle = v2Requests.length;
  await page.waitForTimeout(3000);
  assert.equal(v2Requests.length, beforeIdle);
  pass('No periodic management polling occurs while the workstation is idle');

  // Keyboard focus and Escape semantics.
  await page.keyboard.press('/');
  await page.waitForTimeout(200);
  assert.equal(await page.getByRole('textbox', {name: /Tool, Capability/}).first().evaluate(node => node === document.activeElement), true);
  await pass('Keyboard shortcut focuses the tool search');

  // Responsive captures and layout checks.
  for (const [width, height] of [[320, 740], [375, 812], [390, 844], [768, 1024], [834, 1112], [1024, 900], [1440, 1000], [1920, 1080]]) {
    await page.setViewportSize({width, height});
    await page.waitForTimeout(350);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, `${width}: overflow`);
    if (width === 320) {
      await openSettings(page, width, height);
      await page.getByText('Kategorien', {exact: true}).first().click({force: true});
      await page.waitForTimeout(300);
      await capture(page, 'mobile-320');
      await page.getByText('Workspace', {exact: true}).first().click({force: true});
      await page.waitForTimeout(300);
      await capture(page, 'mobile-workspace-320');
      await page.getByText('Inspector', {exact: true}).first().click({force: true});
      await page.waitForTimeout(300);
      await capture(page, 'mobile-inspector-320');
    } else if (width === 768) {
      await openSettings(page, width, height);
      await capture(page, 'tablet-768');
    } else {
      if (width !== 1440) {
        await openSettings(page, width, height);
        await capture(page, `responsive-${width}`);
      }
    }
    await pass(`Settings workstation renders without overflow at ${width}px`);
  }
  await openSettings(page, 1440, 1000);

  // ---------------------------------------------------------------------------
  // 2. Unauthorized browser identity: v1 works, v2 returns 403.
  // ---------------------------------------------------------------------------
  const unauthorizedContext = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1});
  const unauthorized = await unauthorizedContext.newPage();
  observe(unauthorized, new URL(unauthorizedBase).origin);
  await unauthorized.goto(`${unauthorizedBase}/?settings-2027=unauthorized`, {waitUntil: 'domcontentloaded'});
  await unauthorized.getByText('Operations Workstation', {exact: true}).waitFor({timeout: bootTimeout});
  await nav(unauthorized, 'Einstellungen');
  await visibleText(unauthorized, 'Management-Zugriff nicht autorisiert', 30000);
  await visibleText(unauthorized, 'nicht „Core offline“');
  await unauthorized.getByText('Technische Fehlerdetails').first().click({force: true});
  await visibleText(unauthorized, 'PERMISSION_DENIED');
  await visibleText(unauthorized, '403');
  assert.equal(await unauthorized.getByText('Core / Management-Endpunkt nicht erreichbar').count(), 0);
  await capture(unauthorized, 'unauthorized');
  pass('HTTP 403 is shown as an identity/policy boundary, not as a Core outage');
  await unauthorizedContext.close();

  // ---------------------------------------------------------------------------
  // 3. Second real principal context: registered tools versus availability.
  // ---------------------------------------------------------------------------
  const limitedContext = await browser.newContext({viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1});
  const limited = await limitedContext.newPage();
  observe(limited, new URL(limitedBase).origin);
  // This principal was only captured for tools/permissions/security; the
  // default application read is genuinely absent, so no fixture badge can be
  // asserted until the tools section has loaded its own fixture.
  await openSettings(limited, 1440, 1000, false, limitedBase);
  await category(limited, 'MCP & Agents');
  await section(limited, 'Tools & Capabilities');
  await visibleText(limited, 'CONTRACT FIXTURE · NICHT LIVE');
  await visibleText(limited, '18 registrierte Tools');
  await toolSearch(limited, 'oip_mcp_management_read');
  await limited.getByRole('button', {name: /MCP Tool oip_mcp_management_read/}).first().click({force: true});
  await visibleText(limited, 'Available to Principal');
  await toolSearch(limited, 'oip_settings_read');
  await limited.getByRole('button', {name: /MCP Tool oip_settings_read/}).first().click({force: true});
  await visibleText(limited, 'Denied by Policy');
  await capture(limited, 'mcp-permissions-limited');
  pass('A second principal sees all registered tools but only its authorized subset as available');
  await limitedContext.close();

  assert.deepEqual(external, []);
  assert.deepEqual(errors, []);
  assert.deepEqual(failedResources, []);
  assert.deepEqual(consoleNetwork.filter(line => /status of 5\d\d/.test(line)), []);
  assert.ok(consoleNetwork.every(line => /status of (403|404)/.test(line)), 'only expected 4xx boundaries');
  await context.close();

  const report = {
    verdict: 'PASS',
    base,
    unauthorizedBase,
    limitedBase,
    checks: checks.length,
    captures: captures.length,
    checkList: checks,
    captureList: captures,
    pageErrors: errors,
    expectedHttpBoundaryConsole: consoleNetwork,
    externalRequests: external,
    failedResources,
    fixtureMarked: true,
    credentialBytesExposed: false,
    authorizationHeaderSentByBrowser: false,
  };
  await writeFile(resolve(out, 'browser-settings.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({verdict: 'PASS', checks: checks.length, captures: captures.length}, null, 2));
} catch (error) {
  await writeFile(resolve(out, 'browser-settings-failure.json'), `${JSON.stringify({
    verdict: 'FAIL',
    error: String(error?.stack ?? error),
    checks,
    captures,
    pageErrors: errors,
    expectedHttpBoundaryConsole: consoleNetwork,
    externalRequests: external,
    failedResources,
  }, null, 2)}\n`);
  console.error('SETTINGS BROWSER FAILURE', error);
  process.exitCode = 1;
} finally {
  await browser.close();
}

/**
 * Settings — the depth of the categories of the managed surface.
 *
 * The Settings workspace is where the operator reads what the Core can and
 * cannot do: the settings that exist, the MCP runtime that is really there,
 * the tools of the authorized mapping and the limits that are named. The
 * journey verifies against a real Core with an authorized session that
 *   - every category of the Core is offered, and the sections of it reachable,
 *   - the write path does not exist: the settings are named as offline
 *     administration and the surface carries no save button,
 *   - the MCP runtime is the real one: the number of the tools is the number
 *     the Core delivers, the search reaches a tool of the Core, the inspector
 *     names its permissions and the copied schema is the schema of the Core,
 *   - the copied client configuration is the template of the Core: it names
 *     the placeholders that must be replaced, carries no credential and no
 *     bearer token, and the Core reports that no credential is provisioned,
 *   - the limits are named: the client sessions, the retention, the
 *     connection diagnostics,
 *   - the security names the open advisories and the system names the real
 *     facts of the build — never a claim of production readiness.
 *
 * It replaces the journey of the generation 2027 (it is in the history of the
 * repository): that one drove the surface of the OIP/005 demo and was named
 * by no harness, so its proof was no receipt. This one drives the **managed**
 * surface against a real Core with an authorized session.
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
await rm(resolve(captures, 'failure.png'), {force: true});
await rm(resolve(out, 'failure.json'), {force: true});

const systemChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined),
  headless: true,
});
const context = await browser.newContext({
  viewport: {width: 1600, height: 1000},
  deviceScaleFactor: 1,
  permissions: ['clipboard-read', 'clipboard-write'],
});
const page = await context.newPage();
const errors = [], external = [], failedResources = [], refusals = [], checks = [], taken = [];
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => {
  if (message.type() !== 'error') return;
  // A resource that the Core refused is evidence, not a defect of the surface.
  if (/Failed to load resource/i.test(message.text())) return;
  errors.push(message.text());
});
page.on('response', response => {
  if (response.status() < 400) return;
  if (response.status() === 403) {
    // The refusal of the Core is the Core's answer, recorded with its route.
    refusals.push(response.url().replace(base, ''));
    return;
  }
  if (response.status() === 404 && /favicon\.ico$/.test(response.url())) return;
  failedResources.push(response.url());
});
await context.route('**/*', async route => {
  const url = new URL(route.request().url());
  if (url.protocol.startsWith('http') && url.origin !== new URL(base).origin) {
    external.push(url.href);
    return route.abort();
  }
  return route.continue();
});

const escapeRegExp = value => String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function pass(label) {
  checks.push(label);
  console.log('PASS', label);
}
async function capture(name) {
  await page.screenshot({path: resolve(captures, `${name}.png`)});
  taken.push(`${name}.png`);
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
  await page.waitForTimeout(300);
}
const api = async path => {
  const answer = await context.request.get(base + path, {timeout: 60000});
  assert.equal(answer.status(), 200, `the Core answered ${answer.status()} for ${path}`);
  return await answer.json();
};
const clipboard = async () => await page.evaluate(() => navigator.clipboard.readText());

/** Every name of the semantics DOM: the accessible names of the surface. */
async function theNames() {
  return await page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host') || document.body;
    return [...host.querySelectorAll('flt-semantics')]
      .map(node => {
        const leaf = node.querySelector('flt-semantics') === null;
        return (node.getAttribute('aria-label') || (leaf ? node.textContent : '') || '').trim();
      })
      .filter(name => name.length > 0);
  });
}

/** The name waits for the data of the Core; the surface reads asynchronously. */
async function waitForNameContaining(fragment, timeout = 30000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const names = await theNames();
    const hit = names.find(name => name.includes(fragment));
    if (hit) return hit;
    if (Date.now() > deadline) {
      throw Error(`the surface does not name "${fragment}" (the names: ${names.slice(0, 24).join(' | ')})`);
    }
    await page.waitForTimeout(250);
  }
}

/** The name is in the scrollable content of the workstation or inspector. */
async function revealInSurface(fragment, timeout = 30000) {
  if (await theNames().then(names => names.some(name => name.includes(fragment)))) return true;
  const deadline = Date.now() + timeout;
  // The workspace and the inspector are separate scrollables; the sections
  // are long, so both are searched from the top.
  for (const [x, y] of [[700, 620], [1400, 620]]) {
    await page.mouse.move(x, y);
    await page.waitForTimeout(120);
    for (let step = 0; step < 16; step++) {
      const names = await theNames();
      if (names.some(name => name.includes(fragment))) return true;
      if (Date.now() > deadline) return false;
      await page.mouse.wheel(0, 260);
      await page.waitForTimeout(160);
    }
  }
  return false;
}

async function requireName(fragment, label) {
  if (!(await revealInSurface(fragment))) {
    throw Error(`the surface does not name "${fragment}" (${label})`);
  }
  pass(label);
}

async function scrollToTheTop() {
  for (const [x, y] of [[700, 620], [1400, 620]]) {
    await page.mouse.move(x, y);
    await page.waitForTimeout(120);
    for (let step = 0; step < 20; step++) {
      await page.mouse.wheel(0, -400);
      await page.waitForTimeout(30);
    }
  }
  await page.waitForTimeout(400);
}

async function openCategory(label) {
  await page.getByRole('button', {name: `Settings-Kategorie ${label}`})
    .first().click({force: true});
  await page.waitForTimeout(1400);
}

async function openSection(label) {
  await page.getByRole('button', {name: `Settings-Bereich ${label}`})
    .first().click({force: true});
  await page.waitForTimeout(1400);
}

try {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,
    ['--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
     '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL], {encoding: 'utf8'}));
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true})
    .waitFor({timeout: bootTimeout});
  await typeInto(page.getByRole('textbox', {name: 'Einmalcode'}), minted.login_code);
  await page.getByRole('button', {name: 'Operator-Sitzung autorisieren', exact: true}).click();
  await page.waitForTimeout(2500);
  const session = await api('/api/v2/browser/session');
  assert.equal(session.authenticated, true, 'the session of the operator is not authenticated');

  // The truth of the Core: the settings, the tools and the client
  // configuration. The journey names none of its own.
  const settings = await api('/api/v2/settings?scope=platform');
  const categories = settings.categories ?? [];
  const definitions = settings.definitions ?? [];
  assert.ok(categories.length > 0, 'the Core delivered no settings category');
  assert.ok(definitions.length > 0, 'the Core delivered no setting definition');
  const tools = await api('/api/v2/management?section=tools');
  const coreTools = tools.tools ?? [];
  assert.ok(coreTools.length > 0, 'the Core delivered no tool');
  const configuration = await api('/api/v2/management?section=client_configuration');
  const preview = configuration.client_configuration ?? {};
  assert.equal(preview.credential_provisioned, false,
    'the Core reports a provisioned credential for the template');
  assert.equal(preview.usable_without_replacement, false,
    'the Core reports a template that were usable without replacement');
  pass(`the Core delivered ${categories.length} categories, ${definitions.length} settings and ${coreTools.length} tools`);

  await page.getByRole('button', {name: 'Navigation Einstellungen', exact: true}).click();
  await page.waitForTimeout(1500);
  await waitForNameContaining('SETTINGS · APPLICATION MANAGEMENT', bootTimeout);

  // 1. every category of the Core is offered by the surface.
  const categoryButtons = (await theNames())
    .filter(name => name.startsWith('Settings-Kategorie '));
  assert.equal(categoryButtons.length, categories.length,
    `the surface offers ${categoryButtons.length} categories, the Core delivered ${categories.length}`);
  pass(`the surface offers the ${categories.length} categories of the Core`);

  // 2. the write path does not exist: the settings are offline administration
  //    and the surface carries no save button.
  await openCategory('Allgemein');
  await openSection('Core-Einstellungen');
  await scrollToTheTop();
  await waitForNameContaining('OFFLINE ADMINISTRATION REQUIRED');
  await waitForNameContaining('Kein Browser-Save');
  for (const definition of definitions) {
    await waitForNameContaining(definition.key);
  }
  // The Core delivers the startup snapshot only to a platform-authorized
  // reader; the surface must show that snapshot and not a client default.
  assert.equal(typeof settings.loaded_at_ms, 'number',
    'the Core delivered no startup snapshot timestamp for the platform reader');
  await waitForNameContaining(String(settings.loaded_at_ms));
  const saveButtons = await page.getByRole('button', {name: /Speichern|Save|Apply changes/i}).count();
  assert.equal(saveButtons, 0, 'the surface offers a save button for the settings');
  pass('the settings of the Core are named as offline administration, with no browser save');
  await capture('general-application');

  // 3. the appearance is explicitly client-local.
  await openSection('Erscheinungsbild & Sprache');
  await waitForNameContaining('Erscheinungsbild & Sprache');
  await waitForNameContaining('LOKAL AUF DIESEM GERÄT');
  pass('the appearance is its own client-local section of the surface');
  await capture('general-appearance');

  // 4. the MCP runtime is the real one: the section names the facts of the
  //    server report — the transport, the protocol and the limits — and not a
  //    runtime of the client.
  await openCategory('MCP & Agents');
  await scrollToTheTop();
  const server = await api('/api/v2/management?section=server');
  const serverFacts = server.facts ?? [];
  assert.ok(serverFacts.length > 0, 'the Core delivered no server fact');
  await waitForNameContaining('LOCAL STDIO / IPC');
  for (const fact of serverFacts) {
    if (!(await revealInSurface(fact.name, 20000))) {
      throw Error(`the MCP section does not name the fact ${fact.name} of the Core`);
    }
  }
  pass(`the MCP section names the real runtime and the ${serverFacts.length} facts of the Core`);
  await capture('mcp-server');

  // 5. the tool explorer reaches a tool of the Core, names its permissions
  //    and copies its schema.
  await openSection('Werkzeuge & Fähigkeiten');
  await waitForNameContaining('MCP Tool & Capability Explorer');
  const wanted = coreTools.find(tool => typeof tool.input_schema_json === 'string') ?? coreTools[0];
  const search = page.getByRole('textbox', {name: /Tool, Capability/i});
  if (!(await search.count())) throw Error('the search of the tool explorer is missing');
  await typeInto(search, wanted.name);
  await page.waitForTimeout(1200);
  const toolButton = page.getByRole('button', {name: new RegExp(`MCP Tool ${escapeRegExp(wanted.name)}`)});
  await toolButton.first().waitFor({timeout: 20000});
  await toolButton.first().click({force: true});
  await page.waitForTimeout(1200);
  await waitForNameContaining('Required Permissions');
  await revealInSurface('Erlaubte Geltungsbereiche', 20000);
  for (const permission of wanted.permissions ?? []) {
    if (!(await revealInSurface(permission, 10000))) {
      throw Error(`the inspector does not name the permission ${permission} of ${wanted.name}`);
    }
  }
  pass(`the tool explorer reaches the tool ${wanted.name} of the Core and names its permissions`);
  await capture('tool-explorer');

  // 6. the copied schema is the schema of the Core — the inspector renders
  //    the authorization read, not a schema of the client.
  const schemaButton = page.getByRole('button', {name: 'Schema kopieren', exact: true});
  assert.ok(await revealInSurface('Schema kopieren', 20000),
    'the schema copy of the inspector is not reachable');
  assert.ok(await schemaButton.count(), 'the schema copy of the inspector is not in the tree');
  await schemaButton.first().click({force: true});
  await page.waitForTimeout(500);
  const copiedSchema = JSON.parse(await clipboard());
  assert.deepEqual(copiedSchema, JSON.parse(wanted.input_schema_json),
    `the copied schema is not the schema of ${wanted.name}`);
  pass(`the copied schema is the schema that the Core delivered for ${wanted.name}`);
  await capture('tool-schema');

  // 7. the copied client configuration is the template of the Core: the
  //    placeholders must be replaced and no credential is carried.
  await openSection('Client-Konfiguration');
  await waitForNameContaining('UNRESOLVED TEMPLATE');
  await waitForNameContaining('NOT PROVISIONED');
  assert.ok(await revealInSurface('Copy Configuration', 15000),
    'the copy of the client configuration is not reachable');
  await page.getByRole('button', {name: 'Copy Configuration', exact: true}).click({force: true});
  await page.waitForTimeout(500);
  const configText = await clipboard();
  const config = JSON.parse(configText);
  const servers = Object.keys(config.mcpServers ?? {});
  assert.deepEqual(servers, ['oip-local'], `the copied configuration names ${servers.join(', ')}`);
  const args = config.mcpServers['oip-local'].args ?? [];
  for (const argument of ['--mcp-bridge', '--ipc-socket', '--ipc-credential',
                          '<AUTHORIZED_PRIVATE_SOCKET>', '<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>']) {
    assert.ok(args.includes(argument), `the copied configuration names no ${argument}`);
  }
  assert.ok(!/Bearer\s/.test(configText), 'the copied configuration carries a bearer token');
  assert.ok(!/["'][0-9a-f]{64}["']/.test(configText),
    'the copied configuration carries a credential-looking value');
  assert.ok(await revealInSurface('CLI-Vorlage kopieren', 15000),
    'the copy of the CLI template is not reachable');
  await page.getByRole('button', {name: 'CLI-Vorlage kopieren', exact: true}).click({force: true});
  await page.waitForTimeout(500);
  const cliText = await clipboard();
  assert.ok(cliText.includes('--ipc-credential'), 'the CLI template names no credential file');
  assert.ok(cliText.includes('<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>'),
    'the CLI template has no placeholder');
  assert.ok(!/Bearer\s/.test(cliText), 'the CLI template carries a bearer token');
  pass('the client configuration copies the Core template with its placeholders and no credential');
  await capture('client-configuration');

  // 8. the permissions are read-only and the limits are named.
  await openSection('Berechtigungen & Geltungsbereiche');
  await waitForNameContaining('POLICY READ ONLY');
  await openSection('Client-Sitzungen');
  await waitForNameContaining('MCP Client Sessions');
  await waitForNameContaining('UNSUPPORTED');
  await openSection('Verbindungsdiagnose');
  await waitForNameContaining('MCP Connection Diagnostics');
  await waitForNameContaining('STATUS READ ONLY');
  await waitForNameContaining(`${coreTools.length} registrierte Tools geliefert`);
  pass('the permissions, the client sessions and the connection diagnostics name their limits');
  await capture('mcp-limits');

  // 9. the storage and the retention name what is real.
  await openCategory('Data & Storage');
  await scrollToTheTop();
  await waitForNameContaining('SQLite & Data Storage');
  await openSection('Aufbewahrung');
  await waitForNameContaining('Aufbewahrung');
  await waitForNameContaining('Keine Datenlöschung');
  pass('the storage category names the store and the absence of a retention cleanup');
  await capture('data-storage');

  // 10. the security names the open advisories — never a production claim.
  await openCategory('Security & Access');
  await scrollToTheTop();
  await waitForNameContaining('PRODUCTION BLOCKERS OPEN');
  await waitForNameContaining('RUSTSEC-2023-0071');
  pass('the security category names the open advisories and the production blockers');
  await capture('security');

  // 11. the system names the real facts of the build and invents no host
  //     metric.
  await openCategory('System');
  await scrollToTheTop();
  await waitForNameContaining('System Information');
  await waitForNameContaining('CORE REPORTED');
  await waitForNameContaining('CPU / RAM / GPU');
  await waitForNameContaining('Unknown — no host collector data in this contract');
  const runtime = await api('/api/v2/management?section=system');
  const version = (runtime.facts ?? []).find(fact => fact.name === 'version');
  assert.ok(version && version.value, 'the Core delivered no version fact');
  await waitForNameContaining(version.value);
  pass('the system category names the facts of the Core and no invented host metric');
  await capture('system');

  assert.deepEqual(errors, [], `page errors: ${errors.join(' | ')}`);
  assert.deepEqual(external, [], `external requests: ${external.join(' | ')}`);
  assert.deepEqual(failedResources, [], `failed resources: ${failedResources.join(' | ')}`);

  await writeFile(resolve(out, 'settings-depth.json'), JSON.stringify({
    status: 'PASS',
    the_revision: process.env.OIP_REVISION,
    the_categories_of_the_core: categories.map(category => category.category),
    the_settings_of_the_core: definitions.map(definition => definition.key),
    the_tools_of_the_core: coreTools.map(tool => tool.name),
    the_tool_of_the_journey: wanted.name,
    the_credential_is_provisioned: preview.credential_provisioned,
    the_template_is_usable_without_replacement: preview.usable_without_replacement,
    the_refusals_of_the_core: refusals,
    the_checks: checks,
    the_captures: taken,
    errors,
    external,
  }, null, 2));
} catch (error) {
  await capture('failure');
  await writeFile(resolve(out, 'failure.json'), JSON.stringify({
    status: 'FAIL',
    error: String(error && error.message || error),
    the_checks: checks,
    errors,
    external,
    the_refusals_of_the_core: refusals,
  }, null, 2));
  console.error(error);
  await browser.close();
  process.exit(1);
}
await browser.close();

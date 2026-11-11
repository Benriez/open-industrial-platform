// The browser receipt of the functional depth of the six workstations (G8).
//
// The canonical gate proves that the six workstations of the approved shell
// render and that they carry no legacy marker. This receipt proves the next
// step: every workstation shows **real** data of the authorized Core, and
// nothing of the other organization.
//
// The receipt proves that
//
//   * the overview shows the authorized hierarchy and its counts;
//   * the device workspace shows the real device of the selected source;
//   * the network view shows the authorized placement of the scope;
//   * the OPC-UA browser shows the real nodes of the selected source;
//   * the diagnostics view shows the real events of the authorized sources;
//   * the settings view shows the real settings of the Core;
//   * no identifier of the other organization appears in any of them.
//
// Usage: node browser_workstation_data.mjs <baseUrl> <outDir> [loginCode]

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_workstation_data.mjs <baseUrl> <outDir> [loginCode]');
  process.exit(2);
}
if (!code && process.env.OIP_IPC_SOCKET && process.env.OIP_BROWSER_CREDENTIAL) {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN || 'target/release/oip-server', [
    '--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
    '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL,
  ], { encoding: 'utf8' }));
  code = minted.login_code;
}
fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const errors = [];
const check = (name, ok, detail) => {
  findings.push({
    check: name,
    ok: !!ok,
    // The message describes the failure of the check. A check that
    // passed carries it as well, so a reader does not mistake it for
    // an observation of the surface.
    the_detail: detail ?? null,
  });
  if (!ok) throw new Error(`${name}: ${detail ?? 'failed'}`);
};

const WORKSTATIONS = [
  { slug: 'overview', name: 'Übersicht' },
  { slug: 'devices', name: 'Geräte & Dienste' },
  { slug: 'network', name: 'Netzwerk & VPN' },
  { slug: 'opcua', name: 'OPC-UA-Browser' },
  { slug: 'diagnostics', name: 'Diagnose & Ereignisse' },
  { slug: 'settings', name: 'Einstellungen' },
];
// The identifiers of the other organization must never appear.
const FOREIGN = ['device-d', 'source-d', 'Organization B', 'Infrastructure B1', 'Site B1'];

const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
page.on('pageerror', (e) => errors.push('pageerror: ' + e.message.slice(0, 200)));
page.on('console', (m) => {
  if (m.type() !== 'error') return;
  const text = m.text();
  if (/Failed to load resource/i.test(text) || /\b403\b/.test(text)) return;
  errors.push('console: ' + text.slice(0, 200));
});

// A control of the Flutter view is activated with a real mouse event on its
// painted position.
const clickText = async (text) => {
  const handles = await page.locator('flt-semantics').filter({ hasText: text }).elementHandles();
  let target = null;
  let smallest = Infinity;
  for (const handle of handles) {
    const box = await handle.boundingBox();
    if (!box) continue;
    const area = box.width * box.height;
    if (area < smallest) {
      smallest = area;
      target = box;
    }
  }
  if (!target) throw new Error(`the control "${text}" has no geometry`);
  await page.mouse.click(target.x + Math.min(target.width / 2, 60), target.y + target.height / 2);
  await page.waitForTimeout(1500);
};

const labels = async () => await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    const label = el.getAttribute('aria-label');
    if (label) out.push(label);
    for (const child of el.childNodes) {
      if (child.nodeType === 3) out.push(child.textContent || '');
    }
  });
  return out.join('\n');
});

// The whole painted surface of the workstation: the semantics of the Flutter
// view carry what is painted, so the page is read while it is scrolled.
const readSurface = async () => {
  const lines = new Set();
  const collect = async () => {
    const text = await labels();
    for (const line of text.split('\n')) {
      const trimmed = line.trim();
      if (trimmed) lines.add(trimmed);
    }
  };
  await collect();
  await page.mouse.move(700, 600);
  for (let step = 0; step < 14; step++) {
    await page.mouse.wheel(0, 700);
    await page.waitForTimeout(180);
    await collect();
  }
  await page.mouse.wheel(0, -20000);
  await page.waitForTimeout(600);
  return [...lines].join('\n');
};

await page.goto(base, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !!document.querySelector('flutter-view'), null, { timeout: 300000 });
await page.waitForTimeout(6000);

if (code) {
  const login = await page.evaluate(async (c) => {
    const r = await fetch('/api/v2/browser/login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: c }),
    });
    return { status: r.status };
  }, code);
  check('browser-login accepted', login.status === 200, JSON.stringify(login));
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const out = [];
    document.querySelectorAll('flt-semantics').forEach((el) => {
      for (const child of el.childNodes) {
        if (child.nodeType === 3) out.push(child.textContent || '');
      }
    });
    return out.join('\n').includes('Infrastructure Context:');
  }, null, { timeout: 300000 });
}

// The operator selects the source of the demonstration in the global
// Infrastructure Context: every workstation then works on the same
// authorized scope.
await page.getByRole('button', { name: 'Navigation Übersicht' }).click({ force: true });
await page.waitForTimeout(2500);
await page.getByRole('button', { name: /Infrastructure Context:/ }).first()
  .waitFor({ state: 'attached', timeout: 60000 });
await clickText('Infrastructure Context:');
await page.waitForTimeout(2000);
const sourceOption = await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    const text = (el.textContent || '').trim();
    if (/source-a/.test(text) && text.length < 300) out.push(text);
  });
  return out;
});
check('the context offers the source of the scope', sourceOption.length > 0,
  sourceOption.join(' | ').slice(0, 200));
await clickText(sourceOption[0]);
await page.waitForTimeout(3000);
const scopeLabel = await labels();
check('the scope of the operator is the selected source',
  /source-a/.test(scopeLabel), 'the selected source is not the scope');
const FOREIGN_SCOPE = ['device-d', 'source-d', 'Organization B', 'Infrastructure B1', 'Site B1'];

const surfaces = {};
for (const station of WORKSTATIONS) {
  await page.getByRole('button', { name: `Navigation ${station.name}` }).click({ force: true });
  await page.waitForTimeout(3000);
  if (station.slug === 'settings') {
    // The section of the settings that reads the setting in the scope of the
    // selected source: the application section reads the platform scope,
    // which this principal is not allowed to read.
    await clickText('Diagnostics');
    await page.waitForTimeout(2500);
    await clickText('History Limits');
    await page.waitForTimeout(3000);
  }
  // The nodes of the source arrive from the Core: the gate waits for them
  // instead of reading a surface that may still be empty on a loaded
  // machine. The check below then reports what the surface really carries.
  if (station.slug === 'opcua') {
    await page.waitForFunction(
      () => /bulk\.|motor_running|alarm_active|operating_mode|units_produced|temperature/.test(document.body.innerText),
      null, { timeout: 45000 }).catch(() => {});
  }
  const surface = await readSurface();
  surfaces[station.slug] = surface;
  await page.screenshot({ path: `${outDir}/workstation-${station.slug}.png` });
  const foreign = FOREIGN_SCOPE.filter((marker) => surface.includes(marker));
  check(`${station.slug}: no identifier of the other organization`,
    foreign.length === 0, foreign.join(' | '));
}

// The real data of the Core in every workstation.
check('overview: the authorized hierarchy is shown',
  /Organization A/.test(surfaces.overview) && /Infrastructure A1|Infrastructure A2/.test(surfaces.overview),
  'the hierarchy of the scope is missing');
check('overview: the counts of the scope are shown',
  /ORGANIZATIONS|ORGANIZATIONEN|SOURCES|SOURCES/.test(surfaces.overview) &&
  /DEVICES|GERÄTE/.test(surfaces.overview), 'the counts are missing');
check('devices: the device of the source is shown',
  /device-a/.test(surfaces.devices), 'the device of the source is missing');
check('network: the authorized placement is shown',
  /Organization A \/ Infrastructure A1/.test(surfaces.network) || /site-a1/.test(surfaces.network),
  'the placement of the scope is missing');
// The address space is shown with the names of the nodes of the collector.
check('opcua: the real nodes of the source are shown',
  /bulk\.|motor_running|alarm_active|operating_mode|units_produced|temperature/.test(surfaces.opcua),
  'no node of the source is shown');
check('diagnostics: the real events of the scope are shown',
  /source-a/.test(surfaces.diagnostics), 'no event of the scope is shown');
check('settings: the real settings of the Core are shown',
  /history_page_size|Default historical diagnostics page size/.test(surfaces.settings),
  'no setting of the Core is shown');

check('no browser JavaScript errors', errors.length === 0, errors.join(' | '));

const receipt = {
  schema: 'oip-workstation-data-v1',
  revision: process.env.OIP_REVISION || null,
  the_detail_is: 'the message that describes the failure of the check',
  scope: 'the functional depth of the six workstations against the real Core',
  base,
  selected_source: sourceOption[0] ?? null,
  surfaces: Object.fromEntries(Object.entries(surfaces).map(([key, value]) =>
    [key, { lines: value.split('\n').length }])),
  findings,
  errors,
};
fs.writeFileSync(`${outDir}/workstation-data.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({
  verdict: 'PASS',
  findings: findings.length,
  errors: errors.length,
  lines_per_workstation: receipt.surfaces,
}, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

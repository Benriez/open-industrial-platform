// The browser receipt of the honest connection states (G5, G6).
//
// The Core answers a state for a connection: verified without the
// monitoring, collecting, stale, unreachable, blocked by a changed host key.
// The surface must show **the truth about that state** — a blocked
// connection must never be shown as a connected one.
//
// This receipt proves it against the **real Core**: the journey reads the
// state of the Core over the authorized route and the word of the surface in
// the same moment, and it drives the Core through the states by what the
// operator does (the monitoring switch) and by what the **host** does (it
// disappears, it comes back and it comes back with another key).
//
// Usage: node browser_connection_states.mjs <baseUrl> <outDir> <deviceId>
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
const deviceId = process.argv[4] || process.env.OIP_DEVICE_ID || 'state-device';
const controlUrl = process.env.OIP_CONTROL_URL || '';
const expectedFingerprint = process.env.OIP_EXPECTED_FINGERPRINT || '';
let code = process.argv[5] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_connection_states.mjs <baseUrl> <outDir> <deviceId>');
  process.exit(2);
}
if (!code && process.env.OIP_IPC_SOCKET && process.env.OIP_BROWSER_CREDENTIAL) {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN || 'target/release/oip-server', [
    '--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
    '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL,
  ]).toString());
  code = minted.login_code;
}

// The word of the surface for every state of the Core. The word is the one
// of the approved surface; the state is the one of the Core.
const WORDS = {
  collecting: 'Collecting',
  ssh_verified: 'SSH Verified',
  stale: 'Stale',
  unreachable: 'Unreachable',
  host_key_changed: 'Host-Key geändert',
  host_key_unknown: 'Host-Key unbekannt',
  collector_configured: 'Überwachung konfiguriert',
  verification_failed: 'Verifikation fehlgeschlagen',
};

fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const errors = [];
const check = (name, ok, detail) => {
  findings.push({
    check: name,
    ok: !!ok,
    the_detail: detail ?? null,
  });
  if (!ok) throw new Error(`${name}: ${detail ?? 'failed'}`);
};

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);

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
  if (/Failed to load resource/i.test(text)) return;
  errors.push('console: ' + text.slice(0, 200));
});

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

// A control of the Flutter view is activated with a real mouse event on its
// painted position.
const clickAccessible = async (needle) => {
  const elements = await page.$$('flt-semantics');
  let target = null;
  let smallest = Infinity;
  for (const element of elements) {
    const label = (await element.getAttribute('aria-label')) || '';
    const own = (await element.evaluate((node) => (node.textContent || '').trim()));
    if (!label.includes(needle) && !own.includes(needle)) continue;
    if (label.length + own.length > 400) continue;
    const box = await element.boundingBox();
    if (!box) continue;
    const area = box.width * box.height;
    if (area < smallest) {
      smallest = area;
      target = element;
    }
  }
  if (!target) throw new Error(`the control "${needle}" has no geometry`);
  await target.scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  const box = await target.boundingBox();
  if (!box) throw new Error(`the control "${needle}" has no geometry after scrolling`);
  await page.mouse.click(box.x + Math.min(box.width / 2, 60), box.y + box.height / 2);
  await page.waitForTimeout(1500);
};

// The state of the Core over the authorized route.
const coreState = async () => await page.evaluate(async (id) => {
  const r = await fetch(`/api/v2/device-connections?device_id=${encodeURIComponent(id)}`,
    { headers: { 'Content-Type': 'application/json' } });
  const body = await r.json();
  return { 'the_status': r.status, 'the_state': (body.connection || {}).status };
}, deviceId);

// The word of the surface: the line of the state of the connection.
const surfaceState = async () => {
  const painted = await labels();
  for (const line of painted.split('\n')) {
    const trimmed = line.trim();
    for (const [state, word] of Object.entries(WORDS)) {
      if (trimmed.startsWith(word)) {
        return { 'the_state': state, 'the_line': trimmed };
      }
    }
  }
  return { 'the_state': null, 'the_line': null };
};

// Wait until the Core and the surface agree on a state.
const waitForState = async (state, timeout = 90000) => {
  const deadline = Date.now() + timeout;
  let last = null;
  while (Date.now() < deadline) {
    const core = await coreState();
    const surface = await surfaceState();
    last = { 'the_core': core, 'the_surface': surface };
    if (core.the_state === state && surface.the_state === state) {
      return { 'the_state': state, 'the_core': core, 'the_surface': surface,
               'the_line': surface.the_line };
    }
    await page.waitForTimeout(1000);
  }
  throw new Error(`the state ${state} was not reached: ${JSON.stringify(last)}`);
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
  await page.waitForTimeout(8000);
}

// The inventory of the devices is below the fold of the workstation: the
// surface is scrolled until the device is painted.
const scrollUntil = async (pattern, steps = 18) => {
  await page.mouse.move(700, 600);
  for (let step = 0; step < steps; step++) {
    const found = await page.evaluate((source) => {
      const expression = new RegExp(source);
      const out = [];
      document.querySelectorAll('flt-semantics').forEach((el) => {
        const label = el.getAttribute('aria-label');
        const text = (label || el.textContent || '').trim();
        if (expression.test(text) && text.length < 400) out.push(text);
      });
      return out;
    }, pattern.source);
    if (found.length > 0) return found;
    await page.mouse.wheel(0, 600);
    await page.waitForTimeout(220);
  }
  return [];
};

// The workspace of the devices and the panel of the device.
await page.getByRole('button', { name: 'Navigation Geräte & Dienste' }).click({ force: true });
await page.waitForTimeout(4000);
const deviceOption = await scrollUntil(new RegExp(`${deviceId}.*auswählen`));
check('the inventory of the scope lists the device', deviceOption.length > 0,
  deviceOption.join(' | ').slice(0, 200));
await clickAccessible(`${deviceId} auswählen`);
await page.waitForTimeout(2500);

const states = [];
const stateOfCore = async (name) => {
  const observed = await waitForState(name);
  states.push({ 'the_state': name, 'the_core': observed.the_core,
                'the_surface': observed.the_surface, 'the_line': observed.the_line });
  return observed;
};

// 1. the device is verified without the monitoring
const verified = await stateOfCore('ssh_verified');
check('the surface shows the verified state of the Core',
  verified.the_surface.the_line && verified.the_surface.the_line.startsWith('SSH Verified'),
  verified.the_surface.the_line);
if (expectedFingerprint) {
  const painted = await labels();
  check('the confirmed host key is shown', painted.includes(expectedFingerprint),
    'the fingerprint of the fixture is missing');
}

// 2. the operator enables the monitoring: the Core collects
await clickAccessible('Read-only Monitoring');
await page.waitForTimeout(2000);
const collecting = await stateOfCore('collecting');
check('the surface shows the collecting state of the Core',
  collecting.the_surface.the_line && collecting.the_surface.the_line.startsWith('Collecting'),
  collecting.the_surface.the_line);

// 3. the host disappears: the Core answers `unreachable`
if (controlUrl) {
  const stopped = await page.evaluate(async (url) => {
    const r = await fetch(`${url}/stop`, { method: 'POST' });
    return { status: r.status, body: await r.json() };
  }, controlUrl);
  check('the host of the rehearsal is stopped', stopped.status === 200, JSON.stringify(stopped));
}
const unreachable = await stateOfCore('unreachable');
check('the surface shows the unreachable state of the Core',
  unreachable.the_surface.the_line && unreachable.the_surface.the_line.startsWith('Unreachable'),
  unreachable.the_surface.the_line);

// 4. the host comes back: the Core collects again — the recovery
if (controlUrl) {
  const started = await page.evaluate(async (url) => {
    const r = await fetch(`${url}/start`, { method: 'POST' });
    return { status: r.status, body: await r.json() };
  }, controlUrl);
  check('the host of the rehearsal runs again', started.status === 200, JSON.stringify(started));
}
const recovered = await stateOfCore('collecting');
check('the surface shows the recovery of the Core',
  recovered.the_surface.the_line && recovered.the_surface.the_line.startsWith('Collecting'),
  recovered.the_surface.the_line);

// 5. the host comes back with another key: the Core blocks the connection
if (controlUrl) {
  const rotated = await page.evaluate(async (url) => {
    const r = await fetch(`${url}/rotate`, { method: 'POST' });
    return { status: r.status, body: await r.json() };
  }, controlUrl);
  check('the host of the rehearsal has another key', rotated.status === 200, JSON.stringify(rotated));
}
const blocked = await stateOfCore('host_key_changed');
check('the surface shows the blocked state of the Core',
  blocked.the_surface.the_line && blocked.the_surface.the_line.startsWith('Host-Key geändert'),
  blocked.the_surface.the_line);
const painted = await labels();
check('the reason of the block is named', painted.includes('HOST_KEY_CHANGED'),
  'the reason of the block is missing');

// The painted surface of the last state, so that the receipt carries the
// words of the surface and not only the word of one line.
const head = [
  '# the painted surface of the devices workstation: the connection of the device',
  '# the state of the Core and the word of the surface in the same moment',
  '# the semantics of the page, in the order of the DOM',
];
fs.writeFileSync(`${outDir}/connection-states-surface.txt`,
  head.concat(painted.split('\n')).join('\n') + '\n');

const receipt = {
  schema: 'oip-connection-states-v1',
  revision: process.env.OIP_REVISION || null,
  the_detail_is: 'the message that describes the failure of the check',
  scope: 'the honest connection states of the surface against the real Core',
  base,
  device: deviceId,
  the_states: states,
  findings,
  errors,
};
fs.writeFileSync(`${outDir}/connection-states.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ findings: findings.length, errors: errors.length,
  the_states: states.map((item) => item.the_state) }, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

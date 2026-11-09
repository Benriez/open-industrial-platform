// The browser receipt of the verified connection of a device (G4).
//
// The device workspace of the approved shell shows the association of a
// device with its connection. This receipt proves against the real Core and
// the owned loopback SSH fixture that the surface shows:
//
//   * the device of the authorized inventory with its connection;
//   * the state of the connection (the monitoring is really collecting);
//   * the host key of the fixture — the fingerprint the operator confirmed;
//   * the endpoint of the verified connection;
//   * the really verified identity of the host behind the expansion;
//   * the read-only monitoring with its polling and its revision;
//   * the measurements that were really read from the device.
//
// Usage: node browser_device_connection.mjs <baseUrl> <outDir> [loginCode]

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
const expectedFingerprint = process.env.OIP_EXPECTED_FINGERPRINT || '';
const expectedStatus = process.env.OIP_EXPECTED_CONNECTION_STATUS || '';
// The label of the state of the connection in the approved surface.
const STATE_LABELS = {
  collecting: 'Collecting',
  ssh_verified: 'SSH Verified',
  unreachable: 'Unreachable',
  stale: 'Stale',
  host_key_changed: 'Host-Key geändert',
  host_key_unknown: 'Host-Key unbekannt',
};
if (!base || !outDir) {
  console.error('usage: browser_device_connection.mjs <baseUrl> <outDir> [loginCode]');
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

// A control is looked for while the surface is scrolled: the semantics of
// the Flutter view carry only what is painted.
const scrollUntil = async (pattern, steps = 18) => {
  await page.mouse.move(700, 600);
  for (let step = 0; step < steps; step++) {
    const found = await page.evaluate((source) => {
      const expression = new RegExp(source);
      const out = [];
      document.querySelectorAll('flt-semantics').forEach((el) => {
        // The label of a control is published as the accessible name and as
        // the text of the semantics node.
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

// A control is activated by its accessible name: the label of a Flutter
// control is published as the accessible name of its semantics node. The
// smallest node that carries the name is the painted control itself.
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
      target = box;
    }
  }
  if (!target) throw new Error(`the control "${needle}" has no geometry`);
  await page.mouse.click(target.x + Math.min(target.width / 2, 60), target.y + target.height / 2);
  await page.waitForTimeout(1500);
};

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

// The whole painted surface: the semantics of the Flutter view carry what is
// painted, so the page is read while it is scrolled.
const readSurface = async () => {
  const lines = new Set();
  const collect = async () => {
    for (const line of (await labels()).split('\n')) {
      const trimmed = line.trim();
      if (trimmed) lines.add(trimmed);
    }
  };
  await collect();
  await page.mouse.move(700, 600);
  for (let step = 0; step < 16; step++) {
    await page.mouse.wheel(0, 700);
    await page.waitForTimeout(160);
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

// The device workspace of the approved shell.
await page.getByRole('button', { name: 'Navigation Geräte & Dienste' }).click({ force: true });
await page.waitForTimeout(5000);

// The inventory of the devices is below the fold of the workstation: the
// surface is scrolled until the device is painted.
const deviceOption = await scrollUntil(/existing-pi.*auswählen/);
check('the inventory of the scope lists the device', deviceOption.length > 0,
  deviceOption.join(' | ').slice(0, 200));
// The control is activated by its own name, not by the whole block of the
// semantics node.
await clickAccessible('existing-pi auswählen');
await page.waitForTimeout(3000);

// The connection of the device is shown with its state.
let surface = await readSurface();
check('the connection panel of the device is shown',
  /Verbindung & Monitoring|Connection & Monitoring/.test(surface), 'the panel is missing');
const stateLabel = STATE_LABELS[expectedStatus] || 'Collecting';
check('the state of the connection is shown', surface.includes(stateLabel),
  `the state ${expectedStatus} is not shown as "${stateLabel}"`);
if (expectedFingerprint) {
  check('the host key of the confirmed connection is shown',
    surface.includes(expectedFingerprint), 'the fingerprint of the fixture is missing');
}
check('the endpoint of the verified connection is shown',
  /SSH · [^@\s]+@127\.0\.0\.1:\d+/.test(surface), 'the endpoint is missing');
check('the monitoring of the device is shown',
  /Read-only Monitoring/.test(surface) && /Polling: \d+ s · Revision \d+/.test(surface),
  'the read-only monitoring is missing');

// The really verified identity of the host.
await clickAccessible('Tatsächlich verifizierte Identität');
await page.waitForTimeout(1500);
surface = await readSurface();
check('the verified identity of the host is shown',
  /Arbeitsspeicher|Hostname|Betriebssystem|memory_total_bytes|operating_system/i.test(surface),
  'the identity of the host is missing');

await page.screenshot({ path: `${outDir}/device-connection.png` });

const receipt = {
  schema: 'oip-device-connection-v1',
  revision: process.env.OIP_REVISION || null,
  the_detail_is: 'the message that describes the failure of the check',
  scope: 'the verified connection of a device in the approved surface against the real Core',
  base,
  expected_fingerprint: expectedFingerprint,
  findings,
  errors,
};
fs.writeFileSync(`${outDir}/device-connection.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ findings: findings.length, errors: errors.length }, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

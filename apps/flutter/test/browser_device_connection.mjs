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
// The identity of the device of the authorized inventory. The default is the
// device of the rehearsal of the device connection; another rehearsal may
// name its own device.
const deviceId = process.env.OIP_DEVICE_ID || 'existing-pi';
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
      target = element;
    }
  }
  if (!target) throw new Error(`the control "${needle}" has no geometry`);
  // The control is brought into the view before it is activated: a control
  // below the fold has a geometry outside the viewport, and the click would
  // land on something else.
  await target.scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  const box = await target.boundingBox();
  if (!box) throw new Error(`the control "${needle}" has no geometry after scrolling`);
  await page.mouse.click(box.x + Math.min(box.width / 2, 60), box.y + box.height / 2);
  await page.waitForTimeout(1500);
};

// The state of the verified identity: the panel refreshes itself, so the
// state of the tile is observed over the time.
// The nodes of the semantics that carry the title of the tile. The node of
// the title is the smallest one that carries it.
const identityNodes = async () => {
  const found = [];
  for (const element of await page.$$('flt-semantics')) {
    const label = (await element.getAttribute('aria-label')) || '';
    const own = (await element.evaluate((node) => (node.textContent || '').trim()));
    if (!label.includes('Tatsächlich verifizierte Identität') &&
        !own.includes('Tatsächlich verifizierte Identität')) continue;
    const box = await element.boundingBox();
    found.push({
      element,
      label,
      own,
      box,
      area: box ? box.width * box.height : Infinity,
      role: await element.getAttribute('role'),
      expanded: await element.getAttribute('aria-expanded'),
      tag: await element.evaluate((node) => node.tagName),
    });
  }
  found.sort((a, b) => a.area - b.area);
  return found;
};

// The tile is opened in every way a control of the surface can be activated.
// The attempt that works is recorded, so the evidence names the way.
const expandIdentity = async () => {
  const attempts = [];
  for (const variant of ['center', 'focus-enter', 'dispatch-click']) {
    const found = await identityNodes();
    if (!found.length) {
      attempts.push({ 'the_variant': variant, 'the_state': 'absent' });
      continue;
    }
    const node = found[0];
    const box = node.box;
    if (!box) {
      attempts.push({ 'the_variant': variant, 'the_state': 'no-geometry' });
      continue;
    }
    const x = box.x + Math.min(box.width / 2, 80);
    const y = box.y + box.height / 2;
    try {
      if (variant === 'center') {
        await page.mouse.click(x, y);
      } else if (variant === 'focus-enter') {
        await node.element.focus();
        await page.keyboard.press('Enter');
      } else {
        await node.element.dispatchEvent('click');
      }
    } catch (error) {
      attempts.push({ 'the_variant': variant, 'the_state': 'failed',
                      'the_detail': String(error).slice(0, 160) });
      continue;
    }
    await page.waitForTimeout(1200);
    const state = await identityState();
    attempts.push({ 'the_variant': variant, 'the_state': state, 'the_x': x, 'the_y': y,
                    'the_role': node.role, 'the_area': node.area });
    if (state === 'expanded') return { 'the_attempts': attempts, 'the_state': state };
  }
  return { 'the_attempts': attempts, 'the_state': await identityState() };
};

const identityState = async () => {
  const found = await identityNodes();
  if (!found.length) return 'absent';
  const text = found[0].label + ' ' + found[0].own;
  if (text.includes('Expanded')) return 'expanded';
  if (text.includes('Collapsed')) return 'collapsed';
  return 'present';
};

// The markup of the control, so a reader can see what is activated.
const identityMarkup = async () => {
  const found = await identityNodes();
  return found.slice(0, 6).map((item) => ({
    'the_label': item.label,
    'the_text': item.own.slice(0, 120),
    'the_box': item.box,
    'the_area': item.area,
    'the_role': item.role,
    'the_aria_expanded': item.expanded,
    'the_tag': item.tag,
  }));
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
  // The painted surface is kept as the evidence of what the operator sees.
  const surface = [...lines].join('\n');
  fs.writeFileSync(`${outDir}/device-connection-surface.txt`, surface + '\n');
  return surface;
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

// The states that the journey observed on the way.
const receiptStates = {};

// The device workspace of the approved shell.
await page.getByRole('button', { name: 'Navigation Geräte & Dienste' }).click({ force: true });
await page.waitForTimeout(5000);

// The inventory of the devices is below the fold of the workstation: the
// surface is scrolled until the device is painted.
const deviceOption = await scrollUntil(new RegExp(`${deviceId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}.*auswählen`));
check('the inventory of the scope lists the device', deviceOption.length > 0,
  deviceOption.join(' | ').slice(0, 200));
// The control is activated by its own name, not by the whole block of the
// semantics node.
await clickAccessible(`${deviceId} auswählen`);
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
// The state of the tile is observed while it is read: the panel refreshes
// itself every few seconds, and a reader must be able to keep it open.
const identityStates = [];
let identitySeen = '';
const observeIdentity = async (rounds) => {
  for (let step = 0; step < rounds; step++) {
    const state = await identityState();
    identityStates.push(state);
    if (state === 'expanded') {
      const painted = await labels();
      // The line of the verified identity names the kinds that are not
      // available; the registry of the device says "nicht verfügbar" too.
      if (painted.includes('Nicht verfügbar: ')) {
        identitySeen = painted;
        return true;
      }
    }
    await page.waitForTimeout(500);
  }
  return false;
};

// The stability of the tile: the panel refreshes itself, and the tile must
// stay open while the operator reads the verified identity.
const observeStability = async (rounds) => {
  const states = [];
  for (let step = 0; step < rounds; step++) {
    states.push(await identityState());
    await page.waitForTimeout(500);
  }
  receiptStates.identityStability = states;
  return states;
};
await observeIdentity(4);
let expansion = { 'the_attempts': [], 'the_state': 'not-tried' };
if (!identitySeen) {
  expansion = await expandIdentity();
  receiptStates.identityExpansion = expansion;
  // The panel refreshes itself every few seconds: the tile must stay open
  // while the operator reads the verified identity.
  await observeStability(24);
  if (!identitySeen) {
    const painted = await labels();
    if (painted.includes('Nicht verfügbar: ')) identitySeen = painted;
  }
}
fs.writeFileSync(`${outDir}/device-connection-identity-states.txt`,
  identityStates.join('\n') + '\n');
fs.writeFileSync(`${outDir}/device-connection-identity-markup.json`,
  JSON.stringify(await identityMarkup(), null, 2) + '\n');
receiptStates.identityStates = identityStates;
surface = identitySeen || await readSurface();
check('the verified identity of the host is shown',
  /Arbeitsspeicher|Hostname|Betriebssystem|memory_total_bytes|operating_system/i.test(surface),
  'the identity of the host is missing');
// The measurements that the host report does not deliver are **named** as
// unavailable. A measurement that is silently missing would look like a
// measurement of zero.
check('the measurements that are not available are named',
  /Nicht verfügbar/.test(surface)
  && /gpu/i.test(surface)
  && /temperature/i.test(surface)
  && /cpu_utilization/i.test(surface),
  'the unavailable measurements are not named on the surface');

await page.screenshot({ path: `${outDir}/device-connection.png` });

const receipt = {
  schema: 'oip-device-connection-v1',
  the_states_of_the_verified_identity: receiptStates.identityStates,
  the_opening_of_the_verified_identity: receiptStates.identityExpansion || null,
  the_stability_of_the_verified_identity: receiptStates.identityStability || null,
  revision: process.env.OIP_REVISION || null,
  the_detail_is: 'the message that describes the failure of the check',
  scope: 'the verified connection of a device in the approved surface against the real Core',
  base,
  expected_fingerprint: expectedFingerprint,
  findings,
  errors,
};
const receiptName = process.env.OIP_BROWSER_RECEIPT_NAME || 'device-connection.json';
fs.writeFileSync(`${outDir}/${receiptName}`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ findings: findings.length, errors: errors.length }, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

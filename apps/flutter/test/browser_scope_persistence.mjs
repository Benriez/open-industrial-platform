// The browser receipt of the scope of the operator (G3).
//
// The scope of the operator follows the session across the six workstations,
// and it survives a **refresh of the authorized projection**: the Core answers
// with a new projection, the client reads it again, and the scope of the
// operator must not be thrown away. The evidence of the identity of the
// session is what keeps it — the Core has no whoami route.
//
// This receipt proves it against the **real Core**: the operator selects a
// scope, the journey performs an authorized write (the Core changes, the
// authorized projection is delivered again and the surface shows the new
// state), and the scope must still be the scope of the operator. The
// contrast is measured too: a **new session** starts in the unified view.
//
// Usage: node browser_scope_persistence.mjs <baseUrl> <outDir>
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_scope_persistence.mjs <baseUrl> <outDir>');
  process.exit(2);
}
if (!code && process.env.OIP_IPC_SOCKET && process.env.OIP_BROWSER_CREDENTIAL) {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN || 'target/release/oip-server', [
    '--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
    '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL,
  ]).toString());
  code = minted.login_code;
}

fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const errors = [];
const check = (name, ok, detail) => {
  findings.push({ check: name, ok: !!ok, the_detail: detail ?? null });
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

// The surface is scrolled until the control is painted.
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

const optionTexts = async () => await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    const label = el.getAttribute('aria-label');
    const text = (label || el.textContent || '').trim();
    if (/auswählen/.test(text) && text.length < 300) out.push(text);
  });
  return out;
});

// The scope of the operator, as the surface names it.
const scopeLabel = async () => {
  const painted = await labels();
  const match = /Infrastructure Context: ([^\n]+)/.exec(painted);
  return match ? match[1].trim() : null;
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

// 1. the operator selects the scope of a site — an individual scope, not the
//    unified view.
await page.getByRole('button', { name: 'Navigation Übersicht' }).click({ force: true });
await page.waitForTimeout(2500);
await page.getByRole('button', { name: /Infrastructure Context:/ }).first()
  .waitFor({ state: 'attached', timeout: 60000 });
await clickText('Infrastructure Context:');
await page.waitForTimeout(2000);
const options = await optionTexts();
const siteOption = options.find((label) => /site-a1/.test(label) && !/source-a/.test(label));
check('the global selection offers the site of the scope', !!siteOption,
  options.map((label) => label.slice(0, 70)).join(' | '));
await clickText(siteOption);
await page.waitForTimeout(3000);
const selected = await scopeLabel();
check('the scope of the operator is the selected site',
  !!selected && /site-a1/.test(selected) && !/source-a/.test(selected), String(selected));

// 2. the devices of the scope
await page.getByRole('button', { name: 'Navigation Geräte & Dienste' }).click({ force: true });
await page.waitForTimeout(3000);
const before = await labels();
check('the devices of the scope are shown', /device-a/.test(before),
  'the device of the scope is missing');

// 3. the administration of the device: the write of the operator changes the
//    Core, and the surface reads the authorized projection again.
const device = page.getByRole('button', { name: /Gerät .*device-a.* auswählen/ }).first();
check('the device of the scope can be selected', await device.count() > 0,
  'the device of the scope is not in the list');
await device.click({ force: true });
await page.waitForTimeout(2500);
// The inspector of the device has its own scroll: the pointer is put over
// it, so that the wheel scrolls the inspector and not the page.
const scrollInspectorUntil = async (pattern, steps = 20) => {
  await page.mouse.move(1200, 600);
  for (let step = 0; step < steps; step++) {
    const found = await page.evaluate((source) => {
      const expression = new RegExp(source);
      const out = [];
      document.querySelectorAll('flt-semantics').forEach((el) => {
        const label = el.getAttribute('aria-label');
        const text = (label || el.textContent || '').trim();
        if (expression.test(text) && text.length < 400) out.push(text);
      });
      document.querySelectorAll('input,textarea').forEach((el) => {
        const label = el.getAttribute('aria-label') || '';
        if (expression.test(label)) out.push(label);
      });
      return out;
    }, pattern.source);
    if (found.length > 0) return found;
    await page.mouse.wheel(0, 500);
    await page.waitForTimeout(220);
  }
  return [];
};

const administration = await scrollInspectorUntil(/Anzeigename/);
check('the administration of the device is shown', administration.length > 0,
  'the administration of the device is not shown');
const newName = 'Scope persistence device';
const field = page.locator('input[aria-label="Anzeigename"]').first();
await field.click({ force: true });
await page.waitForTimeout(400);
await page.keyboard.press('Meta+A');
await page.keyboard.type(newName);
await page.waitForTimeout(600);
await page.keyboard.press('Meta+A');
await page.keyboard.type(newName);
await page.waitForTimeout(400);
const save = page.getByRole('button', { name: 'Änderungen speichern' }).first();
check('the administration can be saved', await save.count() > 0,
  'the save of the administration is not shown');
await save.click({ force: true });

// 4. the authorized projection is read again and the surface shows it
let refreshed = false;
let after = '';
for (let step = 0; step < 30 && !refreshed; step++) {
  await page.waitForTimeout(1000);
  after = await labels();
  refreshed = after.includes(newName);
}
// The answer of the Core: what the write really changed.
const record = await page.evaluate(async () => {
  const r = await fetch('/api/v2/inventory/devices?q=device-a',
    { headers: { 'Content-Type': 'application/json' } });
  return { status: r.status, body: await r.json() };
});
fs.writeFileSync(`${outDir}/scope-persistence-surface.txt`, after + '\n');
const written = ((record.body || {}).items || []).map((item) => item.record);
check('the Core holds the name of the write',
  written.some((item) => item.display_name === newName),
  JSON.stringify(written).slice(0, 300));
check('the refreshed projection reaches the surface', refreshed,
  `the Core holds ${JSON.stringify(written.map((item) => item.display_name))}`);

// 5. the scope of the operator survived the refresh
const survived = await scopeLabel();
check('the scope of the operator survives the refresh of the projection',
  !!survived && /site-a1/.test(survived) && !/source-a/.test(survived), String(survived));
await page.screenshot({ path: `${outDir}/scope-persistence.png` });

// 6. the contrast: a new session starts in the unified view again
await page.reload({ waitUntil: 'domcontentloaded' });
await page.waitForTimeout(9000);
const fresh = await scopeLabel();
check('a new session starts in the unified view again',
  !!fresh && /Alle berechtigten Infrastrukturen/.test(fresh), String(fresh));

const receipt = {
  schema: 'oip-scope-persistence-v1',
  revision: process.env.OIP_REVISION || null,
  the_detail_is: 'the message that describes the failure of the check',
  scope: 'the scope of the operator across a refresh of the authorized projection',
  base,
  the_selected_scope: selected,
  the_scope_after_the_refresh: survived,
  the_scope_of_the_new_session: fresh,
  findings,
  errors,
};
fs.writeFileSync(`${outDir}/scope-persistence.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ findings: findings.length, errors: errors.length }, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

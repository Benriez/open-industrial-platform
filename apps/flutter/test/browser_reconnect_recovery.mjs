// The browser receipt of the reconnect and the recovery (G6, G11, G12).
//
// The operator restarts the instance routinely. The application must never
// show stale data as live, and it must tell the operator what happened.
//
// The receipt proves against the real Core that
//
//   * the authorized projection is delivered before the restart;
//   * the death of the Core is noticed and the surface stops claiming a live
//     connection;
//   * the restart of the Core ends the session of the browser — the Core
//     holds the session in its memory — and the surface asks the operator for
//     a new code instead of showing stale content;
//   * a new code restores the authorized projection.
//
// The restart itself is carried out by the rehearsal: the journey asks the
// control server of the rehearsal to restart the instance.
//
// Usage: node browser_reconnect_recovery.mjs <baseUrl> <controlUrl> <outDir>

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import fs from 'node:fs';

const base = process.argv[2] || process.env.OIP_URL;
const control = process.argv[3] || process.env.OIP_CONTROL_URL;
const outDir = process.argv[4] || process.env.OIP_BROWSER_EVIDENCE;
if (!base || !control || !outDir) {
  console.error('usage: browser_reconnect_recovery.mjs <baseUrl> <controlUrl> <outDir>');
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const errors = [];
const check = (name, ok, detail) => {
  findings.push({ check: name, ok: !!ok, detail: detail ?? null });
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

const clickAccessible = async (needle) => {
  const locator = page.getByRole('button', { name: needle }).first();
  await locator.waitFor({ state: 'attached', timeout: 60000 });
  const box = await locator.boundingBox();
  if (!box) throw new Error(`the control "${needle}" has no geometry`);
  await page.mouse.click(box.x + Math.min(box.width / 2, 60), box.y + box.height / 2);
  await page.waitForTimeout(1200);
};

const login = async (code) => {
  const answer = await page.evaluate(async (c) => {
    const r = await fetch('/api/v2/browser/login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: c }),
    });
    return { status: r.status };
  }, code);
  return answer.status;
};

await page.goto(base, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !!document.querySelector('flutter-view'), null, { timeout: 300000 });
await page.waitForTimeout(6000);

// 1. the operator authorizes the session and sees the authorized projection.
const firstCode = await (await fetch(`${control}/code`)).text();
check('the first code is issued', firstCode.trim().length === 64,
  `${firstCode.trim().length} characters`);
check('the login is accepted', (await login(firstCode.trim())) === 200,
  'the Core accepted the one-time code');
await page.reload({ waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) out.push(child.textContent || '');
    }
  });
  return out.join('\n').includes('Infrastructure Context: Alle berechtigten Infrastrukturen');
}, null, { timeout: 300000 });
let surface = await labels();
check('the authorized projection is delivered', /Alle berechtigten Infrastrukturen/.test(surface),
  'the selector names the unified view of the authorized infrastructures');
const before = (surface.match(/\d{4}-\d{2}-\d{2} [\d:.]+ UTC/) || [''])[0];
await page.screenshot({ path: `${outDir}/reconnect-before.png` });

// 2. the instance is restarted by the rehearsal.
const restart = await fetch(`${control}/restart`, { method: 'POST' });
check('the instance is restarted', restart.status === 200,
  `the control server answered ${restart.status}`);

// 3. the surface must not claim a live connection and must not show stale
//    content as current. The session of the browser ends with the restart.
await page.waitForFunction(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) out.push(child.textContent || '');
    }
  });
  const text = out.join('\n');
  return text.includes('IDENTITÄT ERFORDERLICH') || text.includes('Operator-Sitzung autorisieren');
}, null, { timeout: 180000 });
surface = await labels();
check('the surface asks the operator for a new session',
  /IDENTITÄT ERFORDERLICH|Operator-Sitzung autorisieren/.test(surface),
  'the identity notice and the operator login are shown');
check('the surface names the restart as a cause of the end of the session',
  /Neustart der Instanz/.test(surface),
  'the panel of the operator login names the restart of the instance');
await page.screenshot({ path: `${outDir}/reconnect-lost-session.png` });

// 4. a new code restores the authorized projection.
const secondCode = (await (await fetch(`${control}/code`)).text()).trim();
check('a new code is issued', secondCode.length === 64, `${secondCode.length} characters`);
check('the new login is accepted', (await login(secondCode)) === 200,
  'the Core accepted the second one-time code');
await page.reload({ waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) out.push(child.textContent || '');
    }
  });
  return out.join('\n').includes('Infrastructure Context: Alle berechtigten Infrastrukturen');
}, null, { timeout: 300000 });
surface = await labels();
check('the authorized projection is restored', /Alle berechtigten Infrastrukturen/.test(surface),
  'the selector names the unified view again');
const after = (surface.match(/\d{4}-\d{2}-\d{2} [\d:.]+ UTC/) || [''])[0];
check('the projection carries a fresh moment', after !== '' && after !== before,
  `${before} -> ${after}`);
await page.screenshot({ path: `${outDir}/reconnect-restored.png` });

check('no browser JavaScript errors', errors.length === 0, errors.join(' | '));

const receipt = {
  schema: 'oip-reconnect-recovery-v1',
  scope: 'the reconnect and the recovery of the application against the real Core',
  base,
  the_moment_before_the_restart: before,
  the_moment_after_the_restart: after,
  findings,
  errors,
};
fs.writeFileSync(`${outDir}/reconnect-recovery.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ findings: findings.length, errors: errors.length }, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

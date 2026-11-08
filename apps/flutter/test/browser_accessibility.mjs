// The accessibility receipt of the integrated Spectrum-2027 workstations.
//
// The scope of this receipt is the name and role coverage of the rendered
// surface: every control that a person can reach must carry an accessible
// name, and every focusable element must be nameable. It is not a full
// WCAG audit and it does not claim one; the operator's own review of the
// application remains open.
//
// Usage: node browser_accessibility.mjs <baseUrl> <outDir> [loginCode]

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import fs from 'node:fs';

const base = process.argv[2];
const outDir = process.argv[3];
const code = process.argv[4];
if (!base || !outDir) {
  console.error('usage: browser_accessibility.mjs <baseUrl> <outDir> [loginCode]');
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const errors = [];
// A Core denial (401/403/404) is a legitimate state that the UI has to show.
// It is recorded, but it is not an accessibility regression. A JavaScript
// exception is.
const coreDenials = [];
const external = [];
const check = (name, ok, detail) => {
  findings.push({ check: name, ok: !!ok, detail: detail ?? null });
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
const INTERACTIVE = ['button', 'textbox', 'combobox', 'checkbox', 'radio', 'switch',
  'link', 'slider', 'spinbutton', 'listbox', 'menuitem', 'tab'];

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
  if (/Failed to load resource/i.test(text)) {
    coreDenials.push(text.slice(0, 200));
    return;
  }
  errors.push('console: ' + text.slice(0, 200));
});
page.on('request', (r) => {
  const url = r.url();
  if (!url.startsWith(base) && !url.startsWith('http://127.0.0.1')) external.push(url);
});

await page.goto(base, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !!document.querySelector('flutter-view'), null, { timeout: 120000 }).catch(() => {});
await page.waitForTimeout(8000);
check('the application demands an operator session',
  (await page.locator('body').ariaSnapshot()).includes('Lokale Operator-Anmeldung'),
  'the anonymous state does not ask for the operator');

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

const perStation = [];
for (const station of WORKSTATIONS) {
  await page.getByRole('button', { name: `Navigation ${station.name}` }).click({ force: true });
  await page.waitForTimeout(3500);
  const controls = await page.evaluate((roles) => {
    const out = [];
    document.querySelectorAll('flt-semantics').forEach((el) => {
      const role = el.getAttribute('role');
      if (!roles.includes(role)) return;
      const label = (el.getAttribute('aria-label') || el.textContent || '').trim();
      const tabindex = el.getAttribute('tabindex');
      out.push({
        role,
        name: label,
        focusable: tabindex !== null && Number(tabindex) >= 0,
      });
    });
    return out;
  }, INTERACTIVE);
  const unnamed = controls.filter((control) => control.name.length === 0);
  const unnamedFocusable = controls.filter((control) => control.focusable && control.name.length === 0);
  perStation.push({
    workstation: station.slug,
    controls: controls.length,
    focusable: controls.filter((control) => control.focusable).length,
    unnamed: unnamed.length,
    unnamedFocusable: unnamedFocusable.length,
    roles: [...new Set(controls.map((control) => control.role))].sort(),
  });
  check(`${station.slug}: every reachable control has an accessible name`,
    unnamed.length === 0, `${unnamed.length} unnamed controls`);
  check(`${station.slug}: every focusable element is nameable`,
    unnamedFocusable.length === 0, `${unnamedFocusable.length} unnamed focusable elements`);
  await page.screenshot({ path: `${outDir}/accessibility-${station.slug}.png` });
}

check('no browser JavaScript errors', errors.length === 0, errors.join(' | '));
check('no external browser requests', external.length === 0, external.join(', '));

const receipt = {
  schema: 'oip-accessibility-receipt-v1',
  scope: 'name and role coverage of the rendered surface of the six workstations; not a full WCAG audit',
  base,
  stations: perStation,
  controls_total: perStation.reduce((sum, station) => sum + station.controls, 0),
  unnamed_total: perStation.reduce((sum, station) => sum + station.unnamed, 0),
  findings,
  console_errors: errors,
  core_denials: coreDenials,
  external_requests: external,
};
fs.writeFileSync(`${outDir}/accessibility.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({
  verdict: 'PASS',
  controls: receipt.controls_total,
  unnamed: receipt.unnamed_total,
  stations: perStation.map((station) => `${station.workstation}:${station.controls}`).join(' '),
}, null, 2));
await browser.close();
process.exit(0);

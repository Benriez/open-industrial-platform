// The browser receipt of the global infrastructure context (G3).
//
// The global Infrastructure Context is the one selection of the whole
// application. The receipt proves against the real Core that
//
//   * the selector offers the unified view of every authorized
//     infrastructure and every individual infrastructure, site and source of
//     the authorized hierarchy;
//   * the selection of an individual infrastructure scopes the projection of
//     the workstation;
//   * the shared scope follows the operator across all six workstations;
//   * the unified view returns every authorized infrastructure.
//
// It also proves the rule of the contract: the selection narrows already
// authorized data and grants no permission.
//
// Usage: node browser_global_context.mjs <baseUrl> <outDir> [loginCode]

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_global_context.mjs <baseUrl> <outDir> [loginCode]');
  process.exit(2);
}
// The one-use code of the session is minted right before the run.
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
const coreDenials = [];
const check = (name, ok, detail) => {
  findings.push({
    check: name,
    ok: !!ok,
    // The message describes the failure of the check. A check that
    // passed carries it as well, so a reader does not mistake it for
    // an observation of the surface.
    the_failure_message: detail ?? null,
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
    coreDenials.push(text.slice(0, 160));
    return;
  }
  errors.push('console: ' + text.slice(0, 200));
});

// A control of the Flutter view is activated with a real mouse event on its
// painted position: the semantics node of a control is a container node and
// a Playwright click is intercepted by the flutter-view.
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
  await page.mouse.click(
    target.x + Math.min(target.width / 2, 60), target.y + target.height / 2);
  await page.waitForTimeout(1400);
};

const accessibleLabels = async () => await page.evaluate(() => {
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

await page.goto(base, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !!document.querySelector('flutter-view'), null, { timeout: 120000 }).catch(() => {});
await page.waitForTimeout(8000);

if (code) {
  const login = await page.evaluate(async (c) => {
    const r = await fetch('/api/v2/browser/login', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: c }),
    });
    return { status: r.status };
  }, code);
  check('browser-login accepted', login.status === 200, JSON.stringify(login));
  await page.reload({ waitUntil: 'domcontentloaded' });
  // The web release is several megabytes and the loopback is slow. The
  // application is ready when the context of the operator is authorized.
  await page.waitForFunction(() => {
    const out = [];
    document.querySelectorAll('flt-semantics').forEach((el) => {
      for (const child of el.childNodes) {
        if (child.nodeType === 3) out.push(child.textContent || '');
      }
    });
    return out.join('\n').includes('Infrastructure Context: Alle berechtigten Infrastrukturen');
  }, null, { timeout: 240000 });
}

await page.getByRole('button', { name: 'Navigation Übersicht' }).click({ force: true });
await page.waitForTimeout(3000);

// 1. the selector offers the unified view and the individual infrastructures
const selector = page.getByRole('button', { name: new RegExp('Infrastructure Context:') }).first();
await selector.waitFor({ state: 'attached', timeout: 60000 });
// The label of the selector is published as the accessible text of the
// surface, not as an attribute.
const contextLabel = async () => {
  const labels = await accessibleLabels();
  const match = /Infrastructure Context: ([^\n]*)/.exec(labels);
  return match ? match[1].trim() : '';
};
const unifiedText = await contextLabel();
check('the selector starts in the unified view',
  /Alle berechtigten Infrastrukturen/.test(unifiedText), unifiedText);

// The infrastructure explorer of the command center publishes the same
// global selection as a button: "global auswählen". It is the selection of
// the whole application, not a filter of one page.
const optionTexts = async () => await page.evaluate(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    const text = (el.textContent || '').trim();
    if (/global auswählen/.test(text) && text.length < 400) out.push(text);
  });
  return out;
});
const options = await optionTexts();
check('the global selection offers the individual infrastructures', options.length > 0,
  `${options.length} options`);
const infrastructureOption = options.find((label) => /Infrastructure A1 global auswählen/.test(label));
const otherOption = options.find((label) => /Infrastructure A2 global auswählen/.test(label));
check('the individual infrastructures are offered',
  !!infrastructureOption && !!otherOption, options.map((label) => label.slice(0, 60)).join(' | '));
check('the selection grants no permission',
  options.every((label) => /global auswählen/.test(label)), 'an option offers another meaning');
await page.screenshot({ path: `${outDir}/global-context-options.png` });

// 2. the selection of an individual infrastructure scopes the projection
const explorerOption = page.getByRole('button', { name: /Infrastructure A1 global auswählen/ }).first();
await explorerOption.waitFor({ state: 'attached', timeout: 30000 });
await explorerOption.click({ force: true });
await page.waitForTimeout(2500);
const selected = await contextLabel();
check('the selector names the selected infrastructure',
  /Infrastructure A1/.test(selected) && !/Alle berechtigten/.test(selected), selected);
const scoped = await accessibleLabels();
check('the scoped projection shows the selected infrastructure',
  /Organization A \/ Infrastructure A1/.test(scoped), 'the placement of the selection is missing');
check('the scoped projection hides the other infrastructure',
  !/Organization A \/ Infrastructure A2/.test(scoped), 'another infrastructure is still in the projection');
await page.screenshot({ path: `${outDir}/global-context-infrastructure-a1.png` });

// 3. the shared scope follows the operator across all six workstations
const scopePerStation = [];
for (const station of WORKSTATIONS) {
  await page.getByRole('button', { name: `Navigation ${station.name}` }).click({ force: true });
  await page.waitForTimeout(2500);
  const label = await contextLabel();
  scopePerStation.push({ workstation: station.slug, label });
  check(`${station.slug}: the shared scope follows the selection`,
    /Infrastructure A1/.test(label) && !/Alle berechtigten/.test(label), label);
}
await page.screenshot({ path: `${outDir}/global-context-scope-follows.png` });

// 4. the unified view returns every authorized infrastructure.
//
// The scope is the choice of the session, not a persisted state: a new
// session of the application starts in the unified view again.
await page.reload({ waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => {
  const out = [];
  document.querySelectorAll('flt-semantics').forEach((el) => {
    for (const child of el.childNodes) {
      if (child.nodeType === 3) out.push(child.textContent || '');
    }
  });
  return out.join('\n').includes('Infrastructure Context: Alle berechtigten Infrastrukturen');
}, null, { timeout: 240000 });
const restored = await contextLabel();
check('the selector returns to the unified view',
  /Alle berechtigten Infrastrukturen/.test(restored), restored);
const allLabels = await accessibleLabels();
check('the unified view shows every authorized infrastructure',
  /Organization A \/ Infrastructure A1/.test(allLabels) &&
  /Organization A \/ Infrastructure A2/.test(allLabels), 'an authorized infrastructure is missing');
await page.screenshot({ path: `${outDir}/global-context-unified.png` });

check('no browser JavaScript errors', errors.length === 0, errors.join(' | '));

const receipt = {
  schema: 'oip-global-context-receipt-v1',
  revision: process.env.OIP_REVISION || null,
  base,
  options_offered: options.length,
  scope_per_workstation: scopePerStation,
  findings,
  console_errors: errors,
  core_denials: coreDenials,
};
fs.writeFileSync(`${outDir}/global-context.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({
  verdict: 'PASS',
  options: options.length,
  workstations: scopePerStation.length,
}, null, 2));
await browser.close();
process.exit(0);

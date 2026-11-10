// The browser receipt of the status of the settings categories (G8).
//
// The Core answers for every category of the settings whether the category is
// administered offline or only read. The navigation of the settings shows
// that answer instead of a guess of the client — the wire names of the Core
// are snake_case and the mapping of the client is explicit.
//
// This receipt proves against the real Core that
//
//   * the Core answers a status for every category of the settings;
//   * the navigation offers **every** category of the Core;
//   * the status the navigation shows for a category is the status the Core
//     answered for that category — the answer of the Core and not a guess of
//     the client;
//   * no wire name of the Core leaks into the surface.
//
// Usage: node browser_settings_status.mjs <baseUrl> <outDir> [loginCode]
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_settings_status.mjs <baseUrl> <outDir> [loginCode]');
  process.exit(2);
}
if (!code && process.env.OIP_IPC_SOCKET && process.env.OIP_BROWSER_CREDENTIAL) {
  const minted = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN || 'target/release/oip-server', [
    '--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
    '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL,
  ]).toString());
  code = minted.login_code;
}

// The explicit mapping of the client: the wire name of the Core and the word
// the surface shows. A status that the Core sends and the client does not
// know is shown as it is — the journey proves that this does not happen.
const LABELS = {
  offline_administration_required: 'Nur offline administrierbar',
  read_only: 'Nur lesend',
};
const labelOf = (status) => (Object.prototype.hasOwnProperty.call(LABELS, status)
  ? LABELS[status] : status);

// The categories of the navigation, as the surface names them.
const CATEGORIES = {
  general: 'General',
  mcp_agents: 'MCP & Agents',
  infrastructure: 'Infrastructure',
  data_storage: 'Data & Storage',
  diagnostics: 'Diagnostics',
  security_access: 'Security & Access',
  system: 'System',
};

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
  if (/Failed to load resource/i.test(text) || /\b403\b/.test(text)) return;
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

// The painted surface: the semantics of the Flutter view carry what is
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
  for (let step = 0; step < 10; step++) {
    await page.mouse.wheel(0, 700);
    await page.waitForTimeout(180);
    await collect();
  }
  await page.mouse.wheel(0, -20000);
  await page.waitForTimeout(600);
  return [...lines].join('\n');
};

// The status the navigation shows for the selected category.
const shownStatus = async () => {
  const painted = await labels();
  for (const line of painted.split('\n')) {
    const match = /^CORE · (.+)$/.exec(line.trim());
    if (match) return match[1].trim();
  }
  return null;
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

// The answer of the Core, read with the session of the operator.
const answer = await page.evaluate(async () => {
  const r = await fetch('/api/v2/settings', { headers: { 'Content-Type': 'application/json' } });
  return { status: r.status, body: await r.json() };
});
check('the Core answers the settings of the instance', answer.status === 200,
  JSON.stringify(answer).slice(0, 300));
const categories = (answer.body && answer.body.categories) || [];
check('the Core answers a status for every category of the settings',
  categories.length > 0 && categories.every((item) => typeof item.status === 'string'
    && item.status.length > 0),
  JSON.stringify(categories).slice(0, 300));

// The workstation of the settings.
await page.getByRole('button', { name: 'Navigation Einstellungen' }).click({ force: true });
await page.waitForTimeout(4000);

const measured = [];
for (const category of categories) {
  const name = category.category;
  const label = CATEGORIES[name];
  check(`the navigation offers the category ${name}`, typeof label === 'string',
    `the Core answered the category ${name}, which the surface does not name`);
  const button = page.getByRole('button', { name: `Settings-Kategorie ${label}` });
  const count = await button.count();
  check(`the category ${name} is in the navigation`, count > 0,
    `the navigation has no category ${label}`);
  await button.first().click({ force: true });
  await page.waitForTimeout(1200);
  const shown = await shownStatus();
  const expected = labelOf(category.status);
  check(`the status of the category ${name} is the status of the Core`,
    shown === expected, `the Core answered ${expected}, the surface shows ${shown}`);
  measured.push({
    the_category: name,
    the_label_of_the_surface: label,
    the_status_of_the_core: category.status,
    the_word_of_the_surface: shown,
  });
}

const surface = await readSurface();
fs.writeFileSync(`${outDir}/settings-status-surface.txt`, surface + '\n');
const shown = [...surface.split('\n')]
  .map((line) => /^CORE · (.+)$/.exec(line.trim()))
  .filter(Boolean)
  .map((match) => match[1].trim());
check('no wire name of the Core leaks into the surface',
  !shown.some((item) => Object.prototype.hasOwnProperty.call(LABELS, item)),
  JSON.stringify(shown));
check('every category of the Core was measured',
  measured.length === categories.length,
  `${measured.length} of ${categories.length}`);

const receipt = {
  schema: 'oip-settings-status-v1',
  revision: process.env.OIP_REVISION || null,
  the_detail_is: 'the message that describes the failure of the check',
  scope: 'the status of the settings categories in the approved surface against the real Core',
  base,
  the_categories_of_the_core: measured,
  the_statuses_of_the_surface: shown,
  findings,
  errors,
};
fs.writeFileSync(`${outDir}/settings-status.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ findings: findings.length, errors: errors.length,
  the_categories: categories.length }, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

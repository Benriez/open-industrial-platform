// The client side of the performance baseline of the release build.
//
// The Core side of the baseline is measured by the acceptance harness (the
// latency of the official MCP probe and the resource use of the Core). This
// receipt measures what the operator waits for in the browser:
//
//   * the first paint of the delivered web release;
//   * the operator login that the anonymous state demands;
//   * the interactive shell with the six workstations and the global context;
//   * the authorized projection of the infrastructure.
//
// The numbers are a local measurement of this machine, not an SLA.
//
// Usage: node browser_performance.mjs <baseUrl> <outDir> [loginCode]

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_performance.mjs <baseUrl> <outDir> [loginCode]');
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

const browser = await chromium.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
let transferred = 0;
let requests = 0;
page.on('response', async (response) => {
  requests += 1;
  try {
    const length = response.headers()['content-length'];
    if (length) transferred += Number(length);
  } catch (_) { /* the header is optional */ }
});

const started = Date.now();
await page.goto(base, { waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !!document.querySelector('flutter-view'), null, { timeout: 300000 });
const firstPaintMs = Date.now() - started;

// The anonymous state of the real mode demands the operator session.
await page.getByRole('button', { name: /Operator-Sitzung autorisieren/ }).waitFor({ state: 'attached', timeout: 300000 });
const loginGateMs = Date.now() - started;

// The authorized session: the shell with the six workstations.
const sessionStarted = Date.now();
await page.evaluate(async (c) => {
  const response = await fetch('/api/v2/browser/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: c }),
  });
  return response.status;
}, code);
await page.reload({ waitUntil: 'domcontentloaded' });
await page.waitForFunction(() => !!document.querySelector('flutter-view'), null, { timeout: 300000 });
for (const name of ['Übersicht', 'Geräte & Dienste', 'Netzwerk & VPN', 'OPC-UA-Browser', 'Diagnose & Ereignisse', 'Einstellungen']) {
  await page.getByRole('button', { name: `Navigation ${name}` }).first()
    .waitFor({ state: 'attached', timeout: 300000 });
}
const shellMs = Date.now() - sessionStarted;

// The authorized projection of the infrastructure.
const projectionStarted = Date.now();
await page.getByRole('button', { name: /Infrastructure Context:/ }).first()
  .waitFor({ state: 'attached', timeout: 300000 });
let projectionMs = projectionStarted;
for (let attempt = 0; attempt < 120; attempt++) {
  const snapshot = await page.locator('body').ariaSnapshot();
  if (snapshot.includes('Infrastrukturübersicht')) {
    projectionMs = Date.now() - projectionStarted;
    break;
  }
  await page.waitForTimeout(250);
}

const bundle = Buffer.from(await (await context.request.get(base.replace(/\/$/, '') + '/main.dart.js', { timeout: 300000 })).body());
const receipt = {
  schema: 'oip-performance-receipt-v1',
  scope: 'client side of the delivered web release on this machine; a local measurement, not an SLA',
  base,
  first_paint_ms: firstPaintMs,
  login_gate_ms: loginGateMs,
  authenticated_shell_ms: shellMs,
  authorized_projection_ms: projectionMs,
  requests,
  transferred_bytes: transferred,
  bundle_sha256: createHash('sha256').update(bundle).digest('hex'),
  bundle_bytes: bundle.length,
};
fs.writeFileSync(`${outDir}/performance.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify(receipt, null, 2));
await browser.close();
process.exit(0);

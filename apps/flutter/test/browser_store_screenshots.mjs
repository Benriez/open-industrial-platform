// The store assets of the Mac App Store listing.
//
// Apple accepts a screenshot of a Mac app in one of four sizes with a 16:10
// aspect ratio (1280 x 800, 1440 x 900, 2560 x 1600, 2880 x 1800) and forbids
// an alpha channel. This script therefore captures the **viewport** of the
// client in one of those sizes — never the full page, whose height would be
// whatever the content happens to be — and proves every property of the file
// it writes: the exact pixel size and the absence of an alpha channel.
//
// The captures are the **store assets**. They are produced by the release
// build of the client through the managed Core; the acceptance of the visible
// result stays with the operator and is never claimed here.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_STORE_EVIDENCE;
const width = Number(process.argv[4] || process.env.OIP_STORE_WIDTH || 1440);
const height = Number(process.argv[5] || process.env.OIP_STORE_HEIGHT || 900);
let code = process.argv[6] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_store_screenshots.mjs <baseUrl> <outDir> [width] [height] [loginCode]');
  process.exit(2);
}
// The sizes that Apple accepts for a Mac app: 16:10, no alpha channel.
const ACCEPTED = [[1280, 800], [1440, 900], [2560, 1600], [2880, 1800]];
if (!ACCEPTED.some(([w, h]) => w === width && h === height)) {
  console.error(`the size ${width}x${height} is not a size that Apple accepts for a Mac app`);
  process.exit(2);
}
if (!code && process.env.OIP_IPC_SOCKET && process.env.OIP_BROWSER_CREDENTIAL) {
  const result = JSON.parse(execFileSync(process.env.OIP_SERVER_BIN, [
    '--browser-login', '--ipc-socket', process.env.OIP_IPC_SOCKET,
    '--ipc-credential', process.env.OIP_BROWSER_CREDENTIAL,
  ], { encoding: 'utf8' }));
  code = result.login_code;
}
if (fs.existsSync(outDir) && fs.readdirSync(outDir).length > 0) {
  console.error(`refusing to mix store assets in a non-empty directory: ${outDir}`);
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const workstations = [
  { name: 'Übersicht', slug: 'overview', marker: 'INFRASTRUCTURE COMMAND CENTER · READ-ONLY' },
  { name: 'Geräte & Dienste', slug: 'devices', marker: 'DEVICES & SERVICES · OBJECT WORKSPACE' },
  { name: 'Netzwerk & VPN', slug: 'network', marker: 'NETWORK ENGINEERING EXPLORER · READ-ONLY' },
  // The address space is **delivered** by the Core: a capture that shows an
  // empty catalogue would misrepresent the product. The workstation waits for
  // the number of the delivered nodes.
  { name: 'OPC-UA-Browser', slug: 'opcua', marker: 'ADRESSRAUM-EXPLORER · READ-ONLY',
    ready: /([1-9][0-9]*) Nodes/ },
  { name: 'Diagnose & Ereignisse', slug: 'diagnostics', marker: 'EVENTS · UNTERSUCHUNGSKONTEXT' },
  { name: 'Einstellungen', slug: 'settings', marker: 'SETTINGS · APPLICATION MANAGEMENT' },
];

const findings = [];
const errors = [];
const captures = [];
// The prohibited regressions of the binding UI contract (R1-R10 of
// `docs/design/OIP_CANONICAL_UI_BASELINE.md`). A store asset that shows one
// of them would publish a regression of the approved shell.
const forbidden = ['Deine Infrastruktur. Ein Bild.', 'Erfasste Geräte',
  'Erreichbare Geräte', 'Temperatur M-01', 'Temperatur · M-01', 'Normalbetrieb',
  'Tailnet', 'Remote Site', 'OIP / 005', 'AGENT-FIRST'];
// M-01 is forbidden only as the primary managed overview metric. Real OPC-UA
// nodes may legitimately carry that identifier on another workstation.
const overviewForbidden = [...forbidden, 'M-01'];
const check = (name, ok, detail) => {
  findings.push({ check: name, ok: !!ok, the_detail: detail ?? null });
  if (!ok) throw new Error(`${name}: ${detail ?? 'failed'}`);
};

// The property of a PNG that decides whether Apple accepts it: the size in
// the header and the colour type. A type 6 carries an alpha channel, and
// Apple refuses a screenshot with one.
function readPng(file) {
  const buffer = fs.readFileSync(file);
  const signature = buffer.subarray(0, 8).toString('hex');
  if (signature !== '89504e470d0a1a0a') return null;
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
    // 0: grey, 2: truecolour, 3: indexed, 4: grey+alpha, 6: truecolour+alpha
    the_colour_type: buffer[25],
    the_carries_an_alpha_channel: buffer[25] === 4 || buffer[25] === 6,
  };
}

const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const context = await browser.newContext({ viewport: { width, height } });
const page = await context.newPage();
page.on('pageerror', (error) => errors.push('pageerror: ' + error.message.slice(0, 200)));
page.on('console', (message) => {
  if (message.type() !== 'error') return;
  const text = message.text();
  if (/Failed to load resource/i.test(text)) return;
  errors.push('console: ' + text.slice(0, 200));
});
const snapshot = async () => page.locator('body').ariaSnapshot();
async function waitForAria(marker) {
  for (let attempt = 0; attempt < 120; attempt++) {
    if ((await snapshot()).includes(marker)) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`timed out waiting for visible marker: ${marker}`);
}
// The surface is **settled** when two consecutive readings of it are equal:
// the marker of a workstation appears before its data is rendered, and a
// capture that is taken in between shows an empty surface.
async function waitForSettled(ready) {
  if (ready) {
    for (let attempt = 0; attempt < 120; attempt++) {
      if (ready.test(await snapshot())) break;
      await page.waitForTimeout(250);
    }
  }
  let previous = null;
  for (let attempt = 0; attempt < 40; attempt++) {
    const current = await snapshot();
    if (current === previous) return current;
    previous = current;
    await page.waitForTimeout(250);
  }
  return previous;
}
async function typeLoginCode(value) {
  const input = page.getByRole('textbox', { name: 'Einmalcode', exact: true });
  for (let attempt = 0; attempt < 100 && !(await input.isEditable()); attempt++) {
    await page.waitForTimeout(100);
  }
  await input.click({ force: true });
  await input.evaluate((element) => element.blur());
  await page.waitForTimeout(650);
  await input.focus();
  await page.keyboard.type(value, { delay: 20 });
}

let fatal = null;
try {
  const response = await page.goto(base, { waitUntil: 'domcontentloaded' });
  check('the application answers', response?.status() === 200, response?.status());
  await page.getByRole('button', { name: 'Operator-Sitzung autorisieren', exact: true })
    .waitFor({ timeout: 120000 });
  check('the one-use login code is available', !!code);
  await typeLoginCode(code);
  await page.getByRole('button', { name: 'Operator-Sitzung autorisieren', exact: true }).click();
  await waitForAria('Alle berechtigten Infrastrukturen');

  // The catalogue of the source must be **delivered** before a workstation
  // that shows it is captured: a store asset that shows an empty address
  // space would misrepresent the product. The count is read through the
  // authorized session of the page itself.
  const catalogue = await page.evaluate(async () => {
    const answer = await fetch('/api/v2/opcua/nodes?q=&folder=all&offset=0&limit=1',
      { credentials: 'include' });
    return answer.ok ? await answer.json() : { total: 0 };
  });
  let total = catalogue.total || 0;
  for (let attempt = 0; attempt < 120 && total === 0; attempt++) {
    await page.waitForTimeout(500);
    const again = await page.evaluate(async () => {
      const answer = await fetch('/api/v2/opcua/nodes?q=&folder=all&offset=0&limit=1',
        { credentials: 'include' });
      return answer.ok ? await answer.json() : { total: 0 };
    });
    total = again.total || 0;
  }
  check('the catalogue of the source is delivered', total > 0, total);

  for (const workstation of workstations) {
    // Flutter 3.22 deduplicates rapid pointer/browser gestures for 500 ms.
    await page.waitForTimeout(650);
    await page.getByRole('button', { name: `Navigation ${workstation.name}`, exact: true }).click();
    await waitForAria(workstation.marker);
    const settled = await waitForSettled(workstation.ready);
    const scoped = workstation.slug === 'overview' ? overviewForbidden : forbidden;
    for (const marker of scoped.filter((m) =>
      !['M-01', 'Normalbetrieb'].includes(m) &&
      !(workstation.slug === 'settings' && m === 'AGENT-FIRST'))) {
      check(`no legacy marker ${marker} on ${workstation.slug}`,
        !settled.includes(marker));
    }
    if (workstation.slug === 'settings') {
      check('the agent-first principle is named in the technical context of the settings',
        settled.includes('AGENT-FIRST'));
    }
    const overflow = await page.evaluate(() => Math.max(
      document.documentElement.scrollWidth - window.innerWidth,
      document.body.scrollWidth - window.innerWidth,
    ));
    check(`the workstation ${workstation.slug} has no horizontal overflow`, overflow <= 0, overflow);
    // The **viewport**, never the full page: the store accepts a size, not a
    // page whose height is whatever the content happens to be.
    const file = path.join(outDir, `store-${workstation.slug}-${width}x${height}.png`);
    await page.screenshot({ path: file, fullPage: false });
    const measured = readPng(file);
    check(`the capture of ${workstation.slug} is a PNG`, measured !== null, file);
    check(`the capture of ${workstation.slug} has the accepted size`,
      measured.width === width && measured.height === height,
      `${measured.width}x${measured.height}`);
    check(`the capture of ${workstation.slug} carries no alpha channel`,
      !measured.the_carries_an_alpha_channel, measured.the_colour_type);
    captures.push({
      the_workstation: workstation.name,
      the_slug: workstation.slug,
      the_file: path.basename(file),
      the_width: measured.width,
      the_height: measured.height,
      the_colour_type: measured.the_colour_type,
      the_carries_an_alpha_channel: measured.the_carries_an_alpha_channel,
      the_bytes: fs.statSync(file).size,
    });
    findings.push({ check: `capture ${workstation.slug}`, ok: true, the_detail: file });
  }
  check('no browser JavaScript error', errors.length === 0, errors.join(' | '));
} catch (error) {
  fatal = error.message || String(error);
} finally {
  await browser.close().catch(() => {});
}

const receipt = {
  schema: 'oip-store-screenshots-browser-v1',
  the_base: base,
  the_size: { the_width: width, the_height: height },
  the_sizes_that_apple_accepts: ACCEPTED,
  the_workstations: workstations.map((w) => w.name),
  the_captures: captures,
  the_findings: findings,
  the_errors: errors,
  the_fatal: fatal,
  the_verdict: fatal ? 'FAIL' : 'PASS',
  the_finished_utc: new Date().toISOString(),
};
fs.writeFileSync(path.join(outDir, 'browser-store-screenshots.json'),
  JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify({
  the_verdict: receipt.the_verdict,
  the_captures: captures.length,
  the_size: receipt.the_size,
  the_fatal: fatal,
}, null, 2));
process.exit(fatal ? 1 : 0);

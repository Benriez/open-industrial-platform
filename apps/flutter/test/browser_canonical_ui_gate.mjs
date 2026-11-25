const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import { createHash, randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

// Managed real-mode canonical UI gate. Secrets never enter the receipt.
const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_canonical_ui_gate.mjs <baseUrl> <outDir> [loginCode]');
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
  console.error(`refusing to mix canonical UI evidence in a non-empty directory: ${outDir}`);
  process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const findings = [];
const errors = [];
const coreDenials = [];
const external = [];
const screenshots = [];
const check = (name, ok, detail) => {
  findings.push({
    check: name,
    ok: !!ok,
    // The observed value of the check (the status of a request, the
    // digest of a bundle). A check without an observation carries null.
    the_detail: detail ?? null,
  });
  if (!ok) throw new Error(`${name}: ${detail ?? 'failed'}`);
};
const workstations = [
  { name: 'Übersicht', slug: 'overview', marker: 'Diagnose öffnen' },
  { name: 'Geräte & Dienste', slug: 'devices', marker: 'Gerät hinzufügen' },
  { name: 'Netzwerk & VPN', slug: 'network', marker: 'Beziehungen prüfen' },
  { name: 'OPC-UA-Browser', slug: 'opcua', marker: 'SERVER-GESTEUERTER ZUGRIFF' },
  { name: 'Diagnose & Ereignisse', slug: 'diagnostics', marker: 'EVENTS · UNTERSUCHUNGSKONTEXT' },
  { name: 'Einstellungen', slug: 'settings', marker: 'READ-ONLY / OFFLINE ADMIN' },
];
const forbidden = ['Deine Infrastruktur. Ein Bild.', 'Erfasste Geräte',
  'Erreichbare Geräte', 'Temperatur M-01', 'Temperatur · M-01', 'Normalbetrieb',
  'Tailnet', 'Remote Site', 'OIP / 005', 'AGENT-FIRST'];
// M-01 is forbidden only as the primary managed overview metric. Real OPC-UA
// nodes may legitimately carry that identifier on another workstation.
const overviewForbidden = [...forbidden, 'M-01'];

const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await context.newPage();
page.on('pageerror', (error) => errors.push('pageerror: ' + error.message.slice(0, 200)));
page.on('console', (message) => {
  if (message.type() !== 'error') return;
  const text = message.text();
  if (/Failed to load resource/i.test(text)) return;
  errors.push('console: ' + text.slice(0, 200));
});
page.on('response', (response) => {
  if (response.status() >= 400) {
    coreDenials.push({ url: response.url(), status: response.status() });
  }
});
await context.route('**/*', (route) => {
  const url = new URL(route.request().url());
  if (['http:', 'https:'].includes(url.protocol) && url.origin !== new URL(base).origin) {
    external.push(url.origin);
    return route.abort();
  }
  return route.continue();
});
const snapshot = async () => page.locator('body').ariaSnapshot();
async function waitForAria(marker) {
  for (let attempt = 0; attempt < 120; attempt++) {
    if ((await snapshot()).includes(marker)) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`timed out waiting for visible marker: ${marker}`);
}
async function typeLoginCode(value) {
  const input = page.getByRole('textbox', { name: 'Einmalcode', exact: true });
  for (let attempt = 0; attempt < 100 && !(await input.isEditable()); attempt++) {
    await page.waitForTimeout(100);
  }
  await input.click({ force: true });
  // Flutter 3.22 deduplicates pointer/browser gestures; use its focused input.
  await input.evaluate((element) => element.blur());
  await page.waitForTimeout(650);
  await input.focus();
  await page.keyboard.type(value, { delay: 20 });
}
let fatal = null;
let session = null;
let bundleSha256 = null;
let bundleMatches = null;
const started = Date.now();
try {
  const response = await page.goto(base, { waitUntil: 'domcontentloaded' });
  check('application HTTP status', response?.status() === 200, response?.status());
  await page.getByRole('button', { name: 'Operator-Sitzung autorisieren', exact: true })
    .waitFor({ timeout: 120000 });
  const anonymous = await snapshot();
  check('anonymous real mode requires operator login', anonymous.includes('Lokale Operator-Anmeldung'));
  check('healthy anonymous API identifies the required login', anonymous.includes('ANMELDUNG ERFORDERLICH'));
  check('required login is not reported as a stale API', !anonymous.includes('API STALE / RECONNECT'));
  check('anonymous state never restores unified managed content', !anonymous.includes('UNIFIED INFRASTRUCTURE VIEW'));
  for (const marker of overviewForbidden) {
    check(`anonymous state has no legacy marker ${marker}`, !anonymous.includes(marker));
  }
  await page.screenshot({ path: `${outDir}/authentication-required.png` });
  screenshots.push(`${outDir}/authentication-required.png`);

  check('one-use login code supplied', !!code);
  await typeLoginCode(code);
  await page.getByRole('button', { name: 'Operator-Sitzung autorisieren', exact: true }).click();
  await waitForAria('Alle berechtigten Infrastrukturen');

  const sessionResponse = await context.request.get(base.replace(/\/$/, '') + '/api/v2/browser/session',
      { timeout: 60000 });
  check('browser session HTTP status', sessionResponse.status() === 200, sessionResponse.status());
  const rawSession = await sessionResponse.json();
  session = {
    authenticated: rawSession.authenticated,
    principal_id: rawSession.principal_id,
    mode: rawSession.mode,
  };
  check('browser session authenticated', session.authenticated === true);
  check('browser session uses managed local operator mode', session.mode === 'local_operator_session');
  check('browser session principal present', typeof session.principal_id === 'string' && session.principal_id.length > 0);

  const pair = await context.request.post(new URL('/api/v2/browser/pairing', base).href, {
    headers: { origin: new URL(base).origin, 'x-oip-csrf': rawSession.csrf_token },
    data: { credential: randomBytes(32).toString('hex') },
  });
  check('an isolated paired device is available for the settings check', pair.status() === 200, pair.status());

  // The web release is several megabytes and the loopback of a local
  // machine is slow. The download of the delivered bundle therefore gets
  // the same time as the first paint of the application.
  const bundleResponse = await context.request.get(base.replace(/\/$/, '') + '/main.dart.js',
      { timeout: 180000 });
  check('bundle HTTP status', bundleResponse.status() === 200, bundleResponse.status());
  const loaded = await bundleResponse.body();
  bundleSha256 = createHash('sha256').update(loaded).digest('hex');
  const onDiskPath = new URL('./../build/web/main.dart.js', import.meta.url);
  const onDisk = fs.existsSync(onDiskPath) ? fs.readFileSync(onDiskPath) : null;
  bundleMatches = onDisk ? createHash('sha256').update(onDisk).digest('hex') === bundleSha256 : null;
  check('served bundle equals local build', bundleMatches === true);

  const first = await snapshot();
  check('global infrastructure context selector', first.includes('Alle berechtigten Infrastrukturen'));
  for (const workstation of workstations) {
    check(`workstation navigation ${workstation.name}`, first.includes(`Navigation ${workstation.name}`));
  }
  check('authorized projection', first.includes('UNIFIED INFRASTRUCTURE VIEW'));
  check('honest unknown state', first.includes('Unknown ≠ Offline'));
  for (const marker of overviewForbidden) {
    check(`managed mode has no legacy marker ${marker}`, !first.includes(marker));
  }

  for (const width of [1440, 1920]) {
    const height = width === 1440 ? 900 : 1080;
    await page.setViewportSize({ width, height });
    for (const workstation of workstations) {
      // Flutter 3.22 deduplicates rapid pointer/browser gestures for 500 ms.
      // Keep module changes outside that window instead of weakening the marker.
      await page.waitForTimeout(650);
      await page.getByRole('button', { name: `Navigation ${workstation.name}`, exact: true }).click();
      await waitForAria(workstation.marker);
      const title = page.getByRole('heading', { name: workstation.name, exact: true });
      await title.waitFor();
      check(`one workstation title on ${workstation.slug} at ${width}px`,
        await title.count() === 1);
      const workstationSnapshot = await snapshot();
      check(`no shared footer on ${workstation.slug} at ${width}px`,
        !workstationSnapshot.includes('Reale Infrastruktur · lokale Operator-Sitzung') &&
        !workstationSnapshot.includes('Security-Blocker: an diese Sitzung nicht geliefert'));
      const logout = page.getByRole('button', { name: 'Operator abmelden', exact: true });
      check(`logout is exclusive to settings on ${workstation.slug} at ${width}px`,
        await logout.count() === (workstation.slug === 'settings' ? 1 : 0));
      if (workstation.slug === 'overview') {
        check(`no technical summary strips on overview at ${width}px`,
          !workstationSnapshot.includes('DATA TRUST') &&
          !workstationSnapshot.includes('TATSÄCHLICHER EMPFANG'));
      }
      if (workstation.slug === 'devices') {
        check(`no technical scope strip on devices at ${width}px`,
          !workstationSnapshot.includes('Autorisierter v2-Scope'));
      }
      const scopedForbidden = forbidden.filter((marker) =>
        !['M-01', 'Normalbetrieb'].includes(marker) &&
        (workstation.slug !== 'settings' || marker !== 'AGENT-FIRST'));
      for (const marker of scopedForbidden) {
        check(`no legacy marker ${marker} on ${workstation.slug}`,
          !workstationSnapshot.includes(marker));
      }
      // R6 permits the agent-first principle in the technical capability
      // context of the Settings workstation only. The exemption is therefore
      // asserted and not assumed: the principle is named there, and it is
      // nowhere else — the shell and the five other workstations carry no
      // trace of it.
      if (workstation.slug === 'opcua') {
        // The search of the address space belongs to the operator: every
        // character that is typed into it must arrive. A shortcut of the page
        // that matches a character swallows it — the operator lost every "c"
        // of the search.
        await page.keyboard.press('Control+k');
        await page.waitForTimeout(650);
        await page.keyboard.type('abc', { delay: 40 });
        await page.waitForTimeout(400);
        // The rendered field carries the text: the accessible name of the
        // field is its hint, the value is the text of the operator.
        const typed = /textbox "Nodes durchsuchen": abc/.test(await snapshot());
        check('the search of the address space keeps every character', typed, typed);
        await page.keyboard.press('Meta+A');
        await page.keyboard.press('Backspace');
        await page.waitForTimeout(300);
      }
      if (workstation.slug === 'settings') {
        check('the agent-first principle is named in the technical context of the settings',
          workstationSnapshot.includes('AGENT-FIRST'));
      } else {
        check(`no agent-first principle on ${workstation.slug}`,
          !workstationSnapshot.includes('AGENT-FIRST'));
      }
      const overflow = await page.evaluate(() => Math.max(
        document.documentElement.scrollWidth - window.innerWidth,
        document.body.scrollWidth - window.innerWidth,
      ));
      check(`document overflow ${workstation.slug} ${width}px`, overflow <= 0, overflow);
      const shot = workstation.slug === 'overview'
        ? `${outDir}/canonical-ui-${width}.png`
        : `${outDir}/canonical-ui-${workstation.slug}-${width}.png`;
      // The visual gate compares fixed viewport references (1440x900 and
      // 1920x1080), so do not extend screenshots to the document's scroll
      // height. Workspace content may be taller than the viewport.
      await page.screenshot({ path: shot, fullPage: false });
      screenshots.push(shot);
      findings.push({ check: `screenshot ${workstation.slug} ${width}px`, ok: true, detail: shot });
    }
  }
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Settings-Kategorie System', exact: true }).click();
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Settings-Bereich Versionen & Updates', exact: true }).click();
  await waitForAria('OIP · SPECTRUM 2027');
  check('current application identity in Settings', (await snapshot()).includes('OIP · SPECTRUM 2027'));
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Settings-Kategorie Security & Access' }).click();
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Settings-Bereich Aktuelle Identität' }).click();
  await waitForAria('Gespeicherte Geräteanmeldungen');
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Sperren', exact: true }).click();
  await waitForAria('Für eine erneute Einrichtung braucht es einen Einmalcode.');
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Anmeldung sperren', exact: true }).click();
  await waitForAria('Die Geräteanmeldung wurde gesperrt.');
  const cleared = await context.request.get(new URL('/api/v2/browser/device-credentials', base).href);
  const devices = await cleared.json();
  check('the served app revokes the selected sign-in',
    cleared.status() === 200 && devices.items.length === 0, cleared.status());

  const unexpectedDenials = coreDenials.filter((denial) =>
    ![401, 403].includes(denial.status) ||
    !/^\/api\/v[12]\//.test(new URL(denial.url).pathname));
  check('only expected Core authorization denials', unexpectedDenials.length === 0,
    JSON.stringify(unexpectedDenials));
  check('no external browser requests', external.length === 0, external.join(', '));
  check('no browser JavaScript errors', errors.length === 0, errors.join(' | '));
} catch (error) {
  fatal = error.message || String(error);
  try {
    const failureShot = `${outDir}/failure.png`;
    await page.screenshot({ path: failureShot, fullPage: true });
    screenshots.push(failureShot);
    fs.writeFileSync(`${outDir}/failure-aria.txt`, (await snapshot()).replace(/[a-f0-9]{64}/gi, 'REDACTED'));
  } catch (_) {
    // Preserve the original assertion failure even if diagnostic capture fails.
  }
} finally {
  const receipt = {
    verdict: fatal !== null || errors.length || external.length ? 'FAIL' : 'PASS',
    revision: process.env.OIP_REVISION || null,
    the_detail_is: 'the observed value of the check',
    base,
    browser_version: browser.version(),
    bundle_sha256: bundleSha256,
    bundle_matches_local_build: bundleMatches,
    workstations: workstations.map((item) => item.name),
    session,
    findings,
    screenshots,
    console_errors: errors,
    external_requests: external,
    core_denials: coreDenials,
    fatal,
    operator_visual_approval: 'VISUAL_PENDING_OPERATOR_ACCEPTANCE',
    duration_ms: Date.now() - started,
  };
  fs.writeFileSync(`${outDir}/browser-canonical-ui-gate.json`, JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify({
    verdict: receipt.verdict,
    bundle_sha256: bundleSha256,
    bundle_matches_local_build: bundleMatches,
    checks: findings.length,
    failed: findings.filter((item) => !item.ok).length,
    screenshots: screenshots.length,
    core_denials: coreDenials.length,
    console_errors: errors.length,
    external_requests: external.length,
    fatal,
  }, null, 2));
  await browser.close();
  process.exit(receipt.verdict === 'PASS' ? 0 : 1);
}

// The browser receipt of the diagnostic continuation (G6, G8).
//
// The persisted evidence of the diagnostics view is a page of the Core. The
// Core cuts a long answer off and hands a cursor for the continuation; a
// truncated answer without a cursor is explicitly incomplete and never
// implies that the evidence was read completely.
//
// The receipt proves against the real Core that
//
//   * the Core really truncates the page and hands a cursor;
//   * the surface shows the continuation and asks the same authorized route
//     with the opaque cursor of the Core;
//   * the two pages are disjoint: the continuation adds evidence and never
//     repeats a row;
//   * the continuation ends the page: the offer disappears when the evidence
//     is complete;
//   * the disclosed limits of the answer stay visible.
//
// The receipt records the answers of the Core as the browser received them,
// and the state of the surface as it was painted.
//
// Usage: node browser_diagnostic_continuation.mjs <baseUrl> <outDir> [loginCode]

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const base = process.argv[2] || process.env.OIP_URL;
const outDir = process.argv[3] || process.env.OIP_BROWSER_EVIDENCE;
let code = process.argv[4] || process.env.OIP_BROWSER_LOGIN_CODE;
if (!base || !outDir) {
  console.error('usage: browser_diagnostic_continuation.mjs <baseUrl> <outDir> [loginCode]');
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
const pages = [];
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

// Every answer of the Core for the diagnostic pages is recorded with the
// cursor that was asked for and the identity of every row it delivered.
const recordPage = async (response) => {
  const url = new URL(response.url());
  if (!/\/api\/v2\/diagnostics\/(gaps|health-history)/.test(url.pathname)) return;
  try {
    const payload = await response.json();
    const ids = (Array.isArray(payload.items) ? payload.items : []).map((item) => {
      const record = item && item.record ? item.record : item;
      return `${record && record.id ? record.id : ''}|${record && record.source ? record.source : ''}`;
    });
    pages.push({
      route: url.pathname.replace('/api/v2/diagnostics/', ''),
      cursor_asked: url.searchParams.get('cursor'),
      limit: url.searchParams.get('limit'),
      status: response.status(),
      items: ids.length,
      truncated: payload.truncated ?? null,
      next_cursor: payload.next_cursor ?? null,
      missing_evidence: payload.missing_evidence ?? [],
      time_semantics: (payload.time_semantics ?? '').length,
      ids,
    });
  } catch (_) { /* the body is optional */ }
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
page.on('response', recordPage);

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
  await page.waitForTimeout(1500);
};

// The evidence of the diagnostics view is at the bottom of the workstation.
// The semantics of the Flutter view carry only what is painted, so the
// surface is scrolled to the panel before it is read.
const scrollToBottom = async () => {
  await page.mouse.move(700, 600);
  for (let i = 0; i < 60; i++) {
    await page.mouse.wheel(0, 900);
    await page.waitForTimeout(100);
  }
  await page.waitForTimeout(1500);
};

// The text of the painted surface: the labels of the Flutter view are
// published as the text of the semantics node and as its accessible name.
const surfaceText = async () => await page.evaluate(() => {
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

const countRows = (text, marker) => text.split('\n')
  .filter((line) => line.includes(marker) && line.trim().length < 400);

// The rows of the evidence that are painted in the viewport: the gaps come
// first, the health transitions after them.
const visibleEvidence = (text) => ({
  gaps: countRows(text, 'Dokumentierte Lücke ·').length,
  transitions: countRows(text, 'Gesundheitsverlauf ·').length,
});

const gapContinuation = () => page.getByRole('button', { name: /Lücken: weitere Einträge laden/ }).count();
const healthContinuation = () => page.getByRole('button', { name: /Gesundheitsverlauf: weitere Einträge laden/ }).count();

// The evidence is continued until the Core has no more of it: the offer
// disappears only when the last page is reached.
const continueUntilComplete = async (kind) => {
  const label = kind === 'gaps' ? 'Lücken: weitere Einträge laden'
    : 'Gesundheitsverlauf: weitere Einträge laden';
  const offers = kind === 'gaps' ? gapContinuation : healthContinuation;
  let rounds = 0;
  while ((await offers()) > 0 && rounds < 12) {
    await clickText(label);
    await page.waitForTimeout(2500);
    await scrollToBottom();
    rounds += 1;
  }
  return rounds;
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

// The diagnostics workstation of the approved shell.
await page.getByRole('button', { name: 'Navigation Diagnose & Ereignisse' }).click({ force: true });
await page.waitForTimeout(4000);
await scrollToBottom();

// The Core truncated the page and handed a cursor.
const firstGapPage = pages.find((item) => item.route === 'gaps');
check('the Core answered the diagnostic page', !!firstGapPage && firstGapPage.status === 200,
  JSON.stringify(firstGapPage && { items: firstGapPage.items, truncated: firstGapPage.truncated }));
check('the Core truncated the page of the gaps', !!firstGapPage && firstGapPage.truncated === true,
  JSON.stringify(firstGapPage && { items: firstGapPage.items, truncated: firstGapPage.truncated }));
check('the Core handed a cursor for the continuation',
  !!firstGapPage && !!firstGapPage.next_cursor, JSON.stringify(firstGapPage && firstGapPage.next_cursor));

// The surface shows the continuation.
check('the surface offers the continuation of the gaps', (await gapContinuation()) > 0,
  `${await gapContinuation()} buttons`);
check('the surface offers the continuation of the health history',
  (await healthContinuation()) > 0, `${await healthContinuation()} buttons`);
await page.screenshot({ path: `${outDir}/diagnostic-continuation.png` });

const before = await surfaceText();
const visibleBefore = visibleEvidence(before);
check('the evidence is painted for the operator',
  visibleBefore.gaps + visibleBefore.transitions > 0, JSON.stringify(visibleBefore));

// The continuation asks the same authorized route with the cursor of the Core.
const gapRounds = await continueUntilComplete('gaps');
check('the gaps were continued', gapRounds >= 1, `${gapRounds} rounds`);
const gapPages = pages.filter((item) => item.route === 'gaps');
const secondGapPage = gapPages.find((item) => item.cursor_asked);
check('the continuation asked the Core with the opaque cursor', !!secondGapPage,
  JSON.stringify(gapPages.map((item) => ({ cursor: item.cursor_asked, items: item.items }))));
if (secondGapPage) {
  const first = new Set(firstGapPage.ids);
  const overlap = secondGapPage.ids.filter((id) => first.has(id));
  check('the continuation repeats no row of the first page', overlap.length === 0,
    `${overlap.length} repeated rows of ${secondGapPage.items}`);
  check('the continuation adds the next page', secondGapPage.items > 0,
    `${secondGapPage.items} rows`);
  const lastGapPage = gapPages[gapPages.length - 1];
  check('the last page of the gaps is not truncated', lastGapPage.truncated === false,
    JSON.stringify({ truncated: lastGapPage.truncated, items: lastGapPage.items }));
}

// The offer disappears when the evidence is complete.
check('the offer of the gaps is gone after the continuation', (await gapContinuation()) === 0,
  `${await gapContinuation()} buttons`);

// The health history is continued the same way.
const healthRounds = await continueUntilComplete('health-history');
check('the health history was continued', healthRounds >= 1, `${healthRounds} rounds`);
const healthPages = pages.filter((item) => item.route === 'health-history');
const secondHealthPage = healthPages.find((item) => item.cursor_asked);
check('the health history is continued with the cursor of the Core', !!secondHealthPage,
  JSON.stringify(healthPages.map((item) => ({ cursor: item.cursor_asked, items: item.items }))));
check('the offer of the health history is gone after the continuation',
  (await healthContinuation()) === 0, `${await healthContinuation()} buttons`);
const lastHealthPage = healthPages[healthPages.length - 1];
check('the last page of the health history is not truncated', lastHealthPage.truncated === false,
  JSON.stringify({ truncated: lastHealthPage.truncated, items: lastHealthPage.items }));

// The evidence stays visible and the limits of the answer stay disclosed.
const after = await surfaceText();
const visibleAfter = visibleEvidence(after);
check('the evidence stays visible after the continuation',
  visibleAfter.gaps + visibleAfter.transitions > 0, JSON.stringify(visibleAfter));
check('no failure of the evidence is shown',
  !after.includes('Persistierte Evidenz nicht verfügbar'), 'the surface shows a failure');
check('the limits of the evidence stay disclosed',
  /Grenzen dieser Evidenz|keine Fortsetzung|weitere Einträge laden|kein Nachweis einer lückenlosen/i.test(after),
  'the limits of the answer are not shown');

await page.screenshot({ path: `${outDir}/diagnostic-continuation-after.png` });

const receipt = {
  schema: 'oip-diagnostic-continuation-v1',
  revision: process.env.OIP_REVISION || null,
  scope: 'the diagnostic continuation of the approved surface against the real Core',
  base,
  gaps: {
    first_page_items: firstGapPage ? firstGapPage.items : null,
    first_page_truncated: firstGapPage ? firstGapPage.truncated : null,
    continuation_items: secondGapPage ? secondGapPage.items : null,
    continuation_rounds: gapRounds,
    total_rows: (firstGapPage ? firstGapPage.items : 0) + (secondGapPage ? secondGapPage.items : 0),
    distinct_rows: new Set([...(firstGapPage ? firstGapPage.ids : []), ...(secondGapPage ? secondGapPage.ids : [])]).size,
  },
  health: {
    pages: healthPages.map((item) => ({ cursor_asked: item.cursor_asked, items: item.items, truncated: item.truncated })),
  },
  visible_in_the_viewport: { before: visibleBefore, after: visibleAfter },
  core_pages: pages.map((item) => ({ ...item, ids: item.ids.length })),
  checks: findings,
  errors,
};
fs.writeFileSync(`${outDir}/diagnostic-continuation.json`, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({
  gaps: receipt.gaps,
  visible_in_the_viewport: receipt.visible_in_the_viewport,
  checks: findings.length,
  errors: errors.length,
}, null, 2));
await browser.close();
process.exit(errors.length === 0 ? 0 : 1);

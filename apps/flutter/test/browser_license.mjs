import assert from 'node:assert/strict';
import fs from 'node:fs';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const [base, proof, screenshot, mode = 'import'] = process.argv.slice(2);
const artifact = fs.readFileSync(proof, 'utf8');
const { payload } = JSON.parse(artifact);
const { license_id: licenseId, holder, revision } = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
const code = fs.readFileSync(0, 'utf8').trim();
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
try {
  const context = await browser.newContext({ locale: 'de-DE', viewport: { width: 1440, height: 900 } });
  const login = await context.request.post(base + '/api/v2/browser/login', {
    data: { code },
    headers: { origin: new URL(base).origin },
  });
  assert.equal(login.status(), 200);
  const path = base + '/api/v2/license';
  const before = await (await context.request.get(path)).json();
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    return ['http:', 'https:'].includes(url.protocol) && url.origin !== new URL(base).origin
      ? route.abort() : route.continue();
  });
  const page = await context.newPage();
  await page.goto(base, { waitUntil: 'domcontentloaded' });
  await page.getByRole('button', { name: 'Navigation Einstellungen' })
    .click({ timeout: 120000, force: true });
  await page.getByRole('button', { name: 'Settings-Kategorie System' }).click();
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'Settings-Bereich Versionen & Updates' }).click();
  if (mode === 'suspended') {
    assert.equal(before.proof_state, 'suspended');
    assert.equal(before.can_manage, false);
    const body = page.locator('body');
    const deadline = Date.now() + 60000;
    let panel = await body.ariaSnapshot();
    while (!panel.includes('Lizenzprüfung ausgesetzt') && Date.now() < deadline) {
      await page.waitForTimeout(250);
      panel = await body.ariaSnapshot();
    }
    assert.match(panel, /Lizenzprüfung ausgesetzt/);
    assert.equal(await page.getByRole('button', { name: 'Lizenznachweis hinterlegen' }).count(), 0);
    await page.screenshot({ path: screenshot });
  } else if (mode === 'import') {
    await verifyImport(page, context, path, before);
  } else {
    assert.equal(mode, 'superseded');
    assert.equal(before.license_id, licenseId);
    assert.ok(before.revision > revision);
    const refused = await selectProof(page, path);
    assert.equal(refused.status(), 400);
    assert.equal((await refused.json()).code, 'LICENSE_PROOF_SUPERSEDED');
    const body = page.locator('body');
    const message = 'Für diese Lizenz ist bereits eine neuere Fassung gespeichert. Wähle die aktuelle Lizenzdatei.';
    const deadline = Date.now() + 15000;
    let panel = await body.ariaSnapshot();
    while (!panel.includes(message) && Date.now() < deadline) {
      await page.waitForTimeout(250);
      panel = await body.ariaSnapshot();
    }
    await page.screenshot({ path: screenshot });
    assert.ok(panel.includes(message), panel);
    assert.ok(panel.includes(`Fassung ${before.revision} `), panel);
    assert.equal(await page.getByRole('button', { name: 'Nachweis übernehmen' }).count(), 0);
    assert.deepEqual(await (await context.request.get(path)).json(), before);
  }
} finally {
  await browser.close();
}

async function selectProof(page, path) {
  await page.getByRole('button', { name: 'Lizenznachweis hinterlegen' }).click();
  const fileButton = page.getByRole('button', { name: 'Lizenzdatei auswählen' });
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), fileButton.click()]);
  const [response] = await Promise.all([
    page.waitForResponse((response) => response.url() === path + '/preview'),
    chooser.setFiles(proof),
  ]);
  assert.deepEqual(response.request().postDataJSON(), { proof: { artifact } });
  return response;
}

async function verifyImport(page, context, path, before) {
  const verified = await selectProof(page, path);
  assert.equal(verified.status(), 200);
  const confirm = page.getByRole('button', { name: 'Nachweis übernehmen' });
  await confirm.waitFor();
  const preview = await page.locator('body').ariaSnapshot();
  assert.match(preview, /Geprüfter Nachweis zur Übernahme/);
  assert.match(preview, /Gewerbliche Nutzung/);
  assert.match(preview, /Supportberechtigung/);
  assert.ok(preview.includes(licenseId));
  assert.deepEqual(await (await context.request.get(path)).json(), before);
  const [applied] = await Promise.all([
    page.waitForResponse((response) => response.url() === path + '/apply'),
    confirm.click(),
  ]);
  assert.equal(applied.status(), 200);
  const status = await (await context.request.get(path)).json();
  assert.equal(status.license_id, licenseId);
  assert.equal(status.licensee, holder.name);
  assert.equal(status.revision, revision);
  assert.equal(status.commercial, 'active');
  assert.equal(status.support, 'ended');
  await page.getByRole('button', { name: 'Lizenznachweis hinterlegen' }).waitFor();
  await page.screenshot({ path: screenshot });
  const saved = await page.locator('body').ariaSnapshot();
  assert.match(saved, /Nachweis geprüft/);
  assert.ok(saved.includes(licenseId));
}

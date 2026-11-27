import assert from 'node:assert/strict';
import fs from 'node:fs';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const [base, proof, screenshot, mode = 'import'] = process.argv.slice(2);
const artifact = fs.readFileSync(proof, 'utf8');
const { payload } = JSON.parse(artifact);
const { license_id: licenseId, holder } = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
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
    await page.getByRole('button', { name: 'Status aktualisieren' }).waitFor();
    const panel = await page.locator('body').ariaSnapshot();
    assert.match(panel, /Lizenzprüfung ausgesetzt/);
    assert.equal(await page.getByRole('button', { name: 'Lizenznachweis hinterlegen' }).count(), 0);
    await page.screenshot({ path: screenshot });
  } else {
    assert.equal(mode, 'import');
    await verifyImport(page, context, path, before);
  }
} finally {
  await browser.close();
}

async function verifyImport(page, context, path, before) {
  await page.getByRole('button', { name: 'Lizenznachweis hinterlegen' }).click();
  const fileButton = page.getByRole('button', { name: 'Lizenzdatei auswählen' });
  const [chooser] = await Promise.all([page.waitForEvent('filechooser'), fileButton.click()]);
  const [submitted] = await Promise.all([
    page.waitForRequest((request) => request.url() === path + '/preview'),
    chooser.setFiles(proof),
  ]);
  assert.deepEqual(submitted.postDataJSON(), { proof: { artifact } });
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
  assert.equal(status.commercial, 'active');
  assert.equal(status.support, 'ended');
  await page.getByRole('button', { name: 'Lizenznachweis hinterlegen' }).waitFor();
  await page.screenshot({ path: screenshot });
  const saved = await page.locator('body').ariaSnapshot();
  assert.match(saved, /Nachweis geprüft/);
  assert.ok(saved.includes(licenseId));
}

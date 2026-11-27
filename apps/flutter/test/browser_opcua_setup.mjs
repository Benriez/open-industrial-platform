import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const [base, screenshot] = process.argv.slice(2);
const fixture = JSON.parse(fs.readFileSync(0, 'utf8'));
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
let page;
try {
  const context = await browser.newContext({
    locale: 'de-DE', viewport: { width: 1440, height: 900 },
  });
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    return ['http:', 'https:'].includes(url.protocol) && url.origin !== base
      ? route.abort() : route.continue();
  });
  page = await context.newPage();
  page.setDefaultTimeout(15000);
  page.on('pageerror', (error) => console.error(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') console.error(message.text());
  });
  page.on('requestfailed', (request) =>
    console.error(request.failure()?.errorText, new URL(request.url()).pathname));
  page.on('response', (response) => {
    if (response.status() >= 400) console.error(response.status(), new URL(response.url()).pathname);
  });
  const launch = await page.goto(base, { waitUntil: 'domcontentloaded' });
  assert.equal(launch.status(), 200);
  const signIn = page.getByRole('button', { name: 'Operator-Sitzung autorisieren', exact: true });
  await signIn.waitFor({ timeout: 120000 });
  const loginCode = page.getByRole('textbox', { name: 'Einmalcode', exact: true });
  await loginCode.click({ force: true });
  await loginCode.evaluate((element) => element.blur());
  await page.waitForTimeout(650);
  await loginCode.focus();
  await page.keyboard.type(fixture.code, { delay: 20 });
  const [login] = await Promise.all([
    page.waitForResponse((response) => response.url() === base + '/api/v2/browser/login'),
    signIn.click(),
  ]);
  assert.equal(login.status(), 200);
  const navigation = page.getByRole('button', { name: 'Navigation OPC-UA-Browser', exact: true });
  await navigation.waitFor({ timeout: 90000 });
  await page.waitForTimeout(650);
  await navigation.click();
  await page.waitForTimeout(650);
  await page.getByRole('button', { name: 'OPC-UA einrichten', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByText('Gerät und Standort').click();
  await page.getByText(/^Prüfmaschine ·/).last().click();

  async function input(label, value) {
    const field = dialog.getByRole('textbox', { name: new RegExp('^' + label + '( |$)') });
    await page.waitForTimeout(650);
    await field.click({ force: true });
    await field.evaluate((element) => element.blur());
    await page.waitForTimeout(650);
    await field.focus();
    await page.keyboard.press('Meta+A');
    await page.keyboard.type(value, { delay: 5 });
  }
  await input('OPC-UA-Adresse', fixture.endpoint);
  await input('Server-Anwendungs-URI', fixture.server_application_uri);
  await input('Namensraum-URI', fixture.namespace_uri);
  await input('Abfrageintervall in Sekunden', String(fixture.poll_seconds));
  await input('Datenpunkt-Bezeichner', 'temperature');
  await input('Node-Kennung ohne Namensraumindex', 's=Temperature');
  await page.waitForTimeout(650);
  const [chooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    dialog.getByRole('button', { name: 'Zertifikatsdatei auswählen' }).click(),
  ]);
  await chooser.setFiles(fixture.certificate);
  await page.waitForTimeout(650);

  const setup = base + '/api/v2/opcua/setup';
  async function action(label, operation) {
    await page.waitForTimeout(650);
    const [response] = await Promise.all([
      page.waitForResponse((response) => response.url() === setup &&
        response.request().postDataJSON()?.operation.action === operation),
      dialog.getByRole('button', { name: label }).click(),
    ]);
    assert.equal(response.status(), 200, await response.text());
    return response.json();
  }
  const preview = await action('Zertifikat prüfen', 'preview');
  assert.equal(preview.certificate.sha256, fixture.sha256);
  await input('Unabhängig geprüfter SHA-256-Fingerabdruck', fixture.sha256);
  const saved = await action('Zertifikat freigeben', 'apply');
  assert.equal(saved.server_sha256, fixture.sha256);
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    dialog.getByRole('button', { name: 'Öffentliches Clientzertifikat speichern' }).click(),
  ]);
  assert.equal(download.suggestedFilename(), 'oip-opcua-client.pem');
  assert.equal(fs.readFileSync(await download.path(), 'utf8'), saved.client_certificate_pem);
  await page.screenshot({ path: screenshot });
  await dialog.getByRole('button', { name: 'Schließen' }).click();
  const bundle = await context.request.get(base + '/main.dart.js', { timeout: 180000 });
  assert.equal(bundle.status(), 200);
  assert.equal(createHash('sha256').update(await bundle.body()).digest('hex'), fixture.bundleSha256);
} catch (error) {
  if (page) {
    await page.screenshot({ path: screenshot.replace(/\.png$/, '.failure.png') });
    console.error((await page.locator('body').ariaSnapshot()).slice(-5000));
  }
  throw error;
} finally {
  await browser.close();
}

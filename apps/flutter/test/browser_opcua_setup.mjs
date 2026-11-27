import assert from 'node:assert/strict';
import fs from 'node:fs';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const [base, screenshot] = process.argv.slice(2);
const fixture = JSON.parse(fs.readFileSync(0, 'utf8'));
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
try {
  const context = await browser.newContext({
    locale: 'de-DE', viewport: { width: 1440, height: 900 },
  });
  const login = await context.request.post(base + '/api/v2/browser/login', {
    data: { code: fixture.code }, headers: { origin: base },
  });
  assert.equal(login.status(), 200);
  await context.route('**/*', (route) => {
    const url = new URL(route.request().url());
    return ['http:', 'https:'].includes(url.protocol) && url.origin !== base
      ? route.abort() : route.continue();
  });
  const page = await context.newPage();
  await page.goto(base, { waitUntil: 'domcontentloaded' });
  await page.getByRole('button', { name: 'Navigation OPC-UA-Browser' })
    .click({ timeout: 120000, force: true });
  await page.getByRole('button', { name: 'OPC-UA einrichten' }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByText('Gerät und Standort').click();
  await page.getByText(/^Prüfmaschine ·/).last().click();

  async function input(label, value) {
    await dialog.getByRole('textbox', { name: label, exact: true }).fill(value);
  }
  await input('OPC-UA-Adresse', fixture.endpoint);
  await input('Server-Anwendungs-URI', fixture.server_application_uri);
  await input('Namensraum-URI', fixture.namespace_uri);
  await input('Abfrageintervall in Sekunden', String(fixture.poll_seconds));
  await input('Datenpunkt-Bezeichner', 'temperature');
  await input('Node-Kennung ohne Namensraumindex', 's=Temperature');
  const [chooser] = await Promise.all([
    page.waitForEvent('filechooser'),
    dialog.getByRole('button', { name: 'Zertifikatsdatei auswählen' }).click(),
  ]);
  await chooser.setFiles(fixture.certificate);

  const setup = base + '/api/v2/opcua/setup';
  async function action(label, operation) {
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
} finally {
  await browser.close();
}

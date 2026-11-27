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
const context = await browser.newContext({
  locale: 'de-DE', viewport: { width: 1440, height: 900 },
});
await context.route('**/*', (route) => {
  const url = new URL(route.request().url());
  return ['http:', 'https:'].includes(url.protocol) && url.origin !== base
    ? route.abort() : route.continue();
});
const page = await context.newPage();
page.setDefaultTimeout(20000);

async function input(dialog, label, value) {
  const field = dialog.getByRole('textbox', { name: new RegExp('^' + label + '( |$)') });
  await field.click({ force: true });
  await field.evaluate((element) => element.blur());
  await page.waitForTimeout(450);
  await field.focus();
  await page.keyboard.type(value, { delay: 20 });
}

try {
  await page.goto(base, { waitUntil: 'domcontentloaded' });
  const signIn = page.getByRole('button', { name: 'Operator-Sitzung autorisieren', exact: true });
  await signIn.waitFor({ timeout: 120000 });
  await input(page, 'Einmalcode', fixture.code);
  await signIn.click();
  const navigation = page.getByRole('button', { name: 'Navigation OPC-UA-Browser', exact: true });
  await navigation.waitFor({ timeout: 90000 });
  await navigation.click();
  await page.getByRole('button', { name: 'OPC-UA einrichten', exact: true }).click();
  const opcua = page.getByRole('dialog');
  await opcua.getByRole('button', { name: 'OPC-UA-Gerät registrieren', exact: true }).click();

  // The nested Flutter Dialog may be represented by its contents rather than a
  // second dialog role depending on the canvas semantics bridge.
  await page.getByRole('button', { name: 'Neue Organisation', exact: true }).click();
  await input(page, 'Name der Organisation', 'Pruefbetrieb');
  await input(page, 'Name der Infrastruktur', 'Halle A');
  await input(page, 'Name des ersten Standorts', 'Pruefstand A');
  const [created] = await Promise.all([
    page.waitForResponse((response) => response.url() === base + '/api/v2/organizations/setup' &&
      response.request().postDataJSON()?.action === 'create'),
    page.getByRole('button', { name: 'Organisation erstellen', exact: true }).click(),
  ]);
  assert.equal(created.status(), 200);
  const placement = await created.json();
  for (const label of ['Pruefbetrieb', 'Halle A', 'Pruefstand A']) {
    await page.getByText(label, { exact: true }).last().waitFor({ state: 'visible' });
  }
  await page.screenshot({ path: screenshot.replace(/\.png$/, '-selected.png') });
  await input(page, 'Anzeigename', 'Prüfmaschine');
  await page.getByRole('button', { name: 'Registrierung prüfen', exact: true }).click();
  await page.getByText('Ich bestätige die reine Inventarregistrierung ohne Verbindung.', { exact: true }).click();
  const [registered, setup] = await Promise.all([
    page.waitForResponse((response) => response.url() === base + '/api/v2/inventory/apply'),
    page.waitForResponse((response) => response.url() === base + '/api/v2/opcua/setup' &&
      response.request().postDataJSON()?.operation.action === 'status'),
    page.getByRole('button', { name: 'Nur im Inventar registrieren', exact: true }).click(),
  ]);
  assert.equal(registered.status(), 200);
  assert.equal(setup.status(), 200);
  assert.equal(registered.request().postDataJSON().changes[0].device.site_id, placement.site_id);
  assert.equal(setup.request().postDataJSON().site, placement.site_id);
  assert.equal(setup.request().postDataJSON().device, registered.request().postDataJSON().changes[0].device.id);
  await opcua.getByRole('textbox', { name: /^OPC-UA-Adresse/ }).waitFor();
  await page.screenshot({ path: screenshot });
  const served = await context.request.get(base + '/main.dart.js', { timeout: 180000 });
  assert.equal(served.status(), 200);
  assert.equal(createHash('sha256').update(await served.body()).digest('hex'), fixture.bundleSha256);
} catch (error) {
  await page.screenshot({ path: screenshot.replace(/\.png$/, '.failure.png') });
  console.error((await page.locator('body').ariaSnapshot()).slice(-6000));
  throw error;
} finally {
  await browser.close();
}

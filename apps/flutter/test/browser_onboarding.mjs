// Actual Flutter -> authenticated HTTP -> owned daemon -> real loopback SSH.
// No mocked network responses and no private Raspberry-Pi endpoint.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {writeFile, mkdir, readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE);
const base=process.env.OIP_URL, out=process.env.OIP_BROWSER_EVIDENCE;
await mkdir(out,{recursive:true});
const fixture=JSON.parse(await readFile(process.env.OIP_SSH_FIXTURE,'utf8'));
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1100}});
const page=await context.newPage();
const errors=[],external=[],sshRequests=[];
page.on('request',r=>{if(r.url().endsWith('/api/v2/device-connections')&&r.method()==='POST'){sshRequests.push(r.postDataJSON());}});
page.on('pageerror',e=>errors.push(e.message));
await context.route('**/*',r=>{
  const u=new URL(r.request().url());
  if(u.protocol.startsWith('http') && u.origin!==base){external.push(u.origin);return r.abort();}
  return r.continue();
});
async function typeInto(locator, text) { for(let n=0;!(await locator.isEditable());n++){if(n===100)throw Error('Field did not become editable');await page.waitForTimeout(100);} await locator.click({force:true}); await page.waitForTimeout(250); await page.keyboard.press('Meta+A'); await page.waitForTimeout(80); await page.keyboard.press('Backspace'); await page.waitForTimeout(120); await page.keyboard.type(text,{delay:100}); await page.waitForTimeout(150); await page.keyboard.press('Tab'); await page.waitForTimeout(100); }
const capture=async name=>page.screenshot({path:resolve(out,name+'.png')});
try {
  await page.goto(base);
  await page.waitForTimeout(3000);
  await writeFile(resolve(out,'initial-dom.html'),await page.content());
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).waitFor({timeout:45000});
  await capture('01-authentication-required');
  const result=JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,['--browser-login','--ipc-socket',process.env.OIP_IPC_SOCKET,'--ipc-credential',process.env.OIP_BROWSER_CREDENTIAL],{encoding:'utf8'}));
  await typeInto(page.getByRole('textbox',{name:'Einmalcode'}),result.login_code);
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).click();
  await page.getByRole('button',{name:'Navigation Geräte & Dienste',exact:true}).click();
  await page.getByRole('button',{name:'Gerät hinzufügen',exact:true}).waitFor();
  // The Add Device action must also make the inventory-only distinction real.
  await page.getByRole('button',{name:'Gerät hinzufügen',exact:true}).click();
  const nameInput=page.getByRole('textbox',{name:'Anzeigename',exact:true});
  await nameInput.click({force:true});
  // Flutter 3.22 deduplicates pointer/browser gestures for 500ms. Focus
  // through its accessibility input only after that window; no controller injection.
  await nameInput.evaluate(e=>e.blur());
  await page.waitForTimeout(650);
  await nameInput.focus();
  await page.waitForTimeout(250);
  await page.keyboard.type('Manual inventory fixture',{delay:100});
  await page.waitForTimeout(300);
  await capture('01b-manual-name');
  await page.getByRole('button',{name:'Verbindungsmethode wählen',exact:true}).click();
  await page.getByRole('button',{name:/Verbindungsmethode SSH/}).click();
  await page.getByText('Nur Inventar, keine Verbindung',{exact:true}).last().click();
  await page.getByRole('button',{name:'Inventarregistrierung prüfen',exact:true}).click();
  await page.getByRole('checkbox',{name:'Ich bestätige die reine Inventarregistrierung ohne Verbindung.',exact:true}).click();
  await page.getByRole('button',{name:'Nur im Inventar registrieren',exact:true}).click();
  await page.getByRole('button',{name:'Zum Geräteinventar',exact:true}).click();
  const manualPage=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture')).json();
  assert.equal(manualPage.items.length,1);assert.equal(manualPage.items[0].telemetry,'no_collector');assert.equal(manualPage.items[0].connectivity,'unknown');assert.equal(manualPage.items[0].health,'not_evaluated');
  const row=page.getByRole('button',{name:/Details Browser SSH fixture/});
  await row.click();
  await page.getByRole('button',{name:'Verbindung für dieses Gerät einrichten',exact:true}).click();
  await page.getByRole('button',{name:'Verbindungsmethode wählen',exact:true}).click();
  await typeInto(page.getByRole('textbox',{name:'Hostname oder IP-Adresse',exact:true}),'127.0.0.1');
  await typeInto(page.getByRole('textbox',{name:'SSH-Port',exact:true}),String(fixture.port));
  // Port's Tab advances real Flutter focus to the user field; do not refocus its semantic-only DOM proxy.
  await page.keyboard.type(fixture.user,{delay:100});
  await page.waitForTimeout(200); await page.keyboard.press('Tab');
  await capture('02-explicit-endpoint');
  console.log('endpoint input complete');
  await page.getByRole('button',{name:'SSH-Verbindung testen',exact:true}).click();
  const trust=page.getByRole('button',{name:'Fingerprint geprüft · diesem Host-Key vertrauen',exact:true});
  await trust.waitFor({timeout:30000});
  console.log('host key shown');
  const expectedFingerprint=execFileSync('/usr/bin/ssh-keygen',['-lf',resolve(fixture.directory,'host.pub'),'-E','sha256'],{encoding:'utf8'}).split(/\s+/)[1];
  assert((await page.locator('body').ariaSnapshot()).includes(expectedFingerprint));
  await capture('03-host-key-confirmation');
  // Fixture host key was created by this isolated test, independently known.
  await trust.click();
  await page.getByRole('button',{name:'Identität bestätigen und Verbindung speichern',exact:true}).waitFor({timeout:30000});
  await writeFile(resolve(out,'verified-ax.txt'),await page.locator('body').ariaSnapshot());
  await capture('04-actual-host-identity');
  await page.getByRole('checkbox',{name:'Diese ermittelte Identität gehört zum ausgewählten Gerät.',exact:true}).click();
  await page.getByRole('button',{name:'Identität bestätigen und Verbindung speichern',exact:true}).click();
  await page.getByRole('button',{name:'Zum Geräteinventar',exact:true}).waitFor();
  await capture('05-persisted-binding');
  await page.getByRole('button',{name:'Monitoring aktivieren',exact:true}).click();
  await page.getByRole('button',{name:'Zum Geräteinventar',exact:true}).click();
  for(let i=0;i<140;i++){ if((await page.locator('body').ariaSnapshot()).includes('Collecting · aktuelle Messwerte empfangen'))break; if(i===139)throw Error('No rendered actual Collecting state'); await page.waitForTimeout(250); }
  await capture('06-real-monitoring');
  // The panel must show the measurements the Core actually received over SSH.
  // The expected values are read back from the Core, never invented here, and
  // they must be the same values that the operator sees in the browser.
  const observed=(await (await context.request.get(base+'/api/v2/device-connections?device_id=browser-existing')).json());
  const observations=observed.connection.observations;
  assert(Array.isArray(observations)&&observations.length>0,'Core reports no authorized observations');
  const os=observations.find(o=>o.metric_id==='host.os');
  const memory=observations.find(o=>o.metric_id==='host.memory_total_bytes');
  assert(os&&typeof os.value.text==='string'&&os.value.text.length>0,'no host operating system observation');
  assert(memory&&memory.value.unsigned_integer>0,'no real memory observation');
  assert.equal(os.freshness,'fresh');
  let rendered='';
  for(let i=0;i<60;i++){ rendered=await page.locator('body').ariaSnapshot(); if(rendered.includes('host.os')&&rendered.includes(os.value.text)&&rendered.includes('host.memory_total_bytes')&&rendered.includes(String(memory.value.unsigned_integer)))break; if(i===59)throw Error('The rendered panel does not show the collected measurements'); await page.waitForTimeout(250); }
  assert(rendered.includes(os.value.text));
  assert(rendered.includes(String(memory.value.unsigned_integer)));
  const cookies=await context.cookies();assert(cookies.some(c=>c.name==='oip_session'&&c.httpOnly&&c.sameSite==='Strict'));
  assert.equal(await page.evaluate(()=>localStorage.length),0);
  assert.equal(await page.evaluate(()=>sessionStorage.length),0);
  const loaded=Buffer.from(await (await context.request.get(base+'/main.dart.js')).body());
  const local=await readFile(resolve(process.env.OIP_WEB_DIR,'main.dart.js'));
  assert.equal(createHash('sha256').update(loaded).digest('hex'),createHash('sha256').update(local).digest('hex'));
  await page.getByRole('button',{name:'Details schließen',exact:true}).click();
  await page.getByRole('button',{name:'Operator abmelden',exact:true}).click();
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).waitFor();
  assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
  await writeFile(resolve(out,'report.json'),JSON.stringify({status:'PASS',actual_flutter_ssh_monitoring:true,hardware:'owned loopback SSH fixture, not private Raspberry Pi',host_key_consent:true,identity_confirmation:true,existing_device_id_preserved:true,http_only_cookie:true,no_browser_token_storage:true,rendered_measurements:{observed_metrics:observations.map(o=>o.metric_id),host_os:os.value.text,memory_total_bytes:memory.value.unsigned_integer,all_fresh:observations.every(o=>o.freshness==='fresh')},loaded_build_sha256:createHash('sha256').update(loaded).digest('hex'),errors,external},null,2));
} catch(e) {
  await writeFile(resolve(out,'ssh-requests.json'),JSON.stringify(sshRequests,null,2));
  await capture('failure');
  await writeFile(resolve(out,'failure-dom.html'),(await page.content()).replace(/[a-f0-9]{64}/gi,'REDACTED'));
  await writeFile(resolve(out,'failure-ax.txt'),(await page.locator('body').ariaSnapshot()).replace(/[a-f0-9]{64}/gi,'REDACTED'));
  await writeFile(resolve(out,'failure.json'),JSON.stringify({status:'FAIL',error:String(e),errors,external},null,2));throw e;
} finally {await browser.close();}

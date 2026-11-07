const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir,writeFile,rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const base = process.env.OIP_URL ?? 'http://127.0.0.1:28080';
const testDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(testDir,'../../..');
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? resolve(repoRoot,'docs/evidence/oip0061/browser'));
await mkdir(out,{recursive:true});
const systemChrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath=process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined);
const browser = await chromium.launch({executablePath,headless:true});
const context = await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1});
const page = await context.newPage();
// HTML regression build exposes both AX proxy text and painted paragraphs.
// Require painted/visible text, avoiding ambiguous duplicate matches.
function text(...args){return page.getByText(...args).filter({visible:true}).first();}
const errors=[]; const failedResources=[]; const external=[]; const checks=[]; const timings={};
let expectedOffline = false;
page.on('response',r=>{if(r.status()>=400 && !failedResources.includes(r.url())) {failedResources.push(r.url());console.log('HTTP',r.status(),r.url());}});
page.on('pageerror',e=>errors.push(e.message));
page.on('console',m=>{if(m.type()==='error' && !expectedOffline) errors.push(m.text());});
await context.route('**/*',route=>{
  const url=new URL(route.request().url());
  if(url.protocol.startsWith('http') && url.origin!==new URL(base).origin) { external.push(url.href); return route.abort(); }
  return route.continue();
});
async function poll(fn,label,timeout=35000) {
  const start=Date.now();
  while(Date.now()-start<timeout) { if(await fn()) { checks.push(label); console.log('PASS',label); return; } await new Promise(r=>setTimeout(r,150)); }
  throw new Error(`Timeout: ${label}`);
}
async function api(path) {const r=await context.request.get(base+path); assert.equal(r.status(),200);return r.json();}
async function scenario(name) {const r=await context.request.post(base+'/api/v1/demo/scenario',{data:{scenario:name}});assert.equal(r.status(),200);}
async function nav(label) {
  const menu=page.getByRole('button',{name:/Navigation öffnen/});
  const narrow=await menu.count()>0;
  const group=text('Dismiss',{exact:true});
  if(narrow) {
    await group.waitFor({state:'hidden'});
    await menu.click();
    await group.waitFor({state:'visible'});
  }
  await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();
  if(narrow) await group.waitFor({state:'hidden'});
}

async function typeInto(locator,text) { await locator.click(); await locator.press('Meta+A'); await locator.press('Backspace'); if(text) await locator.pressSequentially(text,{delay:70}); }
async function capture(name) {await page.screenshot({path:resolve(out,name+'.png')});}
try {
  await poll(async()=>{try {await api('/api/v1/system/status');return true;} catch {return false;}},'Backend ready');
  await scenario('normal');
  const inventory=await api('/api/v1/devices');
  const inventoryTotal=inventory.length;
  const amdCount=inventory.filter(device=>device.name.includes('AMD')).length;
  const tailnetCount=inventory.filter(device=>device.location==='Tailnet').length;
  const start=Date.now();
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await text('Deine Infrastruktur. Ein Bild.',{exact:true}).waitFor({timeout:45000});
  await text('LIVE · API',{exact:false}).waitFor({timeout:15000});
  timings.firstLiveMs=Date.now()-start;
  await poll(async()=>/Temperaturverlauf, [2-9]/.test(await page.locator('body').innerText()),'Multiple sensor samples rendered via SSE');
  await capture('overview-desktop');
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  await capture('overview-light');
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  checks.push('Spectrum, Daylight and Graphite theme selection'); console.log('THEME PASS');
  await nav('Geräte & Dienste');
  const search=page.getByRole('textbox',{name:'Geräte durchsuchen'});
  await typeInto(search,'AMD');
  await text(`${amdCount} von ${inventoryTotal} Geräten · Simuliertes Inventar`,{exact:true}).waitFor();
  await page.getByRole('button',{name:/Details AMD EVO-X2/}).click();
  await text('Fünf unabhängige Statusdimensionen',{exact:true}).waitFor();
  await capture('device-detail');
  await page.getByRole('button',{name:/Details schließen/}).click();
  await typeInto(search,'does-not-exist');
  await text('Keine Geräte gefunden',{exact:true}).waitFor();
  await typeInto(search,'');
  await text('Standort: Alle',{exact:true}).click();
  await text('Standort: Tailnet',{exact:true}).last().click();
  await text(`${tailnetCount} von ${inventoryTotal} Geräten · Simuliertes Inventar`,{exact:true}).waitFor();
  await text('Standort: Tailnet',{exact:true}).click();
  await text('Standort: Alle',{exact:true}).last().click();
  await text('Sortieren: Name',{exact:true}).click();
  await text('Sortieren: Standort',{exact:true}).last().click();
  await text(`${inventoryTotal} von ${inventoryTotal} Geräten · Simuliertes Inventar`,{exact:true}).waitFor();
  checks.push('Device search, filters, sorting, empty state, detail dialog, close');
  await capture('devices-desktop');
  await nav('Netzwerk & VPN');
  await text('Verbindungspfade',{exact:true}).waitFor();
  await capture('network-desktop');
  await page.getByRole('button',{name:/Remote-Linux-Server/}).first().click();
  await text('Device Reachability',{exact:true}).first().waitFor();
  await page.getByRole('button',{name:/Details schließen/}).click();
  checks.push('Interactive topology opens device health dimensions');
  await nav('OPC-UA-Browser');
  await text('Namespace 2',{exact:true}).waitFor();
  await text('temperature Double',{exact:true}).click();
  await text('SourceTimestamp · virtuelle Quellzeit',{exact:true}).waitFor();
  await capture('opcua-process');
  await text('Bulk',{exact:true}).first().click();
  const bulkPage=await api('/api/v1/opcua/nodes?q=&folder=Bulk&offset=0&limit=40');
  const bulkTotal=bulkPage.total;
  await text(`${bulkTotal} Nodes · Seite 1`,{exact:true}).waitFor();
  const nodeStart=Date.now();
  await page.getByRole('button',{name:'Nächste Nodes',exact:true}).click();
  await text(`${bulkTotal} Nodes · Seite 2`,{exact:true}).waitFor();
  timings.nodePageMs=Date.now()-nodeStart;
  await typeInto(page.getByRole('textbox',{name:'Nodes durchsuchen'}),'bulk.0999');
  await text('1 Nodes · Seite 1',{exact:true}).waitFor();
  await capture('opcua-bulk');
  checks.push(`${bulkTotal} actual browsed bulk nodes, pagination, search and typed read`);
  await nav('Diagnose & Ereignisse');
  await text('Sensoralarm',{exact:true}).click();
  const sensorStart=Date.now();
  await poll(async()=> (await api('/api/v1/metrics/current')).some(o=>o.metric_id==='temperature' && o.value?.float>90),'Real simulator sensor alarm reaches persisted API');
  await nav('Übersicht');
  await poll(async()=>/9[5-9]\.\d °C/.test(await page.locator('body').innerText()),'Sensor alarm reaches visible Flutter metric via SSE');
  timings.sensorToUiMs=Date.now()-sensorStart;
  await capture('sensor-alarm-live');
  await nav('Diagnose & Ereignisse');
  await capture('diagnostics-sensor');
  for(const [key,label,title] of [['gpu','Hohe GPU-Last','Hohe GPU-Auslastung'],['inference','Langsame Inferenz','Langsame lokale Inferenz'],['vpn','VPN-Störung','Instabile VPN-Verbindung'],['agent','Remote-Agent fehlt','VPN erreichbar · Agent nicht verfügbar']]) {
    await text(label,{exact:true}).click();
    await text(title,{exact:true}).waitFor();
    const payload=await api('/api/v1/events');
    const incident=payload.incidents.find(item=>item.title===title);
    assert.ok(incident,`Incident payload for ${key}`);
    for(const panel of ['Unterstützende Evidenz','Widersprechende Evidenz','Fehlende Messwerte']) {
      await text(panel,{exact:true}).waitFor();
    }
    for(const evidence of [...incident.supporting,...incident.contradicting,...incident.missing]) {
      await text(evidence,{exact:true}).waitFor();
    }
    assert.equal((await api('/api/v1/system/status')).scenario,key);
  }
  await capture('diagnostics-agent');
  checks.push('All deterministic diagnoses retain support, contradiction and missing evidence');
  await text('Offline & Reconnect',{exact:true}).click();
  await nav('Übersicht');
  await text(/VERALTET \/ UNBEKANNT/).waitFor({timeout:15000});
  await capture('collector-offline');
  await poll(async()=> (await api('/api/v1/system/status')).opcua_status==='connected','Collector reconnect after real simulator socket stop');
  await poll(async()=>await text(/VERALTET \/ UNBEKANNT/).count()===0,'Freshness restored after simulator recovery');
  await scenario('normal');
  expectedOffline=true;
  await context.setOffline(true);
  await text(/OIP-Server nicht erreichbar/).waitFor({timeout:15000});
  await capture('browser-offline');
  await context.setOffline(false);
  await poll(async()=> (await text(/OIP-Server nicht erreichbar/).count())===0,'Browser network reconnect clears stale error');
  expectedOffline=false;
  await text('LIVE · API',{exact:false}).waitFor();
  await capture('reconnected');
  await context.route('**/api/v1/stream',route=>route.fulfill({
    status:200,
    contentType:'text/event-stream',
    body:'event: error\ndata: storage unavailable\n\n'
  }));
  await page.evaluate(()=>window.dispatchEvent(new Event('offline')));
  await text(/API-Endpunkt \/api\/v1\/stream: Live-Daten vorübergehend nicht verfügbar\. \(SSE_ERROR\)/).waitFor({timeout:15000});
  checks.push('Web named SSE error event enters stale reconnect state');
  console.log('SSE ERROR EVENT PASS');
  await context.unroute('**/api/v1/stream');
  await text('LIVE · API',{exact:false}).waitFor({timeout:15000});
  for(const [name,width,height] of [['tablet',834,1112],['mobile',390,844],['narrow',320,740]]) {
    await page.setViewportSize({width,height});
    await capture('overview-'+name);
    for(const label of ['Geräte & Dienste','Netzwerk & VPN','OPC-UA-Browser','Diagnose & Ereignisse','Übersicht']) {
      await nav(label);
      const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
      assert.equal(overflow,false,`${name} ${label} document overflow`);
      await capture(`${name}-${label.startsWith('OPC')?'opcua':label.startsWith('Netz')?'network':label.startsWith('Geräte')?'devices':label.startsWith('Diagnose')?'diagnostics':'overview'}`);
    }
    checks.push(`All five pages navigable at ${width}x${height}`);
  }
  assert.deepEqual(external,[], 'No external runtime requests');
  assert.deepEqual(failedResources,[], 'No HTTP error responses');
  assert.deepEqual(errors,[], 'No unexpected browser errors');
  await rm(resolve(out,'browser-failure.json'),{force:true});
  await rm(resolve(out,'failure.png'),{force:true});
  const status=await api('/api/v1/system/status');
  const metrics=await api('/api/v1/metrics/current');
  await writeFile(resolve(out,'browser-verification.json'),JSON.stringify({verdict:'PASS',browser:await browser.version(),checks,timings,status,metrics,externalRequests:external,errors},null,2));
  console.log(JSON.stringify({verdict:'PASS',checks,timings},null,2));
} catch(e) {
  await capture('failure');
  await writeFile(resolve(out,'browser-failure.json'),JSON.stringify({error:String(e),checks,errors,external,failedResources,body:(await page.locator('body').innerText()).slice(0,14000)},null,2));
  throw e;
} finally {await context.setOffline(false).catch(()=>{});await browser.close();}

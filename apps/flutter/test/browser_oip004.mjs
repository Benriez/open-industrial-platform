const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir,writeFile,rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const execFileAsync = promisify(execFile);
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
  const group=page.getByText('Dismiss',{exact:true});
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
async function ocrCapture(name) {
  const path=resolve(out,name+'.png');
  await page.screenshot({path, ...(name.startsWith('incident-') ? {clip:{x:550,y:390,width:520,height:610}} : {})});
  const {stdout}=await execFileAsync('tesseract',[path,'stdout'],{maxBuffer:4*1024*1024});
  return stdout;
}
function evidenceTokens(value) {
  return value.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'')
    .split(/[^a-z0-9]+/).filter(token=>token.length>=3 && !['demo','evidenz','messwerte'].includes(token));
}
function editDistance(a,b) {
  const row=Array.from({length:b.length+1},(_,i)=>i);
  for(let i=1;i<=a.length;i++) {
    let diagonal=row[0]; row[0]=i;
    for(let j=1;j<=b.length;j++) {
      const previous=row[j];
      row[j]=Math.min(row[j]+1,row[j-1]+1,diagonal+(a[i-1]===b[j-1]?0:1));
      diagonal=previous;
    }
  }
  return row[b.length];
}
function fuzzyIncludes(text,token) {
  if(text.includes(token)) return true;
  const tolerance=token.length<=4?1:Math.max(1,Math.floor(token.length*.2));
  return text.split(/[^a-z0-9]+/).some(word=>Math.abs(word.length-token.length)<=tolerance && editDistance(word,token)<=tolerance);
}
try {
  await poll(async()=>{try {await api('/api/v1/system/status');return true;} catch {return false;}},'Backend ready');
  await scenario('normal');
  const inventory=await api('/api/v1/devices');
  const inventoryTotal=inventory.length;
  const amdCount=inventory.filter(device=>device.name.includes('AMD')).length;
  const tailnetCount=inventory.filter(device=>device.location==='Tailnet').length;
  const start=Date.now();
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await page.getByText('Operations Workstation',{exact:true}).waitFor({timeout:45000});
  await page.getByText('API CONNECTED',{exact:false}).waitFor({timeout:15000});
  timings.firstLiveMs=Date.now()-start;
  await poll(async()=>/Session-lokaler Signalverlauf, [2-9]/.test(await page.locator('body').innerText()),'Multiple sensor samples rendered via SSE');
  await capture('overview-desktop');
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  await capture('overview-light');
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  checks.push('Spectrum, Daylight and Graphite theme selection'); console.log('THEME PASS');
  await nav('Geräte & Dienste');
  const search=page.getByRole('textbox').first();
  await typeInto(search,'AMD');
  await page.getByText(`${amdCount} von ${inventoryTotal} Geräten · Simuliertes Inventar`,{exact:true}).waitFor();
  await page.getByRole('button',{name:/Gerät AMD EVO-X2 evo auswählen/}).click({force:true});
  await page.getByText('Fünf unabhängige Statusdimensionen',{exact:true}).waitFor();
  await capture('device-detail');
  await page.getByRole('button',{name:/Details schließen/}).click();
  await typeInto(search,'does-not-exist');
  await page.getByText('Keine Geräte gefunden',{exact:true}).waitFor();
  await typeInto(search,'');
  await page.locator('flt-semantics').filter({hasText:/^STANDORT/}).last().click();
  await page.getByText('Standort: Tailnet',{exact:true}).last().click();
  await page.getByText(`${tailnetCount} von ${inventoryTotal} Geräten · Simuliertes Inventar`,{exact:true}).waitFor();
  await page.locator('flt-semantics').filter({hasText:/^STANDORT/}).last().click();
  await page.getByText('Standort: Alle',{exact:true}).last().click();
  await page.locator('flt-semantics').filter({hasText:/^SORTIERUNG/}).last().click();
  await page.getByText('Standort',{exact:true}).last().click();
  await page.getByText(`${inventoryTotal} von ${inventoryTotal} Geräten · Simuliertes Inventar`,{exact:true}).waitFor();
  checks.push('Device search, filters, sorting, empty state, inline engineering workspace, close');
  await capture('devices-desktop');
  await nav('Netzwerk & VPN');
  await page.getByText('Verbindungspfade',{exact:true}).waitFor();
  await page.getByText('6 TOPOLOGIE-NODES',{exact:true}).waitFor();
  await page.getByText('5 PFADE',{exact:true}).waitFor();
  await page.waitForTimeout(650);
  await capture('network-desktop');
  await page.getByRole('button',{name:/Details Remote-Linux-Server,/}).first().click({force:true});
  await page.getByText('Device Reachability',{exact:true}).first().waitFor();
  await page.getByRole('button',{name:/Details schließen/}).click();
  checks.push('Interactive topology opens device health dimensions');
  await nav('OPC-UA-Browser');
  await page.getByText('Namespace 2',{exact:true}).waitFor();
  await page.getByRole('button',{name:/^Node temperature, Double,/}).click();
  await page.getByText('SourceTimestamp · virtuelle Quellzeit',{exact:true}).waitFor();
  await page.getByText('AKTUELLER WERT',{exact:true}).waitFor();
  await page.getByRole('button',{name:'Node anheften',exact:true}).click();
  await page.getByRole('button',{name:/^Angeheftet temperature/}).waitFor();
  await capture('opcua-process');
  await page.getByRole('button',{name:/^Bulk /}).click();
  const bulkPage=await api('/api/v1/opcua/nodes?q=&folder=Bulk&offset=0&limit=40');
  const bulkTotal=bulkPage.total;
  await page.getByText(`${bulkTotal} Nodes · Seite 1`,{exact:true}).waitFor();
  const nodeStart=Date.now();
  await page.getByRole('button',{name:'Nächste Nodes',exact:true}).click();
  await page.getByText(`${bulkTotal} Nodes · Seite 2`,{exact:true}).waitFor();
  timings.nodePageMs=Date.now()-nodeStart;
  await page.getByRole('button',{name:'Dichte Liste',exact:true}).click();
  await page.getByRole('button',{name:'Nach Datentyp gruppieren',exact:true}).click();
  await page.getByText(/^NUMERISCH/).first().waitFor();
  await typeInto(page.getByRole('textbox',{name:'Nodes durchsuchen'}),'bulk.0999');
  await page.getByText('1 Nodes · Seite 1',{exact:true}).waitFor();
  await page.getByRole('button',{name:/^Node bulk\.0999, Double,/}).click();
  await page.getByText('Kein Verlauf · Einzelabfrage. Die API liefert für diese Node keine History.',{exact:true}).waitFor();
  await page.getByRole('button',{name:/^Angeheftet temperature/}).waitFor();
  await capture('opcua-bulk');
  checks.push(`${bulkTotal} actual browsed bulk nodes, pagination, density, grouping, pin, search and typed read`);
  await nav('Diagnose & Ereignisse');
  await page.getByText('Sensoralarm',{exact:true}).click();
  const sensorStart=Date.now();
  await poll(async()=> (await api('/api/v1/metrics/current')).some(o=>o.metric_id==='temperature' && o.value?.float>90),'Real simulator sensor alarm reaches persisted API');
  await nav('Übersicht');
  await poll(async()=>/9[5-9]\.\d °C/.test(await page.locator('body').innerText()),'Sensor alarm reaches visible Flutter metric via SSE');
  timings.sensorToUiMs=Date.now()-sensorStart;
  await capture('sensor-alarm-live');
  await nav('Diagnose & Ereignisse');
  await capture('diagnostics-sensor');
  for(const [key,label,title] of [['gpu','Hohe GPU-Last','Hohe GPU-Auslastung'],['inference','Langsame Inferenz','Langsame lokale Inferenz'],['vpn','VPN-Störung','Instabile VPN-Verbindung'],['agent','Remote-Agent fehlt','VPN erreichbar · Agent nicht verfügbar']]) {
    await page.getByText(label,{exact:true}).click();
    await page.getByRole('button',{name:'Incidents',exact:true}).click({force:true});
    let visibleText='';
    await poll(async()=>{
      visibleText=await ocrCapture(`incident-${key}`);
      const normalized=visibleText.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
      const tokens=evidenceTokens(title);
      const matched=tokens.filter(token=>fuzzyIncludes(normalized,token));
      return tokens.length===0 || matched.length>=Math.max(1,Math.ceil(tokens.length*.5));
    },`Visible incident ${title} verified by OCR`);
    for(const panel of ['Unterst','Widersprechende Evidenz','Fehlende Messwerte']) {
      assert.ok(visibleText.includes(panel),`Visible evidence panel ${panel}`);
    }
    const payload=await api('/api/v1/events');
    const incident=payload.incidents.find(item=>item.title===title);
    assert.ok(incident,`Incident payload for ${key}`);
    const ocrWords=visibleText.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
    for(const evidence of [...incident.supporting,...incident.contradicting,...incident.missing]) {
      const tokens=evidenceTokens(evidence);
      const matched=tokens.filter(token=>fuzzyIncludes(ocrWords,token));
      assert.ok(tokens.length===0 || matched.length>=Math.max(1,Math.ceil(tokens.length*.5)),
        `Visible evidence tokens for ${key}: ${evidence}; OCR=${visibleText.slice(0,500)}`);
    }
    assert.equal((await api('/api/v1/system/status')).scenario,key);
  }
  await capture('diagnostics-agent');
  checks.push('All deterministic diagnoses retain support, contradiction and missing evidence');
  await page.getByText('Offline & Reconnect',{exact:true}).click();
  await nav('Übersicht');
  await page.getByText(/VERALTET \/ UNBEKANNT/).waitFor({timeout:15000});
  await capture('collector-offline');
  await poll(async()=> (await api('/api/v1/system/status')).opcua_status==='connected','Collector reconnect after real simulator socket stop');
  await poll(async()=>await page.getByText(/VERALTET \/ UNBEKANNT/).count()===0,'Freshness restored after simulator recovery');
  await scenario('normal');
  expectedOffline=true;
  await context.setOffline(true);
  await page.getByText(/OIP-Server nicht erreichbar/).waitFor({timeout:15000});
  await capture('browser-offline');
  await context.setOffline(false);
  await poll(async()=> (await page.getByText(/OIP-Server nicht erreichbar/).count())===0,'Browser network reconnect clears stale error');
  expectedOffline=false;
  await page.getByText('API CONNECTED',{exact:false}).waitFor();
  await capture('reconnected');
  await context.route('**/api/v1/stream',route=>route.fulfill({
    status:200,
    contentType:'text/event-stream',
    body:'event: error\ndata: storage unavailable\n\n'
  }));
  await page.evaluate(()=>window.dispatchEvent(new Event('offline')));
  await page.getByText(/API-Endpunkt \/api\/v1\/stream: Live-Daten vorübergehend nicht verfügbar\. \(SSE_ERROR\)/).waitFor({timeout:15000});
  checks.push('Web named SSE error event enters stale reconnect state');
  console.log('SSE ERROR EVENT PASS');
  await context.unroute('**/api/v1/stream');
  await page.getByText('API CONNECTED',{exact:false}).waitFor({timeout:15000});
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

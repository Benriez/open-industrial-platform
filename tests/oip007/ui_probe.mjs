// Actual unchanged Flutter client against the persistent daemon. No fixture API.
import {chromium} from '../../apps/flutter/test/node_modules/playwright/index.mjs';
import {createInterface} from 'node:readline';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const [base,out]=process.argv.slice(2);await mkdir(out,{recursive:true});
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH??'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const context=await browser.newContext({viewport:{width:1440,height:1000},serviceWorkers:'block'});
const external=[];await context.route('**/*',r=>{const u=new URL(r.request().url());if(u.protocol.startsWith('http')&&u.origin!==base){external.push(u.href);return r.abort();}return r.continue();});
let page=await context.newPage();let seq=0;
const nav=label=>page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();
async function capture(name){await page.screenshot({path:resolve(out,name+'.png')});}
async function open(){await page.goto(base,{waitUntil:'domcontentloaded'});await page.getByText('SPECTRUM',{exact:true}).waitFor();await page.getByText('LIVE · API',{exact:false}).waitFor();}
try {
 await open();const bytes=Buffer.from(await (await fetch(base+'/main.dart.js')).arrayBuffer());const local=await readFile(resolve('apps/flutter/build/web/main.dart.js'));assert.equal(createHash('sha256').update(bytes).digest('hex'),createHash('sha256').update(local).digest('hex'));
 for(const [label,text]of [['Geräte & Dienste','2 von 2 Geräten · Simuliertes Inventar'],['Netzwerk & VPN','Verbindungspfade'],['OPC-UA-Browser','Namespace 2'],['Diagnose & Ereignisse','Collection-Ereignisse']]) {await nav(label);await page.getByText(text,{exact:true}).first().waitFor();}
 await nav('Übersicht');await capture('daemon-spectrum-live');
 console.log(JSON.stringify({ready:true,main_sha256:createHash('sha256').update(bytes).digest('hex'),views:5}));
 for await(const line of createInterface({input:process.stdin})) {
  const cmd=JSON.parse(line);let result={};
  if(cmd.op==='close') break;
  if(cmd.op==='connected') {await nav('Übersicht');await page.getByText('LIVE · API',{exact:false}).waitFor();await capture('clients-'+(++seq)+'-core-live');result={api_live:true};}
  else if(cmd.op==='offline') {
   await nav('Geräte & Dienste');await page.getByRole('button',{name:/Details Simulation A/}).click();await page.getByText('Veraltet',{exact:true}).first().waitFor();await capture('source-a-stale');await page.getByRole('button',{name:/Details schließen/}).click();
   await page.getByRole('button',{name:/Details Simulation B/}).click();await page.getByText('Aktuell',{exact:true}).first().waitFor();await capture('source-b-fresh');await page.getByRole('button',{name:/Details schließen/}).click();
   await nav('Übersicht');await page.getByRole('button',{name:/Detail-Inspector manuell öffnen/}).click();await page.getByText(/Core-Zustand: Degradiert/).first().waitFor();await capture('core-degraded-live-api');result={a_stale:true,b_fresh:true,core_degraded:true};
  } else if(cmd.op==='alarm') {await nav('Übersicht');await page.getByText('95.0 °C',{exact:true}).waitFor();await capture('sensor-alarm');result={alarm:true};}
  else if(cmd.op==='stale') {await nav('Übersicht');await page.getByText(/VERALTET \/ UNBEKANNT/).waitFor({timeout:15000});await capture('daemon-restored-stale');result={restore_stale:true};}
  else if(cmd.op==='browser_reconnect') {await context.close();const fresh=await browser.newContext({viewport:{width:1440,height:1000},serviceWorkers:'block'});page=await fresh.newPage();await open();result={new_flutter_connection:true};}
  else throw Error('unsupported UI probe op');
  assert.equal(external.length,0);console.log(JSON.stringify({ok:true,...result}));
 }
 await writeFile(resolve(out,'report.json'),JSON.stringify({verdict:'PASS',externalRequests:external,main_sha256:createHash('sha256').update(bytes).digest('hex')},null,2));
} finally {await browser.close();process.stdin.destroy();console.log(JSON.stringify({closed:true}));}

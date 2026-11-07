const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const base=process.env.OIP_URL ?? 'http://127.0.0.1:18736';
const testDir=dirname(fileURLToPath(import.meta.url));
const out=resolve(process.env.OIP_EVIDENCE_DIR ?? resolve(testDir,'../../../docs/evidence/oip0061/interactions'));
await mkdir(out,{recursive:true});
const systemChrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH ?? (existsSync(systemChrome)?systemChrome:undefined),headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1});
const page=await context.newPage();
// HTML regression build exposes both AX proxy text and painted paragraphs.
// Require painted/visible text, avoiding ambiguous duplicate matches.
function text(...args){return page.getByText(...args).filter({visible:true}).first();}
const errors=[];const external=[];const checks=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
await context.route('**/*',route=>{
  const url=new URL(route.request().url());
  if(url.protocol.startsWith('http') && url.origin!==new URL(base).origin){external.push(url.href);return route.abort();}
  return route.continue();
});
async function capture(name){await page.screenshot({path:resolve(out,name+'.png')});}
async function nav(label){
  const menu=page.getByRole('button',{name:/Navigation öffnen/});
  if(await menu.count())await menu.click();
  await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();
}
try{
  const ready=await context.request.post(base+'/api/v1/demo/scenario',{data:{scenario:'normal'}});
  assert.equal(ready.status(),200);
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await text('Deine Infrastruktur. Ein Bild.',{exact:true}).waitFor({timeout:45000});
  await text('LIVE · API',{exact:false}).waitFor();
  await text('ERFASSTE GERÄTE',{exact:true}).hover();
  await capture('spectrum-hover-overview');
  for(let i=0;i<7;i++)await page.keyboard.press('Tab');
  await capture('spectrum-keyboard-focus');
  checks.push('Hover and keyboard focus captures');

  await nav('Netzwerk & VPN');
  const remote=page.getByRole('button',{name:/Details Remote-Linux-Server/});
  await remote.hover();
  await remote.waitFor();
  assert.match(await remote.innerText(),/Telemetrie: Unbekannt/);
  await capture('spectrum-network-tooltip');
  checks.push('Topology tooltip preserves separate freshness text');

  await nav('Diagnose & Ereignisse');
  const clip=page.getByRole('button',{name:/Telemetry:/}).first();
  await clip.waitFor();
  await clip.click();
  await text('COLLECTION EVENT · KEINE KAUSALBEHAUPTUNG',{exact:true}).waitFor();
  await capture('spectrum-diagnostics-timeline-inspector');
  await text('Spuren ausblenden',{exact:true}).click();
  await text('Klassische Ereignisliste aktiv',{exact:true}).waitFor();
  await text('Collection-Ereignisse',{exact:true}).waitFor();
  await text('Spuren zeigen',{exact:true}).click();
  checks.push('Real event timeline selection, inspector and list fallback');

  await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await text('DAYLIGHT',{exact:true}).waitFor();
  await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await text('GRAPHITE',{exact:true}).waitFor();
  await nav('Übersicht');
  await capture('spectrum-graphite-overview');
  await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await text('SPECTRUM',{exact:true}).waitFor();
  checks.push('Spectrum, Daylight and Graphite browser switching');

  assert.deepEqual(external,[]);
  assert.deepEqual(errors,[]);
  await writeFile(resolve(out,'spectrum-interactions.json'),JSON.stringify({verdict:'PASS',browser:await browser.version(),checks,errors,externalRequests:external},null,2));
  console.log(JSON.stringify({verdict:'PASS',checks},null,2));
}catch(error){
  await capture('spectrum-interaction-failure').catch(()=>{});
  await writeFile(resolve(out,'spectrum-interactions-failure.json'),JSON.stringify({verdict:'FAIL',error:String(error),checks,errors,external},null,2));
  throw error;
}finally{await browser.close();}

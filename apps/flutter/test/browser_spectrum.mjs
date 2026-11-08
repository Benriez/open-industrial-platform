const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const execFileAsync=promisify(execFile);

const base=process.env.OIP_URL ?? 'http://127.0.0.1:18736';
const testDir=dirname(fileURLToPath(import.meta.url));
const out=resolve(process.env.OIP_EVIDENCE_DIR ?? resolve(testDir,'../../../docs/evidence/oip0061/interactions'));
await mkdir(out,{recursive:true});
const systemChrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH ?? (existsSync(systemChrome)?systemChrome:undefined),headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1});
const page=await context.newPage();
const errors=[];const external=[];const checks=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
await context.route('**/*',route=>{
  const url=new URL(route.request().url());
  if(url.protocol.startsWith('http') && url.origin!==new URL(base).origin){external.push(url.href);return route.abort();}
  return route.continue();
});
async function capture(name){await page.screenshot({path:resolve(out,name+'.png')});}
async function ocrCapture(name){
  const path=resolve(out,name+'.png');
  await page.screenshot({path});
  const {stdout}=await execFileAsync('tesseract',[path,'stdout'],{maxBuffer:4*1024*1024});
  return stdout;
}
async function nav(label){
  const menu=page.getByRole('button',{name:/Navigation öffnen/});
  if(await menu.count())await menu.click();
  await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();
}
try{
  const ready=await context.request.post(base+'/api/v1/demo/scenario',{data:{scenario:'normal'}});
  assert.equal(ready.status(),200);
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await page.getByText('Operations Workstation',{exact:true}).waitFor({timeout:45000});
  await page.getByText('API CONNECTED',{exact:false}).waitFor();
  await page.getByText('OPERATIONAL FOCUS · SESSION TELEMETRY',{exact:true}).hover();
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
  for(let i=0;i<3;i++) await page.getByRole('button',{name:'Timeline vergrößern',exact:true}).click();
  const event=page.getByRole('button',{name:/^Ereignis .*Record/}).first();
  await event.waitFor();
  await event.click({force:true});
  let inspectorText='';
  for(let attempt=0;attempt<20;attempt++) {
    inspectorText=await ocrCapture('spectrum-diagnostics-timeline-inspector');
    if(inspectorText.includes('COLLECTION EVENT') && inspectorText.includes('KAUSALBEHAUPTUNG')) break;
    await page.waitForTimeout(250);
  }
  assert.ok(inspectorText.includes('COLLECTION EVENT') && inspectorText.includes('KAUSALBEHAUPTUNG'),
    'Visible Evidence Inspector verified by OCR');
  await page.getByText('Spuren ausblenden',{exact:true}).click();
  const fallbackText=await ocrCapture('spectrum-diagnostics-list-fallback');
  assert.ok(fallbackText.includes('Klassische Erei') && fallbackText.includes('Collection-Ereignisse'),
    'Visible list fallback verified by OCR');
  await page.getByText('Spuren zeigen',{exact:true}).click();
  checks.push('Real shared Explorer/Inspector selection, timeline zoom and list fallback');

  await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await page.getByText('DAYLIGHT',{exact:true}).waitFor();
  await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await page.getByText('GRAPHITE',{exact:true}).waitFor();
  await nav('Übersicht');
  await capture('spectrum-graphite-overview');
  await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await page.getByText('SPECTRUM',{exact:true}).waitFor();
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

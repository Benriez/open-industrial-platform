const {chromium} = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
import {mkdir,writeFile,rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const base = process.env.OIP_URL ?? 'http://127.0.0.1:28080';
const testDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(testDir,'../../..');
const out = resolve(process.env.OIP_EVIDENCE_DIR ?? resolve(repoRoot,'docs/evidence/oip0061/visual'));
await mkdir(out,{recursive:true});
for(const file of ['responsive-verification.json','browser-performance.json','browser-visual-failure.json','visual-failure.png']) {
  await rm(resolve(out,file),{force:true});
}
const systemChrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath=process.env.CHROME_PATH ?? (existsSync(systemChrome) ? systemChrome : undefined);
const browser = await chromium.launch({executablePath,headless:true});
const context = await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1});
const page = await context.newPage();
const errors=[]; const external=[]; const captures=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{if(message.type()==='error') errors.push(message.text());});
await context.route('**/*',route=>{
  const url=new URL(route.request().url());
  if(url.protocol.startsWith('http') && url.origin!==new URL(base).origin) {
    external.push(url.href);
    return route.abort();
  }
  return route.continue();
});

const views = [
  {label:'Übersicht',slug:'overview',marker:'Operations Workstation'},
  {label:'Geräte & Dienste',slug:'devices',marker:'DEVICES & SERVICES · ENGINEERING WORKSTATION'},
  {label:'Netzwerk & VPN',slug:'network',marker:'Logische Topologie'},
  {label:'OPC-UA-Browser',slug:'opcua',marker:'Namespace 2'},
  {label:'Diagnose & Ereignisse',slug:'diagnostics',marker:'Deterministische Regeln · keine KI und keine unbelegte Kausalität'}
];
async function nav(label,marker) {
  const menu=page.getByRole('button',{name:/Navigation öffnen/});
  const narrow=await menu.count()>0;
  if(narrow) {
    await menu.click();
    await page.getByText('Dismiss',{exact:true}).waitFor({state:'visible'});
  }
  await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();
  if(narrow) await page.getByText('Dismiss',{exact:true}).waitFor({state:'hidden'});
  await page.getByText(marker,{exact:true})
    .or(page.locator(`flt-semantics[aria-label*="${marker}"]`)).first().waitFor();
  await page.waitForTimeout(250);
}
async function capture(slug,width,mode) {
  const name=`${slug}-${width}-${mode}.png`;
  await page.screenshot({path:resolve(out,name)});
  const documentOverflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
  assert.equal(documentOverflow,false,`${name} document overflow`);
  captures.push({file:name,width,mode,documentOverflow});
}

try {
  const ready=await context.request.post(base+'/api/v1/demo/scenario',{data:{scenario:'normal'}});
  assert.equal(ready.status(),200);
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await page.getByText('Operations Workstation',{exact:true}).waitFor({timeout:45000});
  await page.getByText('API CONNECTED',{exact:false}).waitFor({timeout:15000});

  for(const [width,height] of [[1920,1080],[1440,1000],[1024,900],[768,1024],[375,812]]) {
    await page.setViewportSize({width,height});
    await page.waitForTimeout(300);
    for(const view of views) {
      console.log('CAPTURE',width,'dark',view.slug);
      await nav(view.label,view.marker);
      await capture(view.slug,width,'dark');
    }
  }

  await page.setViewportSize({width:1440,height:1000});
  await page.waitForTimeout(300);
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  for(const view of views) {
    await nav(view.label,view.marker);
    await capture(view.slug,1440,'light');
  }
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  await page.getByRole('button',{name:/Darstellung wechseln/}).click({force:true});
  await page.getByText('SPECTRUM',{exact:true}).waitFor();
  await nav('Übersicht','Operations Workstation');

  const performanceResult=await page.evaluate(async()=>{
    const longTasks=[];
    let observer;
    try {
      observer=new PerformanceObserver(list=>{
        for(const entry of list.getEntries()) longTasks.push({start:entry.startTime,duration:entry.duration});
      });
      observer.observe({entryTypes:['longtask']});
    } catch {}
    const deltas=[];
    const start=performance.now();
    let previous=start;
    await new Promise(resolveFrame=>{
      function frame(now) {
        deltas.push(now-previous);
        previous=now;
        if(now-start>=8000) resolveFrame();
        else requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    });
    observer?.disconnect();
    deltas.shift();
    const sorted=[...deltas].sort((a,b)=>a-b);
    const percentile=p=>sorted[Math.min(sorted.length-1,Math.floor(sorted.length*p))];
    return {
      durationMs:previous-start,
      frames:deltas.length,
      medianFrameMs:percentile(.5),
      p95FrameMs:percentile(.95),
      maxFrameMs:Math.max(...deltas),
      longTasks,
      jsHeap:performance.memory ? {used:performance.memory.usedJSHeapSize,total:performance.memory.totalJSHeapSize} : null
    };
  });
  const body=await page.locator('body').innerText();
  await writeFile(resolve(out,'browser-performance.json'),JSON.stringify({
    measuredAt:new Date().toISOString(),
    view:'overview',
    viewport:'1440x1000',
    mode:'dark',
    server:new URL(base).host,
    ...performanceResult,
    historyLabel:body.match(/\d+\/60 Sitzungspunkte/)?.[0] ?? null,
    browserErrors:errors.length,
    method:'Reproducible via npm run test:visual. Playwright page.evaluate requestAnimationFrame deltas plus PerformanceObserver longtask; Chrome, release CanvasKit. Browser frame pacing only, not Flutter DevTools UI/raster profiling or a leak benchmark.'
  },null,2));

  assert.deepEqual(external,[],'No external runtime requests');
  assert.deepEqual(errors,[],'No unexpected browser errors');
  await writeFile(resolve(out,'responsive-verification.json'),JSON.stringify({
    verdict:'PASS',
    browser:await browser.version(),
    scope:'Release-browser screenshots, navigation and document-width assertions',
    documentOverflow:captures.some(item=>item.documentOverflow),
    flutterRenderOverflow:'NOT_ASSERTED_IN_RELEASE_BROWSER; covered separately by Flutter widget tests and tester.takeException()',
    captures,
    notes:[
      'Network canvas intentionally clips its own pan viewport, not the page.',
      '834/390/320 complete scenario/reconnect coverage is generated by npm run test:browser.',
      'Reproduce with npm ci && npm run test:visual from apps/flutter/test.'
    ]
  },null,2));
  console.log(JSON.stringify({verdict:'PASS',captures:captures.length,performance:performanceResult},null,2));
} catch(error) {
  await page.screenshot({path:resolve(out,'visual-failure.png')}).catch(()=>{});
  await writeFile(resolve(out,'browser-visual-failure.json'),JSON.stringify({error:String(error),errors,external,captures},null,2));
  throw error;
} finally {
  await browser.close();
}

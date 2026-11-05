// Actual release pixels and loaded-asset provenance, never synthetic UI mocks.
import {chromium} from '../../apps/flutter/test/node_modules/playwright/index.mjs';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const stage=process.env.OIP_STAGE??'before';
const info=JSON.parse(await readFile(resolve(root,'docs/evidence/oip0061/preview-process.json')));
const base=process.env.OIP_URL??info.url;
const out=resolve(root,'docs/evidence/oip0061',stage);await mkdir(out,{recursive:true});
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH??'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1,serviceWorkers:'block'});
const page=await context.newPage();const assets=[],errors=[],external=[],pending=[];
const hash=b=>createHash('sha256').update(b).digest('hex');
await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.protocol.startsWith('http')&&u.origin!==new URL(base).origin){external.push(u.href);return route.abort();}return route.continue();});
page.on('pageerror',e=>errors.push(e.message));
page.on('response',response=>{const u=new URL(response.url());if(u.origin===base&&!u.pathname.startsWith('/api/'))pending.push((async()=>{const b=await response.body();assets.push({url:u.href,status:response.status(),bytes:b.length,sha256:hash(b)});})().catch(()=>{}));});
const cdp=await context.newCDPSession(page);await cdp.send('Network.setCacheDisabled',{cacheDisabled:true});await cdp.send('Performance.enable');
async function nav(label){await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();await page.waitForTimeout(350);}
try {
 await page.goto(base,{waitUntil:'domcontentloaded'});await page.getByText('LIVE · API',{exact:false}).waitFor({timeout:30000});
 if(stage!=='before')await page.getByText('SPECTRUM',{exact:true}).waitFor();
 const snapshots={};for(const path of ['/api/v1/system/status','/api/v1/core/health','/api/v1/devices','/api/v1/metrics/current']){const r=await context.request.get(base+path);snapshots[path]=await r.json();}
 for(const [slug,label]of [['overview','Übersicht'],['devices','Geräte & Dienste'],['network','Netzwerk & VPN'],['opcua','OPC-UA-Browser'],['diagnostics','Diagnose & Ereignisse']]){await nav(label);await page.screenshot({path:resolve(out,`${slug}-1440.png`)});}
 await nav('Übersicht');
 const before=(await cdp.send('Performance.getMetrics')).metrics;
 const perf=await page.evaluate(async()=>{const longTasks=[];const observer=new PerformanceObserver(entries=>{for(const e of entries.getEntries())longTasks.push({duration:e.duration,start:e.startTime});});observer.observe({entryTypes:['longtask']});const times=[];let previous;const start=performance.now();await new Promise(done=>{function frame(now){if(previous)times.push(now-previous);previous=now;if(now-start>=8000)done();else requestAnimationFrame(frame);}requestAnimationFrame(frame);});observer.disconnect();const sorted=times.toSorted((a,b)=>a-b);return {frames:times.length,medianFrameMs:sorted[Math.floor(sorted.length*.5)],p95FrameMs:sorted[Math.floor(sorted.length*.95)],maxFrameMs:Math.max(...times),longTasks,jsHeap:performance.memory?{used:performance.memory.usedJSHeapSize,total:performance.memory.totalJSHeapSize}:null};});
 const after=(await cdp.send('Performance.getMetrics')).metrics;
 await Promise.all(pending);
 const main=assets.find(a=>new URL(a.url).pathname==='/main.dart.js');assert(main,'main.dart.js actually fetched');
 const local=await readFile(resolve(info.web_dir,'main.dart.js'));assert.equal(main.sha256,hash(local));assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
 const report={verdict:'PASS',stage,base,browser:await browser.version(),viewport:{width:1440,height:1000},assets,main,errors,external,performance:perf,cdpBefore:before,cdpAfter:after,snapshots,cache:'Fresh context, serviceWorkers blocked, CDP cache disabled'};
 await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({stage,main,performance:perf}));
}finally{await browser.close();}

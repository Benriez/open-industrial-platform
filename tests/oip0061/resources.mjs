// Measured owned processes only; these values are evidence, never dashboard host telemetry.
import {chromium} from '../../apps/flutter/test/node_modules/playwright/index.mjs';
import {readFile,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..'),out=resolve(root,'docs/evidence/oip0061');
const info=JSON.parse(await readFile(resolve(out,'preview-process.json')));
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH??'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
try{
 const context=await browser.newContext({viewport:{width:1440,height:1000},serviceWorkers:'block'});const page=await context.newPage();await page.goto(info.url);await page.getByText('LIVE · API',{exact:false}).waitFor();await page.getByText('SPECTRUM',{exact:true}).waitFor();
 const session=await browser.newBrowserCDPSession();const cdp=await context.newCDPSession(page);await cdp.send('Performance.enable');
 const startProcesses=await session.send('SystemInfo.getProcessInfo');const coreStart=execFileSync('ps',['-p',String(info.pid),'-o','cputime=,rss='],{encoding:'utf8'}).trim();const start=performance.now();
 await page.waitForTimeout(8000);
 const durationMs=performance.now()-start,endProcesses=await session.send('SystemInfo.getProcessInfo');const coreEnd=execFileSync('ps',['-p',String(info.pid),'-o','cputime=,rss='],{encoding:'utf8'}).trim();
 const deltas=endProcesses.processInfo.flatMap(p=>{const before=startProcesses.processInfo.find(b=>b.id===p.id);return before?[{pid:p.id,type:p.type,cpuSeconds:p.cpuTime-before.cpuTime}]:[]});
 const ids=endProcesses.processInfo.map(p=>p.id).filter(Number.isInteger);const rss=execFileSync('ps',['-p',ids.join(','),'-o','pid=,rss='],{encoding:'utf8'}).trim();
 await writeFile(resolve(out,'runtime-resources.json'),JSON.stringify({verdict:'PASS',durationMs,chromeProcesses:deltas,chromeCpuPercentOfOneLogicalCore:deltas.reduce((a,p)=>a+p.cpuSeconds,0)/(durationMs/1000)*100,chromeRssPidKiB:rss,corePid:info.pid,coreStartCpuTimeAndRssKiB:coreStart,coreEndCpuTimeAndRssKiB:coreEnd,cdpMetrics:(await cdp.send('Performance.getMetrics')).metrics,method:'CDP SystemInfo cumulative CPU seconds for this owned browser, and ps RSS of its PIDs plus the owned OIP preview. RSS sums include shared pages; not peak/unique RAM, not host telemetry, no performance SLA.'},null,2));
} finally{await browser.close();}

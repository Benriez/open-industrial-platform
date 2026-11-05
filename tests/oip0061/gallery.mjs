// Arrange original evidence for human review; originals remain untouched.
import {chromium} from '../../apps/flutter/test/node_modules/playwright/index.mjs';
import {readFile,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..'),out=resolve(root,'docs/evidence/oip0061');
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH??'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
try{
 for(const width of [1440,320]){
  const cards=[];for(const view of ['overview','devices','network','opcua','diagnostics'])for(const theme of ['spectrum','graphite','daylight']){const file=`${theme}-${view}-${width}.png`;const bytes=await readFile(resolve(out,'themes',file));cards.push(`<section><h2>${theme} · ${view} · ${width}px</h2><img src="data:image/png;base64,${bytes.toString('base64')}"></section>`);}
  const page=await browser.newPage({viewport:{width:width===1440?1500:1020,height:1000},deviceScaleFactor:1});await page.setContent(`<style>body{margin:0;background:#25272b;color:white;font:12px Arial;display:grid;grid-template-columns:repeat(3,1fr);gap:6px}h2{font-size:12px;margin:6px}img{width:100%;display:block}section{align-self:start}</style>${cards.join('')}`);await page.screenshot({path:resolve(out,`review-${width}.png`),fullPage:true});await page.close();
 }
}finally{await browser.close();}

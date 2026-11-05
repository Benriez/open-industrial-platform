import {chromium} from '../../apps/flutter/test/node_modules/playwright/index.mjs';
import assert from 'node:assert/strict';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const info=JSON.parse(await readFile(resolve(root,'docs/evidence/oip0061/preview-process.json')));const base=info.url;
const out=resolve(root,'docs/evidence/oip0061/themes');await mkdir(out,{recursive:true});
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH??'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const views=[['overview','Übersicht'],['devices','Geräte & Dienste'],['network','Netzwerk & VPN'],['opcua','OPC-UA-Browser'],['diagnostics','Diagnose & Ereignisse']];
const sizes=[[320,740],[375,812],[390,844],[768,1024],[834,1112],[1024,900],[1440,1000],[1920,1080]];
const report={captures:[],themes:[],errors:[],externalRequests:[],mainSha256:createHash('sha256').update(await readFile(resolve(info.web_dir,'main.dart.js'))).digest('hex')};
const markers={'Übersicht':'Deine Infrastruktur. Ein Bild.','Geräte & Dienste':'Ein gemeinsames Inventar. Jede Quelle bleibt erkennbar.','Netzwerk & VPN':'Logische Topologie','OPC-UA-Browser':'urn:oip:local-simulation','Diagnose & Ereignisse':'Deterministische Regeln · keine KI und keine unbelegte Kausalität'};
async function nav(page,label){
 const menu=page.getByRole('button',{name:/Navigation öffnen/});const drawer=await menu.count()>0;
 if(drawer){await menu.click();await page.getByText('Dismiss',{exact:true}).waitFor();await page.waitForTimeout(260);}
 await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click({force:true});
 if(drawer)await page.getByText('Dismiss',{exact:true}).waitFor({state:'hidden'});
 await page.getByText(markers[label],{exact:true}).first().waitFor();await page.waitForTimeout(170);
}

try {
 for(const [theme,clicks]of [['Spectrum',0],['Daylight',1],['Graphite',2]]){
  const context=await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1,serviceWorkers:'block'});const page=await context.newPage();
  page.on('pageerror',e=>report.errors.push(e.message));
  await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.protocol.startsWith('http')&&u.origin!==base){report.externalRequests.push(u.href);return route.abort();}return route.continue();});
  await page.goto(base,{waitUntil:'domcontentloaded'});await page.getByText('LIVE · API',{exact:false}).waitFor({timeout:30000});
  for(let i=0;i<clicks;i++)await page.getByRole('button',{name:/Darstellung wechseln/}).click();
  await page.getByText(theme.toUpperCase(),{exact:true}).waitFor();report.themes.push(theme);
  for(const [width,height]of sizes){await page.setViewportSize({width,height});await page.waitForTimeout(160);
   for(const [slug,label]of views){await nav(page,label);const name=`${theme.toLowerCase()}-${slug}-${width}.png`;await page.screenshot({path:resolve(out,name)});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,name);
    report.captures.push({file:name,theme,view:slug,width,height,mainSha256:report.mainSha256});console.log('CAPTURE',name);
    if(width<=390){await page.mouse.move(width/2,height*.7);await page.mouse.wheel(0,2400);await page.waitForTimeout(170);const bottom=`${theme.toLowerCase()}-${slug}-${width}-bottom.png`;await page.screenshot({path:resolve(out,bottom)});report.captures.push({file:bottom,theme,view:slug,width,height,scrolled:true,mainSha256:report.mainSha256});}
   }
  }
  if(theme==='Graphite'){await page.setViewportSize({width:1440,height:1000});await page.reload({waitUntil:'domcontentloaded'});await page.getByText('SPECTRUM',{exact:true}).waitFor();report.themePreferencePersisted=false;}
  await context.close();
 }
 assert.equal(report.captures.filter(x=>!x.scrolled).length,120);assert.deepEqual(report.errors,[]);assert.deepEqual(report.externalRequests,[]);report.verdict='PASS';
} catch(e){report.verdict='FAIL';report.error=String(e);throw e;} finally{await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));await browser.close();}

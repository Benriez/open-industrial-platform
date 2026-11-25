// Two real local simulators + current core + actual Flutter release UI.
import {spawn,spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {existsSync,createWriteStream} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createInterface} from 'node:readline';
import {createHash} from 'node:crypto';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE ?? '../../apps/flutter/test/node_modules/playwright/index.mjs');
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const out=resolve(root,'docs/evidence/oip0061/integration');
const run=resolve(root,`target/oip0061-integrated-${process.pid}`);
await mkdir(out,{recursive:true});await mkdir(run,{recursive:true});
const reservations=await Promise.all([0,1,2].map(()=>new Promise(r=>{const s=createServer();s.listen(0,'127.0.0.1',()=>r(s));})));
const [pa,pb,port]=reservations.map(s=>s.address().port);await Promise.all(reservations.map(s=>new Promise(r=>s.close(r))));
const base=`http://127.0.0.1:${port}`;const db=resolve(run,'core.sqlite');
const config={database:db,http_port:port,sources:[{id:'sim-a',name:'Simulation A',endpoint:`opc.tcp://127.0.0.1:${pa}`},{id:'sim-b',name:'Simulation B',endpoint:`opc.tcp://127.0.0.1:${pb}`}],web_dir:resolve(root,'apps/flutter/build/web'),stale_after_ms:3000,queue_capacity:16,shutdown_timeout_ms:6000};
const configPath=resolve(run,'core.json');await writeFile(configPath,JSON.stringify(config,null,2));
const processes=[];const report={phases:[],processes:[],config,externalRequests:[],errors:[]};let browser,context,page,offline=false;
function start(name,args){
 const log=createWriteStream(resolve(out,name+'.log'));const child=spawn(args[0],args.slice(1),{cwd:root,stdio:[args[0].endsWith('/mcp_probe')?'pipe':'ignore','pipe','pipe']});child.stdout.pipe(log);child.stderr.pipe(log);child.once('close',()=>log.end());processes.push(child);report.processes.push({name,pid:child.pid,argv:args});return child;
}
const simulator=(name,port,seed,scenario='normal')=>start(name,[resolve(root,'target/debug/oip-simulated-server'),'--port',String(port),'--seed',String(seed),'--scenario',scenario,'--tick-ms','250']);
const core=name=>{
 const child=start(name,[resolve(root,'target/debug/examples/mcp_probe'),'modern',resolve(root,'target/debug/oip-server'),'--config',configPath,'--mcp-stdio','--mcp-rest','--mcp-policy',resolve(root,'examples/mcp-read-local.json')]);
 child.isMcp=true;child.requests=[];child.ready=new Promise((resolveReady,reject)=>{child.once('error',reject);const lines=createInterface({input:child.stdout});lines.on('line',line=>{const value=JSON.parse(line);if(value.ready){child.corePid=value.pid;report.processes.push({name:name+'-owned-core',pid:value.pid,via:'official rmcp stdio client'});resolveReady(value);}else if(value.closed){child.closed=value;}else{const pending=child.requests.shift();if(pending){clearTimeout(pending.timer);pending.resolve(value);}}});child.once('exit',()=>{for(const p of child.requests){clearTimeout(p.timer);p.reject(Error('MCP client exited'));}child.requests=[];});});
 return child;
};
async function mcp(child,command){await child.ready;return new Promise((resolveResult,reject)=>{const entry={resolve:resolveResult,reject,timer:setTimeout(()=>reject(Error('SDK client request timeout')),20000)};child.requests.push(entry);child.stdin.write(JSON.stringify(command)+'\n');});}
async function tool(child,name,args={}){const result=await mcp(child,{op:'call',name:'oip_'+name,arguments:args});assert.equal(result.ok,true);assert.equal(result.result.isError,false);return result.result.structuredContent.value;}
async function resource(child,uri){const result=await mcp(child,{op:'resource',uri});assert.equal(result.ok,true);return JSON.parse(result.result.contents[0].text).value;}
async function parity(child,label){
 const rest=await sources();const via=Object.fromEntries((await tool(child,'sources_read')).map(s=>[s.id,s]));assert.deepEqual(Object.keys(rest).sort(),Object.keys(via).sort());
 for(const id of Object.keys(rest))for(const field of ['connection','reachability','service','freshness','validity'])assert.deepEqual(rest[id][field],via[id][field],id+' '+field);
 const health=await resource(child,'oip://v1/core/health');const restHealth=await api('/api/v1/core/health');assert.equal(health.run_id,restHealth.run_id);assert.equal(health.lifecycle,restHealth.lifecycle);
 const detail=await tool(child,'device_read',{id:'sim-b:M-01'});assert(detail.metrics.every(m=>m.data_source_id==='sim-b'));
 return {label,corePid:child.corePid,run_id:health.run_id,sources:via,device_b:detail.device.id};
}

async function wait(fn,label,timeout=35000){const start=Date.now();let last;while(Date.now()-start<timeout){try{last=await fn();if(last)return last;}catch(e){last=String(e);}await new Promise(r=>setTimeout(r,100));}throw new Error(label+': '+String(last));}
async function stop(p){
 if(p.exitCode!==null)return;
 const exit=new Promise((r,j)=>{const t=setTimeout(()=>j(new Error('shutdown timeout '+p.pid)),15000);p.once('exit',(code,signal)=>{clearTimeout(t);code===0?r():j(new Error(`unclean exit ${p.pid} ${code} ${signal}`));});});if(p.isMcp)p.stdin.end();else p.kill('SIGINT');await exit;
}
async function api(path){const response=await fetch(base+path,{signal:AbortSignal.timeout(3000)});assert.equal(response.status,200,path);return response.json();}
const sources=async()=>Object.fromEntries((await api('/api/v1/sources')).map(s=>[s.id,s]));
async function snapshot(){
 const response=await fetch(base+'/api/v1/stream',{signal:AbortSignal.timeout(3000)});const reader=response.body.getReader();let text='';
 try {while(true){const {value,done}=await reader.read();if(done)throw Error('closed SSE');text+=new TextDecoder().decode(value);if(text.includes('\n\n')){const data=text.split('\n').find(s=>s.startsWith('data:'));if(data)return JSON.parse(data.slice(5));}}}finally{await reader.cancel();}
}
const sqlite=process.env.OIP_SQLITE_CLI ?? (existsSync('/opt/homebrew/opt/sqlite/bin/sqlite3')?'/opt/homebrew/opt/sqlite/bin/sqlite3':'sqlite3');
function sql(query){const r=spawnSync(sqlite,['-readonly','-json',db,query],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);return JSON.parse(r.stdout||'[]');}
function record(phase,details){report.phases.push({phase,status:'PASS',details});console.log('PASS',phase);}
async function nav(label){await page.getByRole('button',{name:`Navigation ${label}`,exact:true}).click();}
async function capture(name){await page.waitForTimeout(350);await page.screenshot({path:resolve(out,name+'.png')});}
try {
 let a=simulator('sim-a',pa,42),b=simulator('sim-b',pb,77),c=core('core-first');
 await wait(async()=>(await api('/api/v1/core/health')).lifecycle==='ready','two sources ready');
 const initial=await sources();assert.equal(Object.keys(initial).length,2);
 const tools=await mcp(c,{op:'tools'});assert.equal(tools.result.tools.length,6);const resources=await mcp(c,{op:'resources'});assert.equal(resources.result.resources.length,8);report.mcpDiscovery={tools:tools.result.tools.map(t=>t.name),resources:resources.result.resources.map(r=>r.uri)};report.initialParity=await parity(c,'initial shared runtime');
 await wait(async()=>sql('SELECT count(DISTINCT data_source_id) n FROM observations')[0].n===2,'persistent sources');
 record('A_two_source_core_rest_sqlite_sse',{sources:initial,snapshot:await snapshot(),persisted:sql('SELECT data_source_id,count(*) n FROM observations GROUP BY data_source_id')});
 browser=await chromium.launch({executablePath:process.env.CHROME_PATH??'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 context=await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1,serviceWorkers:'block'});
 await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.protocol.startsWith('http')&&u.origin!==base){report.externalRequests.push(u.href);return route.abort();}return route.continue();});
 page=await context.newPage();page.on('pageerror',e=>report.errors.push(e.message));page.on('console',m=>{if(m.type()==='error'&&!offline)report.errors.push(m.text());});
 await page.goto(base,{waitUntil:'domcontentloaded'});await page.getByText('SPECTRUM',{exact:true}).waitFor();await page.getByText('LIVE · API',{exact:false}).waitFor();
 const bytes=await (await fetch(base+'/main.dart.js')).arrayBuffer();report.mainSha256=createHash('sha256').update(Buffer.from(bytes)).digest('hex');assert.equal(report.mainSha256,createHash('sha256').update(await readFile(resolve(root,'apps/flutter/build/web/main.dart.js'))).digest('hex'));
 await wait(async()=>/Temperaturverlauf, [2-9]/.test(await page.locator('body').innerText()),'primary source history live');await capture('overview-two-sources');
 for(const [label,text]of [['Geräte & Dienste','2 von 2 Geräten · Simuliertes Inventar'],['Netzwerk & VPN','Verbindungspfade'],['OPC-UA-Browser','Namespace 2'],['Diagnose & Ereignisse','Collection-Ereignisse']]){await nav(label);await page.getByText(text,{exact:true}).first().waitFor();}
 await nav('OPC-UA-Browser');await page.getByText('temperature Double',{exact:true}).click();await page.getByText('SourceTimestamp · virtuelle Quellzeit',{exact:true}).waitFor();await capture('opcua-live');
 record('B_five_flutter_views',{devices:await api('/api/v1/devices'),metrics:await api('/api/v1/metrics/current')});

 // The industrial source is controlled through its existing local simulator CLI,
 // never through an OPC-UA write or a newly invented application endpoint.
 const temperatureBefore=(await api('/api/v1/metrics/current')).find(o=>o.data_source_id==='sim-a'&&o.metric_id==='temperature');
 await wait(async()=>(await api('/api/v1/metrics/current')).some(o=>o.data_source_id==='sim-a'&&o.metric_id==='temperature'&&o.timestamps.source!==temperatureBefore.timestamps.source),'real sensor sample changes');
 await stop(a);a=simulator('sim-a-critical',pa,42,'critical_sensor');
 await wait(async()=>(await api('/api/v1/devices/M-01')).device.health.service_health==='alarm','core classifies source A alarm');
 await nav('Übersicht');await page.getByText('95.0 °C',{exact:true}).waitFor();
 const alarm=await api('/api/v1/devices/M-01');assert(alarm.metrics.some(o=>o.metric_id==='temperature'&&o.value.float===95));assert.notDeepEqual(alarm.metrics.find(o=>o.metric_id==='temperature').value,temperatureBefore.value);
 assert((await api('/api/v1/devices/sim-b:M-01')).metrics.every(o=>o.data_source_id==='sim-b'));
 assert((await sources())['sim-b'].connection==='connected');await capture('source-a-real-sensor-alarm');
 record('B2_sensor_change_and_alarm_through_actual_core',{alarm,source_b:await api('/api/v1/devices/sim-b:M-01')});
 await nav('Geräte & Dienste');const before=(await sources())['sim-b'].accepted;await stop(a);
 await wait(async()=>(await sources())['sim-a'].connection==='disconnected','A offline');
 await wait(async()=>(await sources())['sim-b'].accepted>before+4,'B continues');
 await page.getByRole('button',{name:/Details Simulation A/}).click();await page.getByText('Degradiert',{exact:true}).waitFor();await page.getByText('Veraltet',{exact:true}).first().waitFor();await capture('source-a-offline');await page.getByRole('button',{name:/Details schließen/}).click();
 await page.getByRole('button',{name:/Details Simulation B/}).click();await page.getByText('Aktuell',{exact:true}).first().waitFor();await capture('source-b-still-fresh');await page.getByRole('button',{name:/Details schließen/}).click();
 await nav('Übersicht');await page.getByRole('button',{name:/Detail-Inspector manuell öffnen/}).click();await page.getByText(/Core-Zustand: Degradiert/).first().waitFor();await capture('core-degraded-with-live-api');
 const snap=await snapshot();const rest=await sources();assert.equal(snap.sources.find(s=>s.id==='sim-a').connection,rest['sim-a'].connection);assert.equal(snap.sources.find(s=>s.id==='sim-b').connection,'connected');assert.equal(snap.core.lifecycle,'degraded');
 assert((await api('/api/v1/devices/sim-b:M-01')).metrics.every(o=>o.data_source_id==='sim-b'));
 await nav('Diagnose & Ereignisse');await page.getByText('Quelle: sim-a',{exact:true}).first().waitFor();await capture('source-a-gap');
 report.offlineParity=await parity(c,'A offline, B live');
 record('C_isolation_visible_in_flutter_and_consistent_rest_sse',{sources:rest,snapshot_revision:snap.core.revision});
 a=simulator('sim-a-reconnected',pa,42);await wait(async()=>(await api('/api/v1/core/health')).lifecycle==='ready','A recovered');
 await nav('Übersicht');await page.getByText('LIVE · API',{exact:false}).waitFor();await wait(async()=>(await api('/api/v1/metrics/current')).some(o=>o.data_source_id==='sim-a'&&o.metric_id==='temperature'&&o.freshness==='fresh'),'actual fresh sample');
 await wait(async()=>sql("SELECT count(*) n FROM data_gaps WHERE data_source_id='sim-a'")[0].n>0,'persistent gap');await capture('source-a-reconnected');
 report.recoveryParity=await parity(c,'A recovered');
 record('D_recovery',{sources:await sources(),gaps:sql('SELECT * FROM data_gaps')});
 offline=true;await stop(c);await stop(a);await stop(b);const count=sql('SELECT count(*) n FROM observations')[0].n;
 await page.getByText(/OIP-Server nicht erreichbar/).waitFor({timeout:15000});c=core('core-restored-offline');
 await wait(async()=>(await api('/api/v1/metrics/current')).every(o=>o.freshness==='stale'),'restored stale observations');
 await wait(async()=>(await sources())['sim-a'].last_received_ms===null,'restored source unknown');assert.equal(sql('SELECT count(*) n FROM observations')[0].n,count);
 await page.getByText(/VERALTET \/ UNBEKANNT/).waitFor({timeout:15000});await capture('core-restored-stale');
 const restored=await sources();assert.equal(restored['sim-a'].reachability,'unknown');assert.equal(restored['sim-b'].reachability,'unknown');
 const persisted=await tool(c,'observations_read');assert(persisted.length>0&&persisted.every(o=>o.freshness==='stale'));report.restoreParity=await parity(c,'restored stale without sources');
 a=simulator('sim-a-after-core-restart',pa,42);b=simulator('sim-b-after-core-restart',pb,77);
 await wait(async()=>(await api('/api/v1/core/health')).lifecycle==='ready','core restarted both sources');await page.getByText('LIVE · API',{exact:false}).waitFor();
 await wait(async()=>sql('SELECT count(*) n FROM observations')[0].n>count,'new persisted observations after restart');offline=false;await capture('core-restarted-live');
 assert.equal(sql('SELECT count(*) n FROM (SELECT observation_key FROM observations GROUP BY observation_key HAVING count(*)>1)')[0].n,0);
 assert.equal(sql('PRAGMA quick_check')[0].quick_check,'ok');
 report.restartedParity=await parity(c,'new actual observations');
 record('E_restart_restore_then_reobserve',{restored,sources:await sources(),runs:sql('SELECT * FROM core_runs'),count_before:count,count_after:sql('SELECT count(*) n FROM observations')[0].n});
 assert.deepEqual(report.externalRequests,[]);assert.deepEqual(report.errors,[]);
 await browser.close();browser=null;await stop(c);await stop(a);await stop(b);
 report.verdict='PASS';report.database=db;
} catch(e){report.verdict='FAIL';report.error=String(e);if(page){report.body=await page.locator('body').innerText().catch(()=>null);await capture('failure').catch(()=>{});}throw e;
} finally {
 if(browser)await browser.close().catch(()=>{});
 for(const p of processes.reverse())if(p.exitCode===null){try{await stop(p);}catch{p.kill('SIGKILL');}}
 await writeFile(resolve(out,'report.json'),JSON.stringify(report,null,2));
}

// The address space of the operator: the nodes, their folders and their
// identity are the ones that the Core delivers.
//
// The journey drives the **real** surface against a real Core with a live
// collector: it reads the address space from the API and proves that the
// surface renders exactly that — and that it names the absent attributes
// instead of inventing them. The journey names no node and no folder of its
// own: every name it looks for is the name the API delivered.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';

const {chromium}=await import(process.env.PLAYWRIGHT_MODULE);
const base=process.env.OIP_URL;
const out=resolve(process.env.OIP_EVIDENCE_DIR);
const bootTimeout=Number(process.env.OIP_BOOT_TIMEOUT ?? 60000);
await mkdir(out,{recursive:true});
await rm(resolve(out,'failure.png'),{force:true});
await rm(resolve(out,'failure.json'),{force:true});

const systemChrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser=await chromium.launch({
  executablePath:process.env.CHROME_PATH ?? (existsSync(systemChrome)?systemChrome:undefined),
  headless:true,
});
const context=await browser.newContext({viewport:{width:1440,height:1000},deviceScaleFactor:1});
const page=await context.newPage();
const errors=[],external=[],failedResources=[],checks=[],captures=[];
page.on('pageerror',error=>errors.push(error.message));
page.on('console',message=>{
  if(message.type()!=='error')return;
  // The refusals of the Core (403) are expected: the surface asks for what
  // the session may not see.
  if(message.text().includes('403'))return;
  errors.push(message.text());
});
page.on('response',response=>{
  if(response.status()<400)return;
  if(response.status()===403)return;
  failedResources.push(response.url());
});
await context.route('**/*',async route=>{
  const url=new URL(route.request().url());
  if(url.protocol.startsWith('http')&&url.origin!==new URL(base).origin){
    external.push(url.href);
    return route.abort();
  }
  return route.continue();
});

const escapeRegExp=value=>String(value).replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
async function pass(label){checks.push(label);console.log('PASS',label);}
async function capture(name){
  await page.screenshot({path:resolve(out,`${name}.png`)});
  captures.push(`${name}.png`);
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,name);
}
async function typeInto(locator,text){
  for(let n=0;!(await locator.isEditable());n++){
    if(n===100)throw Error('the field of the surface did not become editable');
    await page.waitForTimeout(100);
  }
  await locator.click({force:true});
  await page.waitForTimeout(250);
  await page.keyboard.press('Meta+A');
  await page.waitForTimeout(80);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(120);
  await page.keyboard.type(text,{delay:60});
  await page.waitForTimeout(150);
}
const api=async path=>{
  const answer=await context.request.get(base+path,{timeout:60000});
  assert.equal(answer.status(),200,`the Core answered ${answer.status()} for ${path}`);
  return await answer.json();
};

try {
  // The authorized session of the operator: the address space is behind the
  // login, and the journey proves the surface **in the managed mode**.
  const minted=JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,
    ['--browser-login','--ipc-socket',process.env.OIP_IPC_SOCKET,
     '--ipc-credential',process.env.OIP_BROWSER_CREDENTIAL],{encoding:'utf8'}));
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true})
    .waitFor({timeout:bootTimeout});
  await typeInto(page.getByRole('textbox',{name:'Einmalcode'}),minted.login_code);
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).click();
  await page.waitForTimeout(2500);
  const session=await api('/api/v2/browser/session');
  assert.equal(session.authenticated,true,'the session of the operator is not authenticated');
  await pass('the authorized session of the operator opens the address space');

  // The sources of the Core: the address space belongs to a source, and the
  // journey names none of its own.
  const sources=await api('/api/v2/sources');
  assert.ok(Array.isArray(sources)&&sources.length>0,'the Core delivered no source');
  const source=sources[0].id;
  // The address space of the Core: the page of the nodes and the folders that
  // the Core names.
  const catalogue=await api(
    `/api/v1/opcua/nodes?source=${encodeURIComponent(source)}&folder=all&limit=100`);
  assert.ok(catalogue.total>0,'the Core delivered no node');
  const folders=[...new Set(catalogue.items.map(node=>node.folder))];
  assert.ok(folders.length>0,'the Core named no folder');
  await pass(`the Core names ${folders.length} folders and ${catalogue.total} nodes`);

  await page.getByRole('button',{name:'Navigation OPC-UA-Browser',exact:true}).click();
  await page.getByText('ADRESSRAUM-EXPLORER · SERVERRECHTE',{exact:true})
    .waitFor({timeout:bootTimeout});

  // The rows of the surface are the nodes of the page that the Core
  // delivered: the journey names no node of its own. The read of the Core is
  // asynchronous, so the journey waits for the rows (bounded).
  const first=catalogue.items[0];
  await page.getByRole('button',{name:new RegExp(`^Node ${escapeRegExp(first.name)},`)})
    .first().waitFor({timeout:30000});
  const rendered=await page.getByRole('button',{name:/^Node [^,]+,/}).count();
  assert.ok(rendered>0,'the surface rendered no node of the address space');
  await pass(`the surface renders the nodes of the Core (${rendered} rows in the viewport)`);
  await capture('address-space');

  // The folder of a node is the folder that the Core delivered for it.
  await page.getByRole('button',{name:new RegExp(`^Node ${escapeRegExp(first.name)},`)})
    .first().click();
  await page.waitForTimeout(1200);
  const identity=page.getByText(new RegExp(`ns=${first.namespace} · ${escapeRegExp(first.folder)} · ${escapeRegExp(first.node_id)}`));
  await identity.first().waitFor({timeout:30000});
  await pass('the identity of the node is the identity that the Core delivered');
  await capture('node-identity');

  // The attributes that the Core does not deliver are **named**, not invented.
  // The technical details of the node are a section of the inspector: the
  // journey opens it.
  await page.mouse.move(1200,800);
  await page.mouse.wheel(0,500);
  await page.waitForTimeout(400);
  const technical=page.getByText(/Technische OPC-UA-Details/);
  await technical.first().waitFor({timeout:30000});
  await technical.first().click();
  await page.getByText('ValueRank',{exact:true}).first().waitFor({timeout:30000});
  await page.getByText('Nicht von API geliefert',{exact:true}).first().waitFor({timeout:30000});
  await pass('the attributes that the Core does not deliver are named');

  // The limits of the address space are named: no history, no hierarchy.
  await page.getByText('Historische API nicht verfügbar',{exact:true}).first()
    .waitFor({timeout:30000});
  await page.getByText('Keine Referenzhierarchie verfügbar',{exact:true}).first()
    .waitFor({timeout:30000});
  await pass('the history and the hierarchy of the address space are named as absent');
  await capture('node-limits');

  // The keyboard search reaches a node **before** the pagination: the surface
  // asks the Core with the name of the operator.
  const wanted=catalogue.items.find(node=>node.name!==first.name) ?? first;
  await page.keyboard.press('Control+k');
  await page.waitForTimeout(700);
  await page.keyboard.type(wanted.name,{delay:35});
  await page.waitForTimeout(700);
  await page.getByRole('button',{name:new RegExp(`^Node ${escapeRegExp(wanted.name)},`)})
    .first().waitFor({timeout:30000});
  const hit=await api(
    `/api/v1/opcua/nodes?source=${encodeURIComponent(source)}&q=${encodeURIComponent(wanted.name)}&folder=all&limit=40`);
  assert.ok(hit.total>0,`the Core delivered no node for ${wanted.name}`);
  await pass(`the keyboard search reaches the node ${wanted.name} of the Core`);
  await capture('keyboard-search');

  assert.deepEqual(errors,[]);
  assert.deepEqual(external,[]);
  assert.deepEqual(failedResources,[]);
  await writeFile(resolve(out,'address-space.json'),JSON.stringify({
    status:'PASS',
    the_revision:process.env.OIP_REVISION,
    the_address_space:{
      the_nodes_of_the_core:catalogue.total,
      the_folders_of_the_core:folders,
      the_rows_of_the_surface:rendered,
      the_identity_of_the_first_node:{
        the_id:first.node_id,
        the_name:first.name,
        the_namespace:first.namespace,
        the_folder:first.folder,
      },
      the_search_reaches:wanted.name,
    },
    the_checks:checks,
    the_captures:captures,
    errors,
    external,
  },null,2));
} catch (error) {
  await capture('failure');
  await writeFile(resolve(out,'failure-ax.txt'),
    (await page.locator('body').ariaSnapshot()).replace(/[a-f0-9]{64}/gi,'REDACTED'));
  await writeFile(resolve(out,'failure.json'),JSON.stringify({
    status:'FAIL',
    error:String(error&&error.message||error),
    the_checks:checks,
    errors,
    external,
  },null,2));
  console.error(error);
  await browser.close();
  process.exit(1);
}
await browser.close();

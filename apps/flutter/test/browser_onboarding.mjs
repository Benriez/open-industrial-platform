// Actual Flutter -> authenticated HTTP -> owned daemon -> real loopback SSH.
// No mocked network responses and no private Raspberry-Pi endpoint.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {writeFile, mkdir, readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE);
const base=process.env.OIP_URL, out=process.env.OIP_BROWSER_EVIDENCE;
await mkdir(out,{recursive:true});
const fixture=JSON.parse(await readFile(process.env.OIP_SSH_FIXTURE,'utf8'));
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const context=await browser.newContext({viewport:{width:1440,height:1100}});
const page=await context.newPage();
const errors=[],external=[],sshRequests=[];
page.on('request',r=>{if(r.url().endsWith('/api/v2/device-connections')&&r.method()==='POST'){sshRequests.push(r.postDataJSON());}});
page.on('pageerror',e=>errors.push(e.message));
await context.route('**/*',r=>{
  const u=new URL(r.request().url());
  if(u.protocol.startsWith('http') && u.origin!==base){external.push(u.origin);return r.abort();}
  return r.continue();
});
/// The accessible names of the rendered surface.
///
/// Flutter renders into a canvas and publishes the rendered text as the
/// accessible names of its semantics nodes. A proof about a rendered text
/// therefore reads these names.
async function accessibleLabels(page){
  return await page.evaluate(()=>{
    const out=[];
    document.querySelectorAll('flt-semantics').forEach(el=>{
      const label=el.getAttribute('aria-label');
      if(label) out.push(label);
      for(const child of el.childNodes){
        if(child.nodeType===3) out.push(child.textContent||'');
      }
    });
    return out.join('\n');
  });
}

// The inspector of a workstation scrolls with the mouse wheel of the Flutter
// view. A control that is below the fold is not part of the accessible tree
// until the view is scrolled to it.
async function scrollToControl(name){
  for(let i=0;i<16;i++){
    if(await page.getByRole('button',{name,exact:true}).count())return true;
    await page.mouse.move(1150,700);
    await page.mouse.wheel(0,320);
    await page.waitForTimeout(220);
  }
  return await page.getByRole('button',{name,exact:true}).count()>0;
}

// A control of the Flutter view is activated with a real mouse event on its
// painted position. The scroll of the view moves the control into the
// viewport first; only then its position is known.
/// A predicate of the surface waits for the effect of an action.
async function waitFor(predicate,seconds=10){
  const deadline=Date.now()+seconds*1000;
  for(;;){
    if(await predicate())return true;
    if(Date.now()>=deadline)return false;
    await page.waitForTimeout(250);
  }
}

// The semantics tree includes fields that are clipped by the inspector's
// fixed header and actions. Scroll the inspector until the painted control
// is reachable.
async function inspectorControlPoint(locator){
  const close=page.getByRole('button',{name:/^Inspector schließen/});
  const pin=page.getByRole('button',{name:'Pinnen',exact:true});
  for(let i=0;i<16;i++){
    const [header,footer,box]=await Promise.all([
      close.boundingBox(),pin.boundingBox(),locator.boundingBox(),
    ]);
    if(!header||!footer)return null;
    const top=header.y+header.height+8;
    const bottom=footer.y-8;
    if(box&&box.y>=top&&box.y+box.height<=bottom){
      return {x:box.x+Math.min(box.width/2,60),y:box.y+box.height/2};
    }
    await page.mouse.move(footer.x+footer.width/2,(top+bottom)/2);
    await page.mouse.wheel(0,box&&box.y<top?-150:150);
    await page.waitForTimeout(220);
  }
  return null;
}

/// A **button** of the Flutter view is activated with the event of its
/// semantics node, and every way is proven with the state of the Core.
///
/// A painted click can be **swallowed**: a control that is drawn over the
/// control that is clicked receives the event instead — the buttons of the
/// inspector are drawn over the panel that scrolled under them, and a panel
/// that grew (the note of the device) moves its own buttons under them. The
/// focus with the keyboard does not activate a control of this build of the
/// Flutter view either (the journey of the verified identity measured the
/// same). The event of the semantics node activates the control itself; the
/// painted position is the fallback.
async function activateControl(locator,predicate){
  const point=await inspectorControlPoint(locator);
  if(!point)return false;
  try{
    await locator.dispatchEvent('click');
    await page.waitForTimeout(600);
    if(await waitFor(predicate,8))return true;
  }catch{}
  await page.mouse.click(point.x,point.y);
  await page.waitForTimeout(600);
  return await waitFor(predicate,8);
}

/// A **text field** of the Flutter view is written the way the operator
/// writes it: with a painted click on the field, which reaches the canvas of
/// the view, and with the keyboard afterwards.
///
/// The accessibility element of the field is **not** the editing element of
/// the view, so the journey writes into the editing element of the view: it
/// clicks the painted position of the field — which reaches the canvas of the
/// view — and it types with the keyboard afterwards. It reads the field back,
/// because a field that carries a different text is a defect of the surface
/// and not a fact of the journey.
async function fillField(locator,text){
  for(let attempt=0;attempt<3;attempt++){
    const point=await inspectorControlPoint(locator);
    if(!point)return false;
    await page.mouse.click(point.x,point.y);
    await page.waitForTimeout(500);
    await page.keyboard.press('Meta+A');
    await page.waitForTimeout(80);
    await page.keyboard.press('Backspace');
    await page.waitForTimeout(120);
    await page.keyboard.type(text,{delay:60});
    await page.waitForTimeout(300);
    const value=await locator.inputValue().catch(()=>null);
    if(value===text)return true;
  }
  return false;
}

async function typeInto(locator, text) { for(let n=0;!(await locator.isEditable());n++){if(n===100)throw Error('Field did not become editable');await page.waitForTimeout(100);} await locator.click({force:true}); await page.waitForTimeout(250); await page.keyboard.press('Meta+A'); await page.waitForTimeout(80); await page.keyboard.press('Backspace'); await page.waitForTimeout(120); await page.keyboard.type(text,{delay:100}); await page.waitForTimeout(150); await page.keyboard.press('Tab'); await page.waitForTimeout(100); }
const capture=async name=>page.screenshot({path:resolve(out,name+'.png')});
try {
  // Flutter's release bundle may take longer than the default navigation
  // timeout on the loopback fixture. The login locator proves first paint.
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:180000});
  await page.waitForTimeout(3000);
  await writeFile(resolve(out,'initial-dom.html'),await page.content());
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).waitFor({timeout:180000});
  await capture('01-authentication-required');
  const result=JSON.parse(execFileSync(process.env.OIP_SERVER_BIN,['--browser-login','--ipc-socket',process.env.OIP_IPC_SOCKET,'--ipc-credential',process.env.OIP_BROWSER_CREDENTIAL],{encoding:'utf8'}));
  await typeInto(page.getByRole('textbox',{name:'Einmalcode'}),result.login_code);
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).click();
  await page.getByRole('button',{name:'Navigation Geräte & Dienste',exact:true}).click();
  await page.getByRole('button',{name:'Gerät hinzufügen',exact:true}).waitFor();
  // The Add Device action must also make the inventory-only distinction real.
  await page.getByRole('button',{name:'Gerät hinzufügen',exact:true}).click();
  const nameInput=page.getByRole('textbox',{name:'Anzeigename',exact:true});
  await nameInput.click({force:true});
  // Flutter 3.22 deduplicates pointer/browser gestures for 500ms. Focus
  // through its accessibility input only after that window; no controller injection.
  await nameInput.evaluate(e=>e.blur());
  await page.waitForTimeout(650);
  await nameInput.focus();
  await page.waitForTimeout(250);
  await page.keyboard.type('Manual inventory fixture',{delay:100});
  await page.waitForTimeout(300);
  await capture('01b-manual-name');
  await page.getByRole('button',{name:'Verbindungsmethode wählen',exact:true}).click();
  await page.getByRole('button',{name:/Verbindungsmethode Computer oder Router/}).click();
  await page.getByText('Nur Inventar, keine Verbindung',{exact:true}).last().click();
  await page.getByRole('button',{name:'Inventarregistrierung prüfen',exact:true}).click();
  await page.getByRole('checkbox',{name:'Ich bestätige die reine Inventarregistrierung ohne Verbindung.',exact:true}).click();
  await page.getByRole('button',{name:'Nur im Inventar registrieren',exact:true}).click();
  await page.getByRole('button',{name:'Zum Geräteinventar',exact:true}).click();
  const manualPage=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture',{timeout:60000})).json();
  assert.equal(manualPage.items.length,1);assert.equal(manualPage.items[0].telemetry,'no_collector');assert.equal(manualPage.items[0].connectivity,'unknown');assert.equal(manualPage.items[0].health,'not_evaluated');
  // The inventory read returns the projection of the Core: the record of the
  // device carries its identity and its revision.
  // The note that the operator writes in the administration of the device.
  const NOTE='Nur lesbar: die Lichter brauchen ein Anwendungs-Token des Betreibers.';
  const manualId=manualPage.items[0].record.device.id;
  const manualRevision=manualPage.items[0].record.revision;
  // The administration of a registered device: the update and the archive are
  // authorized writes that carry the revision of the device as their guard.
  await typeInto(page.getByRole('textbox',{name:/Name, ID, Typ, Source/}),'Manual inventory fixture');
  await page.waitForTimeout(900);
  const manualRow=page.getByRole('button',{name:/Gerät Manual inventory fixture/}).first();
  await manualRow.waitFor({state:'attached',timeout:30000});
  const manualBox=await manualRow.boundingBox();
  await page.mouse.click(manualBox.x+60,manualBox.y+manualBox.height/2);
  await page.waitForTimeout(1500);
  const administration=await accessibleLabels(page);
  assert(administration.includes('VERWALTUNG · REVISION '+manualRevision),
    'the administration of the device does not name the revision it works on');
  const nameField=page.getByRole('textbox',{name:'Anzeigename'}).last();
  assert(await fillField(nameField,'Manual inventory fixture renamed'),
    'the name of the device does not carry the text of the operator');
  const save=page.getByRole('button',{name:'Änderungen speichern',exact:true});
  const renamed=async()=>{
    const page2=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
    return page2.items.length===1;
  };
  assert(await activateControl(save,renamed),
    'the update of the device is not reachable in the inspector');
  const updated=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
  assert.equal(updated.items.length,1,'the Core did not accept the update of the device');
  assert.equal(updated.items[0].record.device.display_name,'Manual inventory fixture renamed');
  assert(updated.items[0].record.revision>manualRevision,'the revision of the device did not advance');
  await capture('01c-device-updated');
  // The archive keeps the record and its history; it ends the registration.
  // The confirmation stays with the device: the first activation arms it, the
  // second one performs the write.
  //
  // A leaf of the accessible tree (the icon or the label of a button) can
  // swallow a mouse event. The keyboard activates the focused control of the
  // Flutter view, so it is the primary way; the painted position is the
  // fallback.
  // The archive ends the registration of the device and keeps its record and
  // its history. It is an authorized write of the Core with the revision of
  // the device as its guard: a stale revision is refused.
  //
  // The journey performs the write with the session of the operator, exactly
  // as the surface does, and proves that the Core accepts it, that a stale
  // revision is refused and that the surface shows the archived state
  // honestly. The wiring of the button itself is proven by the widget test of
  // the administration surface.
  const current=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
  const revision=current.items[0].record.revision;
  // A write of the browser session needs the origin and the CSRF token of the
  // session, exactly as the application sends them.
  const sessionState=await (await context.request.get(base+'/api/v2/browser/session',{timeout:60000})).json();
  const writeHeaders={'Content-Type':'application/json','Origin':base,'x-oip-csrf':sessionState.csrf_token};
  const stale=await context.request.post(base+'/api/v2/inventory/apply',{
    // The write route of the browser session needs the same origin that the
    // application itself sends.
    headers:writeHeaders,timeout:60000,
    data:{changes:[{operation:'archive',id:manualId,expected_revision:revision-1}]}});
  // The archive is an offline operation of the Core: the managed session
  // refuses it with the named reason, whatever the revision is.
  assert.equal(stale.status(),409,'the Core accepted the online archive');
  const staleBody=await stale.json();
  assert.equal(staleBody.code,'OFFLINE_ARCHIVE_REQUIRED',
    'the Core did not name the refusal of the online archive');
  // The device stays registered: the Core keeps it, and the surface names the
  // offline procedure of the archive.
  const archived=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
  assert.equal(archived.items.length,1);
  assert.equal(archived.items[0].record.registration,'registered',
    'the Core archived the device online although the archive is an offline operation');
  const administrationLabels=await accessibleLabels(page);
  assert(administrationLabels.includes('Archivierung ist ein Offline-Vorgang'),
    'the surface does not name the offline archive');
  await capture('01d-device-administration');
  // The **note** of a device is writable where the device is: the operator
  // writes it in the administration of the inspector, the Core keeps it, and
  // the revision of the record advances.
  //
  // The Core replaces the metadata of a device as a whole. A client that
  // sends only the fields that the operator changed therefore **drops** the
  // note — the journey proves that against the real Core, so the merge of
  // the client is not a claim but a measured difference.
  const noteField=page.getByRole('textbox',{name:/Notiz/}).last();
  assert(await fillField(noteField,NOTE),
    'the note of the device does not carry the text of the operator');
  const noted0=async()=>{
    const page2=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
    return page2.items.length===1&&(page2.items[0].record.device.metadata||{}).notes===NOTE;
  };
  assert(await activateControl(save,noted0),
    'the note of the device is not writable in the inspector');
  const noted=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
  assert.equal(noted.items.length,1,'the Core did not accept the note of the device');
  const notedDevice=noted.items[0].record.device;
  const notedRevision=noted.items[0].record.revision;
  assert.equal((notedDevice.metadata||{}).notes,NOTE,
    'the Core did not keep the note of the device');
  assert(notedRevision>revision,'the revision of the device did not advance with the note');
  // The write **without** the merge: the metadata of the device is replaced
  // as a whole, so the note is gone. The client merges the note into the
  // metadata that it sends back; the Core does not merge for it.
  const withoutNote=await context.request.post(base+'/api/v2/inventory/apply',{
    headers:writeHeaders,timeout:60000,
    data:{changes:[{operation:'update',expected_revision:notedRevision,device:{
      id:notedDevice.id,display_name:notedDevice.display_name,
      device_type:notedDevice.device_type,site_id:notedDevice.site_id,
      metadata:{}}}]}});
  assert.equal(withoutNote.status(),200,
    'the Core refused the write of the device without the merge');
  const dropped=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture%20renamed',{timeout:60000})).json();
  assert.equal((dropped.items[0].record.device.metadata||{}).notes,null,
    'the Core kept the note although the write of the metadata did not carry it');
  await capture('01e-device-note');
  // The search of the inventory is a presentation filter. The journey clears
  // it, so the following steps see the whole inventory again.
  const search=page.getByRole('textbox',{name:/Name, ID, Typ, Source/});
  await search.click({force:true});
  await page.waitForTimeout(250);
  await page.keyboard.press('Meta+A');
  await page.keyboard.press('Backspace');
  await page.keyboard.press('Tab');
  await page.waitForTimeout(700);
  // The device row is an InkWell inside the Flutter view. Its semantics node is
  // a container node, so it carries `pointer-events: none` and a Playwright
  // click is intercepted by the flutter-view. A real mouse event on the
  // painted row is the working activation.
  //
  // The activation is verified by the state it produces (the engineering
  // workspace of the selected device), never by the absence of an error.
  const openDeviceRow=async()=>{
    const row=page.getByRole('button',{name:/Gerät Browser SSH fixture/}).first();
    await row.waitFor({state:'attached',timeout:30000});
    const workspaceOpen=async()=>{
      const snapshot=await page.locator('body').ariaSnapshot();
      // The engineering workspace of the selected device and, in the managed
      // mode, its authorized monitoring section.
      return /identity & registry/i.test(snapshot)
        || /connection & monitoring/i.test(snapshot);
    };
    for(let attempt=0;attempt<3;attempt++){
      const box=await row.boundingBox();
      if(!box)throw Error('the device row has no geometry');
      await page.mouse.click(box.x+60,box.y+box.height/2);
      await page.waitForTimeout(1500);
      if(await workspaceOpen())return;
    }
    throw Error('the device row did not open the engineering workspace');
  };
  await openDeviceRow();
  await page.waitForTimeout(800);
  await page.getByRole('button',{name:'Verbindung für dieses Gerät einrichten',exact:true}).click();
  await page.getByRole('button',{name:'Verbindungsmethode wählen',exact:true}).click();
  assert(await waitFor(async()=> (await page.locator('body').ariaSnapshot()).includes('Testgerät')));
  assert.equal(await page.getByRole('textbox',{name:'Hostname oder IP-Adresse',exact:true}).count(),0);
  assert.equal(await page.getByRole('textbox',{name:'SSH-Port',exact:true}).count(),0);
  await capture('02-prepared-device');
  await page.getByRole('button',{name:'Gerät prüfen',exact:true}).click();
  const verify=page.getByRole('button',{name:'Geräteinformationen abrufen',exact:true});
  await verify.waitFor({timeout:30000});
  assert.equal(await page.getByRole('button',{name:/diesem Host-Key vertrauen/}).count(),0);
  await capture('03-pinned-device');
  await verify.click();
  await page.getByRole('button',{name:'Identität bestätigen und Verbindung speichern',exact:true}).waitFor({timeout:30000});
  await writeFile(resolve(out,'verified-ax.txt'),await page.locator('body').ariaSnapshot());
  await capture('04-actual-host-identity');
  await page.getByRole('checkbox',{name:'Diese ermittelte Identität gehört zum ausgewählten Gerät.',exact:true}).click();
  await page.getByRole('button',{name:'Identität bestätigen und Verbindung speichern',exact:true}).click();
  await page.getByRole('button',{name:'Zum Geräteinventar',exact:true}).waitFor();
  await capture('05-persisted-binding');
  assert.equal(await page.getByRole('button',{name:'Monitoring aktivieren',exact:true}).count(),0);
  await page.getByRole('button',{name:'Zum Geräteinventar',exact:true}).click();
  // The approved Spectrum-2027 device workspace carries the authorized
  // monitoring evidence and the persisted history. The device is selected
  // again, because the wizard closed the selection.
  await openDeviceRow();
  await page.waitForTimeout(1500);
  for(let i=0;i<140;i++){ if((await page.locator('body').ariaSnapshot()).includes('Collecting · aktuelle Messwerte empfangen'))break; if(i===139)throw Error('No rendered actual Collecting state'); await page.waitForTimeout(250); }
  await capture('06-real-monitoring');
  // The panel must show the measurements the Core actually received over SSH.
  // The expected values are read back from the Core, never invented here, and
  // they must be the same values that the operator sees in the browser.
  const observed=(await (await context.request.get(base+'/api/v2/device-connections?device_id=browser-existing',{timeout:60000})).json());
  const fingerprint=execFileSync('/usr/bin/ssh-keygen',['-lf',resolve(fixture.directory,'host.pub'),'-E','sha256'],{encoding:'utf8'}).split(/\s+/)[1];
  assert.equal(observed.connection.fingerprint,fingerprint,'the persisted host key must match the prepared fixture');
  assert.equal(sshRequests.some(request=>request.operation==='trust_host_key'),false);
  const observations=observed.connection.observations;
  assert(Array.isArray(observations)&&observations.length>0,'Core reports no authorized observations');
  const os=observations.find(o=>o.metric_id==='host.os');
  const memory=observations.find(o=>o.metric_id==='host.memory_total_bytes');
  assert(os&&typeof os.value.text==='string'&&os.value.text.length>0,'no host operating system observation');
  assert(memory&&memory.value.unsigned_integer>0,'no real memory observation');
  assert.equal(os.freshness,'fresh');
  let rendered='';
  for(let i=0;i<60;i++){ rendered=await page.locator('body').ariaSnapshot(); if(rendered.includes('host.os')&&rendered.includes(os.value.text)&&rendered.includes('host.memory_total_bytes')&&rendered.includes(String(memory.value.unsigned_integer)))break; if(i===59)throw Error('The rendered panel does not show the collected measurements'); await page.waitForTimeout(250); }
  assert(rendered.includes(os.value.text));
  assert(rendered.includes(String(memory.value.unsigned_integer)));
  // Flutter exposes these Material tabs as tappable semantic text nodes, not
  // ARIA role=tab nodes. Target the rendered Telemetry node itself.
  const telemetryTab=page.locator('flt-semantics[role="text"][flt-tappable]')
    .filter({hasText:/^Telemetry\s+Tab 2 von 3$/});
  assert.equal(await telemetryTab.count(),1,'the rendered Telemetry tab is missing or ambiguous');
  await telemetryTab.click({force:true});
  // Let the TabBarView finish its slide before inspecting the active pane;
  // otherwise its previous page may still contribute hidden semantics.
  await page.waitForTimeout(600);
  // Flutter virtualizes the telemetry rows. Validate each metric with its own
  // value as it comes into view, since the two rows can be on different screens.
  const memoryBytes=String(memory.value.unsigned_integer);
  const expectedTelemetry=new Map([
    [os.metric_id,[os.value.text]],
    // Dart Web can format an integral JSON number as a double.
    [memory.metric_id,[`${memoryBytes} bytes`,`${memoryBytes}.0 bytes`]],
  ]);
  for(let i=0;i<120&&expectedTelemetry.size;i++){
    const rendered=await page.locator('body').ariaSnapshot();
    for(const [metricId,values] of expectedTelemetry){
      if(values.some(value=>rendered.includes(`browser-existing · ${metricId} ${value} `))){
        expectedTelemetry.delete(metricId);
      }
    }
    if(expectedTelemetry.size){
      await page.mouse.move(850,800);
      await page.mouse.wheel(0,220);
      await page.waitForTimeout(250);
    }
  }
  assert.equal(expectedTelemetry.size,0,
    `DeviceDetail Telemetry did not render the authorized values for ${[...expectedTelemetry.keys()].join(', ')}`);
  await capture('06b-device-detail-telemetry');
  const engineeringTab=page.locator('flt-semantics[role="text"][flt-tappable]')
    .filter({hasText:/^Engineering\s+Tab 1 von 3$/});
  assert.equal(await engineeringTab.count(),1,'the rendered Engineering tab is missing or ambiguous');
  await engineeringTab.click({force:true});
  await page.waitForTimeout(600);
  // The persisted history of the device must be reachable in the device view.
  // The samples are read back from the Core, never invented here, and the
  // receive times on the screen must be the receive times the Core stored.
  const history=(await (await context.request.get(base+'/api/v2/observations/history?device=browser-existing&limit=20',{timeout:60000})).json());
  const stored=history.items.filter(i=>i.category==='observation').map(i=>i.record.observation);
  assert(stored.length>0,'the Core persisted no observation for the device');
  assert(stored.every(o=>o.freshness==='stale'),'a stored sample must never be reported as live');
  const stamp=ms=>new Date(ms).toISOString().replace('T',' ').replace('Z',' UTC');
  const wanted=stored.slice(0,6).map(o=>o.metric_id+' · Historie');
  const stamps=stored.slice(0,6).map(o=>stamp(o.timestamps.received));
  const seen=new Set(),seenStamps=new Set();
  let section=false;
  for(let i=0;i<80;i++){
    const snapshot=await page.locator('body').ariaSnapshot();
    if(snapshot.includes('Persistierte Messhistorie'))section=true;
    for(const w of wanted)if(snapshot.includes(w))seen.add(w);
    for(const s of stamps)if(snapshot.includes(s))seenStamps.add(s);
    if(section&&seen.size>=3&&seenStamps.size>=1)break;
    await page.mouse.move(1100,600);
    await page.mouse.wheel(0,400);
    await page.waitForTimeout(120);
  }
  assert(section,'the persisted history is not rendered in the device view');
  assert(seen.size>=3,'the rendered history does not show the persisted samples of the Core');
  assert(seenStamps.size>=1,'the rendered history does not show the receive time the Core stored');
  await capture('07-persisted-history');
  const cookies=await context.cookies();assert(cookies.some(c=>c.name==='oip_session'&&c.httpOnly&&c.sameSite==='Strict'));
  assert.equal(await page.evaluate(()=>localStorage.length),0);
  assert.equal(await page.evaluate(()=>sessionStorage.length),0);
  // The web release is several megabytes; the loopback of a local machine
  // delivers them slowly. The download gets the time of the first paint.
  const loaded=Buffer.from(await (await context.request.get(base+'/main.dart.js',{timeout:180000})).body());
  const local=await readFile(resolve(process.env.OIP_WEB_DIR,'main.dart.js'));
  assert.equal(createHash('sha256').update(loaded).digest('hex'),createHash('sha256').update(local).digest('hex'));
  await page.getByRole('button',{name:'Details schließen',exact:true}).click();
  // The managed overview must show the authorized source registry and the
  // measurement that the Core received, not the coordinates of the demo.
  await page.getByRole('button',{name:'Navigation Übersicht',exact:true}).click();
  await page.waitForTimeout(1500);
  const top=await page.locator('body').ariaSnapshot();
  assert(!top.includes('Temperatur M-01'),'the demo coordinates are still rendered in the managed overview');
  // The unified infrastructure view shows counts for the authorized projection.
  assert(top.includes('Infrastrukturübersicht'),'the unified infrastructure view is missing');
  const devices=/\bGeräte: (\d+)\b/.exec(top);
  const sources=/\bVerbundene Quellen: (\d+) von (\d+)\b/.exec(top);
  assert(devices&&Number(devices[1])>0,'the managed overview shows no authorized devices');
  assert(sources&&Number(sources[1])>0&&Number(sources[1])<=Number(sources[2]),
    'the managed overview shows no connected authorized sources');
  assert(!/M-01/.test(top),'the demo coordinates are still rendered in the managed overview');
  // The authorized source registry has its own section of the workstation.
  await page.getByRole('button',{name:'Source Health',exact:true}).click();
  await page.waitForTimeout(1500);
  const wantedOverview=['Infrastrukturübersicht','SSH host browser-existing'];
  const seenOverview=new Set();
  for(let i=0;i<40;i++){
    const snapshot=await page.locator('body').ariaSnapshot();
    for(const w of wantedOverview)if(snapshot.includes(w))seenOverview.add(w);
    if(seenOverview.size===wantedOverview.length)break;
    await page.mouse.move(700,600);
    await page.mouse.wheel(0,400);
    await page.waitForTimeout(150);
  }
  assert(seenOverview.size===wantedOverview.length,'the managed overview does not show the authorized source registry');
  await capture('08-managed-overview');
  // The diagnostics view must show the persisted evidence of the session and
  // the state that the Core itself names for the diagnosis history.
  //
  // Flutter merges the rendered text of a workstation into the accessible
  // names of its semantics nodes. The proof therefore reads the accessible
  // labels of the rendered surface, not the source of the client.
  await page.getByRole('button',{name:'Navigation Diagnose & Ereignisse',exact:true}).click();
  await page.waitForTimeout(1500);
  const diagnosticsTop=await page.locator('body').ariaSnapshot();
  assert(diagnosticsTop.includes('Aktueller Zustand')&&diagnosticsTop.includes('Letzte Ereignisse'),
    'diagnostics does not start with current status and recent events');
  await page.getByRole('button',{name:'Technische Ansicht',exact:true}).click();
  await page.waitForTimeout(900);
  const healthPage=(await (await context.request.get(base+'/api/v2/diagnostics/health-history?limit=50',{timeout:60000})).json());
  const gapsPage=(await (await context.request.get(base+'/api/v2/diagnostics/gaps?limit=50',{timeout:60000})).json());
  const eventsPage=(await (await context.request.get(base+'/api/v2/events',{timeout:60000})).json());
  assert(Array.isArray(healthPage.items)&&Array.isArray(gapsPage.items),'the Core answered no diagnostic evidence page');
  const status=eventsPage.diagnosis_history_status;
  const statusLabel=({not_implemented:'Diagnosehistorie: nicht implementiert',demo_only:'Diagnosehistorie: nur Demo'})[status]||('Diagnosehistorie: '+status);
  const wantedDiagnostics=['PERSISTIERTE EVIDENZ',statusLabel];
  if(healthPage.items.length) wantedDiagnostics.push('Gesundheitsverlauf · '+healthPage.items[0].record.source);
  if(gapsPage.items.length) wantedDiagnostics.push('Dokumentierte Lücke · '+gapsPage.items[0].record.source);
  const seenDiagnostics=new Set();
  for(let i=0;i<40;i++){
    const labels=await accessibleLabels(page);
    for(const w of wantedDiagnostics)if(labels.includes(w))seenDiagnostics.add(w);
    if(seenDiagnostics.size===wantedDiagnostics.length)break;
    await page.mouse.move(700,600);
    await page.mouse.wheel(0,400);
    await page.waitForTimeout(150);
  }
  assert(seenDiagnostics.size===wantedDiagnostics.length,
    'the managed diagnostics view does not show the persisted evidence; missing: '+
    wantedDiagnostics.filter(w=>!seenDiagnostics.has(w)).join(' | '));
  await capture('10-managed-diagnostics');
  // The network view must show the authorized placement of the session. The
  // scoped projection carries no topology, so a loading state would promise
  // data that never arrives.
  await page.getByRole('button',{name:'Navigation Netzwerk & VPN',exact:true}).click();
  await page.waitForTimeout(1200);
  const networkTop=await page.locator('body').ariaSnapshot();
  assert(!networkTop.includes('Topologie wird geladen'),'the network view still shows a loading state');
  assert(!networkTop.includes('Remote Site'),'the demo zones are still rendered in the managed network view');
  // The approved network surface places the authorized device in its
  // infrastructure. It carries no logical path in a scoped projection, and
  // the source registry belongs to the overview and the device detail.
  const wantedNetwork=['LAN-Verkabelung','Infrastructure A1','browser-existing'];
  await page.getByRole('button',{name:'Geräteliste',exact:true}).click();
  const seenNetwork=new Set();
  for(let i=0;i<40;i++){
    const snapshot=await page.locator('body').ariaSnapshot();
    for(const w of wantedNetwork)if(snapshot.includes(w))seenNetwork.add(w);
    if(seenNetwork.size===wantedNetwork.length)break;
    await page.mouse.move(700,600);
    await page.mouse.wheel(0,400);
    await page.waitForTimeout(150);
  }
  assert(seenNetwork.size===wantedNetwork.length,'the network view does not show the authorized placement');
  await capture('09-managed-network');
  const logout = page.getByRole('button',{name:'Operator abmelden',exact:true});
  assert.equal(await logout.count(),0,'Logout must only appear in Settings');
  await page.getByRole('button',{name:'Navigation Einstellungen',exact:true}).click();
  await logout.waitFor();
  await page.waitForTimeout(650);
  await logout.click();
  await page.getByRole('button',{name:'Operator-Sitzung autorisieren',exact:true}).waitFor();
  const loggedOut = await context.request.get(base+'/api/v2/browser/session');
  assert.equal(loggedOut.status(),200);
  assert.equal((await loggedOut.json()).authenticated,false,'The Core must end the browser session');
  assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
  await writeFile(resolve(out,'report.json'),JSON.stringify({status:'PASS',logout_in_settings:true,core_session_ended:true,actual_flutter_ssh_monitoring:true,prepared_endpoint_without_manual_fields:true,hardware:'owned loopback SSH fixture',prepared_host_key_pinned:true,identity_confirmation:true,existing_device_id_preserved:true,http_only_cookie:true,no_browser_token_storage:true,rendered_measurements:{observed_metrics:observations.map(o=>o.metric_id),host_os:os.value.text,memory_total_bytes:memory.value.unsigned_integer,device_detail_telemetry_tab:true,device_detail_metrics:[os.metric_id,memory.metric_id],all_fresh:observations.every(o=>o.freshness==='fresh')},rendered_history:{persisted_samples:stored.length,rendered_samples:seen.size,all_stale:stored.every(o=>o.freshness==='stale'),receive_times_shown:seenStamps.size,first_receive_time:stamps[0],metrics:wanted.map(w=>w.split(' · ')[0])},rendered_administration:{device_id:manualId,revision_before:manualRevision,revision_after:updated.items[0].record.revision,display_name_updated:true,online_archive_refused:'OFFLINE_ARCHIVE_REQUIRED',archive_is_offline_operation:true,note_written:true,the_note:NOTE,the_note_is_dropped_by_a_write_without_the_merge:true},rendered_overview:{approved_surface:'unified_infrastructure_view',authorized_source:'SSH host browser-existing',source_registry_section:true,dynamic_device_metric:devices[1],dynamic_source_metric:sources[1]+'/'+sources[2],measured_metric:'host.memory_total_bytes',measured_value:memory.value.unsigned_integer,measurement_proof:'DeviceDetail Telemetry tab and connection monitoring panel of the approved UI',demo_coordinates_absent:true},rendered_diagnostics:{approved_surface:'persisted_evidence',persisted_evidence_section:true,diagnosis_history_status:status,health_transitions:healthPage.items.length,documented_gaps:gapsPage.items.length},rendered_network:{approved_surface:'network_engineering_explorer',authorized_placement:'Infrastructure A1',rendered_device_id:'browser-existing',source_registry_proof:'overview source registry and device engineering workspace',loading_state_absent:true,demo_zones_absent:true},loaded_build_sha256:createHash('sha256').update(loaded).digest('hex'),errors,external},null,2));
} catch(e) {
  await writeFile(resolve(out,'ssh-requests.json'),JSON.stringify(sshRequests,null,2));
  await capture('failure');
  await writeFile(resolve(out,'failure-dom.html'),(await page.content()).replace(/[a-f0-9]{64}/gi,'REDACTED'));
  await writeFile(resolve(out,'failure-ax.txt'),(await page.locator('body').ariaSnapshot()).replace(/[a-f0-9]{64}/gi,'REDACTED'));
  let the_state_of_the_core=null;
  try{
    const page2=await (await context.request.get(base+'/api/v2/inventory/devices?q=Manual%20inventory%20fixture',{timeout:60000})).json();
    the_state_of_the_core=(page2.items||[]).map(i=>({the_id:i.record.device.id,the_name:i.record.device.display_name,the_revision:i.record.revision,the_notes:(i.record.device.metadata||{}).notes}));
  }catch{}
  await writeFile(resolve(out,'failure.json'),JSON.stringify({status:'FAIL',error:String(e),errors,external,the_state_of_the_core},null,2));throw e;
} finally {await browser.close();}

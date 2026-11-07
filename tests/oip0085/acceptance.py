#!/usr/bin/env python3
"""Real zero-source onboarding, scoped REST/official MCP, atomic import and crash recovery.
Reuses process/client definitions only from0082; no mocked authorization or runtime.
"""
import ast,pathlib,json,os,subprocess,time,hashlib,concurrent.futures,signal,csv
ROOT=pathlib.Path(__file__).resolve().parents[2];base=ROOT/'tests/oip0082/acceptance.py';nodes=[]
for n in ast.parse(base.read_text(),filename=str(base)).body:
 if isinstance(n,ast.Try):break
 nodes.append(n)
ns={'__file__':str(base),'__name__':'oip85_helpers'};exec(compile(ast.Module(body=nodes,type_ignores=[]),str(base),'exec'),ns);globals().update({k:v for k,v in ns.items() if not k.startswith('__')})
OUT=pathlib.Path(os.environ.get('OIP_EVIDENCE_DIR',ROOT/'target/oip0085-e2e'));OUT.mkdir(parents=True,exist_ok=True);ns['OUT']=OUT
config['sources']=[];config['web_dir']=None;(RUN/'core.json').write_text(json.dumps(config));plan=json.loads((ROOT/'examples/multi-infrastructure-plan.json').read_text());plan['sources']=[];plan['bindings']=[b for b in plan['bindings'] if b['scope']['kind']!='source'];plan['roles'].append({'id':'inventory-admin','name':'Explicit isolated test operator','permissions':['devices_read','inventory_manage','settings_read','settings_write','mcp_management_read']});plan['bindings'].append({'principal_id':'platform-reader','role_id':'inventory-admin','scope':{'kind':'platform'}});plan['principals'].append({'id':'inventory-org-a','name':'Scoped inventory operator test','enabled':True});plan['bindings'].append({'principal_id':'inventory-org-a','role_id':'inventory-admin','scope':{'kind':'organization','id':'org-a'}});TOKENS['inventory-org-a']=__import__('secrets').token_bytes(32);credential=RUN/'inventory-org-a.credential';credential.write_bytes(TOKENS['inventory-org-a']);credential.chmod(0o600);ipc=json.loads((RUN/'ipc.json').read_text());ipc['clients'].append({'uid':os.geteuid(),'credential_file':str(credential),'policy':{'principal':'inventory-org-a'}});(RUN/'ipc.json').write_text(json.dumps(ipc));(RUN/'ipc.json').chmod(0o600);(RUN/'plan.json').write_text(json.dumps(plan));REPORT.update(baseline='f9969f0a21f2885a8b6c4695b3c105ad28708d33',stacked_on_oip0084=True)
def apply(changes,do_apply=True,p='platform-reader',ok=True):
 file=RUN/('inventory-'+str(time.time_ns())+'.json');file.write_text(json.dumps({'principal':p,'changes':changes}));cmd=[BIN,'--config',RUN/'core.json','--inventory-plan',file]+(['--inventory-apply'] if do_apply else []);proc=start('inventory-cli-'+str(time.time_ns()),cmd);proc.wait(timeout=15);assert (proc.returncode==0)==ok,(proc.returncode,cmd)
 return proc

def device(id,site,name='A manually entered host',kind='server'):
 return {'id':id,'display_name':name,'device_type':kind,'site_id':site,'metadata':{'description':'Operator fixture; no collector','ip_address':'192.0.2.8','tags':['local-test']}}
def register(d):return {'operation':'register','device':d}
def inv(p='reader-org-a',query=''):return get('/api/v2/inventory/devices'+query,p)
def keys():return {t:sql('SELECT * FROM '+t+' ORDER BY rowid') for t in ['inventory_devices','settings','organizations','infrastructures','sites']}
def model_honest(v):
 assert v['items'];assert all(not d['sources'] and d['connectivity']=='unknown' and d['telemetry']=='no_collector' and d['health']=='not_evaluated' and not d['monitoring_simulated'] for d in v['items'])
try:
 d=start('empty-normal',[BIN,'--database',DB,'--port',HTTP,'--no-web']);wait(lambda:req('/api/v2/installation/status',None)[0]==200,'normal empty installation')
 empty=get('/api/v2/installation/status',None);assert empty['status']=='No infrastructure configured' and empty['items']==[];assert sql('SELECT count(*) n FROM source_identities')[0]['n']==0 and count()==0 and sql('SELECT count(*) n FROM collection_events')[0]['n']==0
 assert req('/api/v2/inventory/devices',None)[0]==403;stop(d);record('01_empty_normal_runtime',{'devices':0,'sources':0,'observations':0,'events':0,'simulator_started':False})
 p=start('provision-personal-fixture',[BIN,'--config',RUN/'core.json','--provision',RUN/'plan.json']);assert p.wait(timeout=15)==0
 # Empty schema7 was initialized by the actual normal runtime, no implicit demo hierarchy.
 assert sql('PRAGMA user_version')[0]['user_version']==7
 d=daemon('empty-provisioned');wait(lambda:req('/api/v2/inventory/devices')[0]==200,'provisioned empty inventory');assert inv()['status']=='No devices registered';assert req('/api/v2/installation/status',None)[0]==403;assert get('/api/v2/sources')==[];stop(d)
 first=device('manual-first','site-a1','AMD EVO-X2','single_board_computer');body=[register(first)];before=hashlib.sha256(DB.read_bytes()).hexdigest();apply(body,False);assert hashlib.sha256(DB.read_bytes()).hexdigest()==before
 apply(body,p='inventory-org-a');apply(body,p='inventory-org-a');assert sql('SELECT count(*) n FROM inventory_devices')[0]['n']==1;assert sql('SELECT count(*) n FROM inventory_audit')[0]['n']==1
 d=daemon('first-device');wait(lambda:len(inv()['items'])==1,'first device persisted');model_honest(inv());A=Client('reader-org-a','first-device-sdk');assert A.call('inventory_read')==inv();assert A.call('device_read',{'id':'manual-first'})['metrics']==[];A.close();stop(d)
 restarted_before=keys();d=daemon('first-device-restart');wait(lambda:len(inv()['items'])==1,'first full core restart');model_honest(inv());stop(d);assert keys()==restarted_before
 record('02_first_device_restart',{'registered_without_collector':True,'stable_id':'manual-first','name_does_not_determine_origin':True,'rest_sdk_parity':True,'unknown_no_collector':True})
 more=[register(device('manual-a2','site-a3','Site A2 laptop','laptop')),register(device('manual-b','site-b1','Organization B router','network_device')),register(device('manual-other','site-a1','Second local host','desktop'))];apply(more)
 conflict=[register(device('should-rollback','site-a1')),register(device('manual-first','site-a1','Conflicting replacement'))];apply(conflict,ok=False);assert sql("SELECT count(*) n FROM inventory_devices WHERE id='should-rollback'")[0]['n']==0
 apply([register(device('foreign-attempt','site-b1'))],p='reader-org-a',ok=False)
 apply([register(device('foreign-admin-attempt','site-b1'))],p='inventory-org-a',ok=False)
 rejected_secret=__import__('secrets').token_hex(32);badmeta=RUN/'bad-metadata.json';badmeta.write_text(json.dumps({'password':rejected_secret}));badmeta.chmod(0o600)
 denied=subprocess.run(['python3',str(ROOT/'tests/oip0085/onboard.py'),'add','--config',str(RUN/'core.json'),'--principal','platform-reader','--site','site-a1','--name','Invalid metadata input','--type','server','--metadata',str(badmeta),'--apply'],cwd=ROOT,capture_output=True,text=True);assert denied.returncode!=0 and rejected_secret not in denied.stdout+denied.stderr
 changed=json.loads(json.dumps(first));changed['display_name']='Operator-renamed host';changed['metadata']['tags']=['updated'];apply([{'operation':'update','device':changed,'expected_revision':1}]);apply([{'operation':'update','device':first,'expected_revision':1}],ok=False)
 metadata_before=sql("SELECT metadata_json FROM inventory_devices WHERE id='manual-first'")[0]['metadata_json']
 p=start('helper-rename-preserves-metadata',['python3',ROOT/'tests/oip0085/onboard.py','update','--config',RUN/'core.json','--principal','platform-reader','--id','manual-first','--revision',2,'--name','CLI rename only','--apply']);assert p.wait(timeout=15)==0;assert sql("SELECT metadata_json FROM inventory_devices WHERE id='manual-first'")[0]['metadata_json']==metadata_before
 apply([{'operation':'archive','id':'manual-other','expected_revision':1}]);assert sql('SELECT count(*) n FROM inventory_devices')[0]['n']==4
 # Exercise the actual CSV frontend: duplicate ID handling is delegated to typed Rust validation.
 csv_file=RUN/'import.csv'
 with csv_file.open('w',newline='') as f:
  writer=csv.DictWriter(f,fieldnames=['id','display_name','device_type','site_id','description']);writer.writeheader();writer.writerow({'id':'csv-host','display_name':'Imported host','device_type':'server','site_id':'site-a1','description':'Pure CSV fixture'})
 cmd=['python3',ROOT/'tests/oip0085/onboard.py','import','--config',RUN/'core.json','--principal','platform-reader','--file',csv_file]
 p=start('csv-dry-run',cmd);assert p.wait(timeout=15)==0;assert sql("SELECT count(*) n FROM inventory_devices WHERE id='csv-host'")[0]['n']==0
 p=start('csv-apply',cmd+['--apply']);assert p.wait(timeout=15)==0
 p=start('csv-idempotent',cmd+['--apply']);assert p.wait(timeout=15)==0
 # Retain an actual settings value through inventory writes/restart/crash.
 setting=RUN/'setting.json';setting.write_text(json.dumps({'principal':'platform-reader','scope':{'kind':'platform'},'key':'instance_name','value':{'type':'text','value':'Real inventory fixture'},'expected_revision':0}));p=start('setting-save',[BIN,'--config',RUN/'core.json','--settings-change',setting]);assert p.wait(timeout=15)==0
 inspect=RUN/'inspect.json';inspect.write_text(json.dumps({'principal':'platform-reader'}));before=DB.read_bytes();p=start('cleanup-dry-run',[BIN,'--config',RUN/'core.json','--inventory-cleanup-plan',inspect]);assert p.wait(timeout=15)==0;assert DB.read_bytes()==before
 d=daemon('multi-organization-inventory');wait(lambda:len(inv()['items'])==3,'scoped inventory ready')
 assert {v['record']['device']['id'] for v in inv('reader-org-a')['items']}=={'manual-first','manual-a2','csv-host'};assert {v['record']['device']['id'] for v in inv('reader-infra-a1')['items']}=={'manual-first','csv-host'};assert {v['record']['device']['id'] for v in inv('reader-org-b')['items']}=={'manual-b'}
 assert inv(query='?q=imported')['items'][0]['record']['device']['id']=='csv-host';assert inv(query='?limit=1')['has_more'];assert len(inv(query='?limit=1&offset=1')['items'])==1;assert len(inv(query='?include_archived=true')['items'])==4
 for path in ['/api/v2/inventory/devices?id=manual-b','/api/v2/inventory/devices?site=site-b1','/api/v2/inventory/devices?organization=org-b','/api/v2/devices/manual-b']:
  assert req(path,'reader-org-a')[0] in [403,404]
 for path in ['/api/v2/inventory/devices?limit=101','/api/v2/inventory/devices?source=%20source-a%20','/api/v2/inventory/devices?principal=platform-reader']:
  assert req(path)[0] in [400,404]
 clients=[Client(p,'inventory-client-'+str(i)) for i,p in enumerate(['reader-org-a','reader-infra-a1','reader-org-b','reader-site-a1','platform-reader','inventory-org-a','reader-infra-a1','reader-org-b'])];admin=clients[4]
 for c in clients:
  assert c.call('inventory_read')==inv(c.principal);c.denied('inventory_change',{'principal':'platform-reader'});c.denied('inventory_read',{'principal':'platform-reader'})
 assert admin.call('inventory_plan_read',{'changes':[{'operation':'archive','id':'csv-host','expected_revision':1}]})['applied']==False
 clients[5].denied('mcp_management_read',{});clients[5].denied('inventory_plan_read',{'changes':[register(device('foreign-plan','site-b1'))]});clients[0].denied('inventory_plan_read',{'changes':[register(device('unauthorized','site-a1'))]});clients[0].denied('inventory_read',{'id':'manual-b'})
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:assert all(pool.map(lambda c:bool(c.call('inventory_read')['items']),clients))
 clients[0].abort();assert d.poll() is None;assert admin.call('inventory_read')['items']
 for c in clients:c.close()
 assert get('/api/v2/sources','platform-reader')==[] and count()==0 and sql('SELECT count(*) n FROM collection_events')[0]['n']==0
 apply([register(device('running-write','site-a1'))],ok=False);stop(d)
 stored=keys();d=daemon('inventory-full-restart');wait(lambda:len(inv()['items'])==3,'restart');model_honest(inv());assert get('/api/v2/settings','platform-reader')['settings'][0]['effective']['value']=='Real inventory fixture';stop(d,True)
 d=daemon('inventory-crash-restore');wait(lambda:len(inv()['items'])==3,'crash restore');model_honest(inv());assert sql("SELECT count(*) n FROM core_runs WHERE result='interrupted'")[0]['n']>=1;stop(d);assert keys()==stored
 assert sql('PRAGMA integrity_check')[0]['integrity_check']=='ok' and sql('PRAGMA foreign_key_check')==[];assert sql('SELECT count(*) n FROM source_identities')[0]['n']==0
 record('03_multi_org_import_auth_crash',{'devices_preserved':5,'archived_retained':1,'active_org_a':3,'active_org_b':1,'mcp_clients':8,'csv_dry_run_apply_idempotent':True,'settings_preserved':True,'restart_and_sigkill':True,'fake_sources_or_events':0})
 # Actual source association lives in a DIFFERENT disposable installation, not the normal onboarding DB.
 assoc=RUN/'association';assoc.mkdir(mode=0o700);assoc_db=assoc/'db.sqlite';assoc_cfg=json.loads(json.dumps(config));assoc_cfg.update(database=str(assoc_db),http_port=port());assoc_plan=json.loads(json.dumps(plan));assoc_cfg['sources']=[]
 (assoc/'core.json').write_text(json.dumps(assoc_cfg));(assoc/'plan.json').write_text(json.dumps(assoc_plan));(assoc/'operator.json').write_text(json.dumps({'principal':'platform-reader'}));p=start('assoc-provision',[BIN,'--config',assoc/'core.json','--provision',assoc/'plan.json']);assert p.wait(timeout=15)==0;p=start('assoc-initialize',[BIN,'--config',assoc/'core.json','--inventory-initialize',assoc/'operator.json']);assert p.wait(timeout=15)==0
 target=device('device-a','site-a1','Explicit source association fixture');reqfile=assoc/'register.json';reqfile.write_text(json.dumps({'principal':'platform-reader','changes':[register(target),register(device('unassociated','site-a1'))]}));p=start('assoc-register',[BIN,'--config',assoc/'core.json','--inventory-plan',reqfile,'--inventory-apply']);assert p.wait(timeout=15)==0
 original=json.loads((ROOT/'examples/multi-infrastructure-core.json').read_text());sp=port();assoc_cfg['sources']=[original['sources'][0]];assoc_cfg['sources'][0]['endpoint']=f'opc.tcp://127.0.0.1:{sp}';assoc_plan['sources']=[json.loads((ROOT/'examples/multi-infrastructure-plan.json').read_text())['sources'][0]];assoc_plan['bindings'].append({'principal_id':'reader-source-b','role_id':plan['bindings'][0]['role_id'],'scope':{'kind':'source','id':'source-a'}})
 # Bind source-only reader to existing explicit read role, never to admin role.
 assoc_plan['bindings'][-1]['role_id']=next(b['role_id'] for b in plan['bindings'] if b['principal_id']=='reader-org-a')
 (assoc/'core.json').write_text(json.dumps(assoc_cfg));(assoc/'plan.json').write_text(json.dumps(assoc_plan));p=start('assoc-bind-source',[BIN,'--config',assoc/'core.json','--provision',assoc/'plan.json']);assert p.wait(timeout=15)==0
 assoc_ipc=json.loads((RUN/'ipc.json').read_text());assoc_ipc['socket']=str(assoc/'s');(assoc/'ipc.json').write_text(json.dumps(assoc_ipc));(assoc/'ipc.json').chmod(0o600)
 simproc=start('assoc-real-simulator',[SIM,'--port',sp,'--seed',42,'--tick-ms',250]);ad=start('assoc-daemon',[BIN,'--daemon','--config',assoc/'core.json','--ipc-config',assoc/'ipc.json'])
 import urllib.request
 def assoc_get(path,p='reader-org-a'):
  with urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{assoc_cfg['http_port']}"+path,headers={'Authorization':'Bearer '+TOKENS[p].hex()}),timeout=4) as r:return json.load(r)
 wait(lambda:assoc_get('/api/v2/sources')[0]['freshness']=='fresh','associated source actual reception')
 associated=assoc_get('/api/v2/inventory/devices')['items'][0];assert all(associated['record']['device'][k]==v for k,v in target.items() if k!='metadata') and all(associated['record']['device']['metadata'][k]==v for k,v in target['metadata'].items()) and associated['record']['origin']=='manual_operator' and associated['sources']==['source-a'] and associated['telemetry']=='receiving' and associated['connectivity']=='unknown' and associated['monitoring_simulated']
 (OUT/'association-snapshot.json').write_text(json.dumps(associated,indent=2));assert {r['record']['device']['id'] for r in assoc_get('/api/v2/inventory/devices','reader-source-b')['items']}=={'device-a'}
 stop(ad);stop(simproc);assert sql('SELECT count(*) n FROM core_sources')[0]['n']==0
 record('04_separate_actual_source_association',{'same_device_identity':True,'source_origin':'simulation_test_only','receiving_after_actual_observations':True,'device_connectivity_not_inferred':True,'normal_inventory_database_sources':0})
 REPORT.update(status='PASS',schema=7)
except Exception:
 REPORT['status']='FAIL';raise
finally:
 for c in CLIENTS:
  try:c.close()
  except Exception:pass
 for p in reversed(PROCS):
  if p.poll() is None:p.send_signal(signal.SIGINT)
  try:p.wait(timeout=15)
  except subprocess.TimeoutExpired:p.kill();p.wait()
 REPORT['own_processes_stopped']=all(p.poll() is not None for p in PROCS);(OUT/'report.json').write_text(json.dumps(REPORT,indent=2))

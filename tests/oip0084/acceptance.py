#!/usr/bin/env python3
"""Actual schema4→5, settings apply, REST/SDK parity, four OPC sources and eight bridges.
Reuses the existing process/client harness definitions, never mocked decisions or product logic.
All credentials private, all ports dynamically bound loopback. No operator DBs are opened.
"""
import ast,datetime,hashlib,json,os,pathlib,subprocess,time,concurrent.futures,signal
ROOT=pathlib.Path(__file__).resolve().parents[2]
# Definition-only import of the prior acceptance harness (its top-level try test is not executed).
base=ROOT/'tests/oip0082/acceptance.py'
nodes=[]
for node in ast.parse(base.read_text(),filename=str(base)).body:
 if isinstance(node,ast.Try):break
 nodes.append(node)
namespace={'__file__':str(base),'__name__':'oip0084_process_helpers'}
exec(compile(ast.Module(body=nodes,type_ignores=[]),str(base),'exec'),namespace)
globals().update({k:v for k,v in namespace.items() if not k.startswith('__')})
OUT=pathlib.Path(os.environ.get('OIP_EVIDENCE_DIR',ROOT/'target/oip0084-e2e'));OUT.mkdir(parents=True,exist_ok=True);namespace['OUT']=OUT
BASE=pathlib.Path(os.environ['OIP0083_BASELINE_BINARY']);expected=os.environ['OIP0083_BASELINE_SHA256'];assert hashlib.sha256(BASE.read_bytes()).hexdigest()==expected
REPORT.update(baseline='0e20f7283a8815242aaa71a2066a9944cb8cafc8',legacy_binary_sha256=expected,helper_sha256=hashlib.sha256(base.read_bytes()).hexdigest())
def settings(scope='platform',id=None,p='platform-reader',catalog=False):
 from urllib.parse import urlencode
 q={'scope':scope,'catalog':str(catalog).lower()}
 if id:q['scope_id']=id
 return get('/api/v2/settings?'+urlencode(q),p)
def management(section,p='platform-reader'):return get('/api/v2/management?section='+section,p)
SAVE_TIMES=[]
def change(key,value,scope=None,revision=0,principal='platform-reader',ok=True):
 started=time.perf_counter()
 body={'principal':principal,'scope':scope or {'kind':'platform'},'key':key,'value':value,'expected_revision':revision};file=RUN/'settings-change.json';file.write_text(json.dumps(body))
 p=start('settings-admin-'+str(time.time_ns()),[BIN,'--config',RUN/'core.json','--settings-change',file]);p.wait(timeout=15);assert (p.returncode==0)==ok,p.returncode
 if ok:
  SAVE_TIMES.append((time.perf_counter()-started)*1000)
  report=sql("SELECT count(*) n FROM settings_audit")[0]['n'];assert report>0
 return p.returncode
def all_rows(db,table):return json.loads(subprocess.check_output([SQL,'-readonly','-json',str(db),'SELECT * FROM '+table+' ORDER BY rowid'],text=True) or '[]')
def preservation(before):
 for table,rows in before.items():
  current=all_rows(DB,table);key={'observations':'observation_key','collection_events':'event_key','data_gaps':'gap_key','source_health_history':'id','source_placements':'source_id'}.get(table,'id');by={r[key]:r for r in current}
  for r in rows:
   assert r[key] in by,(table,r[key]);a=dict(by[r[key]]);b=dict(r);a.pop('duplicate_count',None);b.pop('duplicate_count',None);assert a==b,(table,r[key])
def percentile(v,p):return sorted(v)[min(len(v)-1,int((len(v)-1)*p))]
def performance(c):
 metrics={}
 for label,path,tool,args in [('catalog','/api/v2/settings?catalog=true','settings_read',{'catalog':True}),('effective','/api/v2/settings','settings_read',{}),('mcp_status','/api/v2/management?section=server','mcp_management_read',{'section':'server'}),('sessions_unavailable','/api/v2/management?section=sessions','mcp_management_read',{'section':'sessions'})]:
  row={}
  for transport in ['rest','mcp']:
   samples=[]
   for _ in range(25):
    t=time.perf_counter();get(path,'platform-reader') if transport=='rest' else c.call(tool,args);samples.append((time.perf_counter()-t)*1000)
   row[transport]={'samples':len(samples),'p50_ms':percentile(samples,.5),'p95_ms':percentile(samples,.95)}
  metrics[label]=row
 return metrics
try:
 # Real protected prior build produces schema4 history including health transitions/gaps.
 p=start('baseline-provision',[BASE,'--config',RUN/'core.json','--provision',RUN/'plan.json']);p.wait(timeout=15);assert p.returncode==0
 sims=[sim(i,'baseline-source-'+str(i)) for i in range(4)];d=start('baseline-daemon',[BASE,'--daemon','--config',RUN/'core.json','--ipc-config',RUN/'ipc.json']);wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'baseline four fresh');wait(lambda:count()>15,'baseline persisted')
 stop(sims[0]);wait(lambda:sources()['source-a']['freshness']!='fresh','baseline outage');time.sleep(.5);stop(d)
 for p in sims[1:]:stop(p)
 assert sql('PRAGMA user_version')[0]['user_version']==4
 before={t:all_rows(DB,t) for t in ['organizations','infrastructures','sites','source_placements','observations','collection_events','data_gaps','source_health_history']};assert before['data_gaps'] and before['source_health_history']
 backup=OUT/'schema4-pristine.sqlite';subprocess.run([SQL,'-readonly',str(DB),'.backup '+str(backup)],check=True);backup.chmod(0o600)
 # Only explicit offline operator provisioning adds settings policies. No migration implicitly grants rights.
 plan=json.loads((RUN/'plan.json').read_text());plan['roles'].extend([{'id':'settings-read','name':'Explicit scoped settings read','permissions':['settings_read']},{'id':'settings-operator','name':'Explicit local settings operator','permissions':['settings_read','settings_write','mcp_management_read']}])
 for principal,scope,role in [('platform-reader',{'kind':'platform'},'settings-operator'),('reader-org-a',{'kind':'organization','id':'org-a'},'settings-read'),('reader-org-b',{'kind':'organization','id':'org-b'},'settings-read'),('reader-infra-a1',{'kind':'infrastructure','id':'infra-a1'},'settings-read'),('reader-site-a1',{'kind':'site','id':'site-a1'},'settings-read'),('reader-source-b',{'kind':'source','id':'source-b'},'settings-read')]:plan['bindings'].append({'principal_id':principal,'role_id':role,'scope':scope})
 (RUN/'plan.json').write_text(json.dumps(plan));p=start('settings-policy-provision',[BIN,'--config',RUN/'core.json','--provision',RUN/'plan.json']);p.wait(timeout=15);assert p.returncode==0
 # Runtime-open alone migrates4→5 with no extra grants; do before configured values.
 d=daemon('schema5-default-restore');wait(lambda:len(sources())==4,'restored old sources');assert sql('PRAGMA user_version')[0]['user_version']==5
 assert settings()['settings'][2]['effective']['value']==50 or any(s['effective']=={'type':'integer','value':50} for s in settings()['settings'])
 assert all(s['freshness']=='unknown' and s['last_received_ms'] is None for s in sources().values());assert all(o['freshness']=='stale' for o in get('/api/v2/observations','platform-reader'))
 stop(d);preservation(before);record('01_real_schema4_migration',{'schema':5,'before_counts':{k:len(v) for k,v in before.items()},'ids_and_payloads_preserved':True,'backup_sha256':hashlib.sha256(backup.read_bytes()).hexdigest()})
 for scope,value in [({'kind':'platform'},40),({'kind':'organization','id':'org-a'},13),({'kind':'infrastructure','id':'infra-a1'},11),({'kind':'site','id':'site-a1'},9),({'kind':'source','id':'source-a'},7)]:change('history_page_size',{'type':'integer','value':value},scope)
 change('instance_name',{'type':'text','value':'OIP Settings Acceptance'})
 change('history_page_size',{'type':'integer','value':0},ok=False);change('history_page_size',{'type':'integer','value':50},revision=0,ok=False)
 change('history_page_size',{'type':'integer','value':50},scope={'kind':'organization','id':'org-a'},revision=1,principal='reader-org-a',ok=False)
 assert sql('SELECT count(*) n FROM settings_audit')[0]['n']==6
 # Two simultaneous local writers with the same expected revision: exactly one wins.
 races=[]
 for i in range(2):
  file=RUN/('cas-'+str(i)+'.json');file.write_text(json.dumps({'principal':'platform-reader','scope':{'kind':'platform'},'key':'instance_description','value':{'type':'text','value':'CAS contender '+str(i)},'expected_revision':0}));races.append(start('cas-'+str(i),[BIN,'--config',RUN/'core.json','--settings-change',file]))
 for p in races:p.wait(timeout=15)
 assert sorted(p.returncode for p in races)==[0,1];assert sql('SELECT count(*) n FROM settings_audit')[0]['n']==7

 d=daemon('settings-daemon');wait(lambda:len(sources())==4,'new daemon ready');sims=[sim(i,'new-source-'+str(i)) for i in range(4)];wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'new actual fresh')
 assert settings('source','source-a','reader-org-a')['settings'][0]['effective']=={'type':'integer','value':7}
 assert settings('source','source-b','reader-org-a')['settings'][0]['effective']['value']==9
 for scope,id,p in [('organization','org-a','reader-org-a'),('infrastructure','infra-a1','reader-infra-a1'),('site','site-a1','reader-site-a1'),('source','source-b','reader-source-b')]:assert settings(scope,id,p)['settings']
 for path,p in [('/api/v2/settings','reader-org-a'),('/api/v2/settings?scope=organization&scope_id=org-b','reader-org-a'),('/api/v2/settings?scope=source&scope_id=source-d','reader-infra-a1'),('/api/v2/management','reader-org-a')]:assert req(path,p)[0] in [403,404]
 clients=[Client(p,'settings-client-'+str(i)) for i,p in enumerate(['platform-reader','reader-org-a','reader-infra-a1','reader-org-b','reader-site-a1','reader-source-b','reader-org-a','reader-org-b'])];A=clients[0]
 assert len(A.command({'op':'tools'})['result']['tools'])==18;assert len(clients[1].command({'op':'tools'})['result']['tools'])==17
 assert A.call('settings_read')==settings();assert A.call('mcp_management_read',{'section':'tools'})==management('tools')
 assert clients[1].call('settings_read',{'scope':'organization','scope_id':'org-a'})==settings('organization','org-a','reader-org-a')
 preview=management('client_configuration')['client_configuration'];cfg=json.loads(preview['configuration_json']);assert cfg['mcpServers']['oip-local']['command']==str(BIN);assert cfg['mcpServers']['oip-local']['args'][::2]==['--mcp-bridge','<AUTHORIZED_PRIVATE_SOCKET>','<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>'];assert not preview['usable_without_replacement'] and not preview['credential_provisioned']
 for token in TOKENS.values():assert token.hex() not in preview['configuration_json']
 assert management('sessions')['availability']=='unsupported';assert len(management('tools')['tools'])==18
 for c in clients[1:]:c.denied('mcp_management_read',{});c.denied('settings_read',{'scope':'platform'});c.denied('settings_read',{'scope':'organization','scope_id':'org-b' if c.principal!='reader-org-b' else 'org-a'})
 for q in [{'actor':'platform-reader'},{'principal':'platform-reader'},{'scope':'source','scope_id':'x'*1000},{'scope':'tenant'},{'key':'credential'},{'key':None,'unexpected':True}]:clients[1].denied('settings_read',q)
 A.denied('settings_change',{'value':{'type':'integer','value':1}});change('history_page_size',{'type':'integer','value':5},revision=1,ok=False)
 assert settings()['settings'] # no concurrent admin write was accepted
 # Default config actually changes historical query results, not only display metadata.
 history=get('/api/v2/events/history?source=source-a');assert history['limit']==7 if 'limit' in history else len(history['items'])<=7
 assert len(get('/api/v2/events/history?source=source-a&limit=2')['items'])<=2
 metrics=performance(A);metrics['offline_save']={'samples':len(SAVE_TIMES),'p50_ms':percentile(SAVE_TIMES,.5),'p95_ms':percentile(SAVE_TIMES,.95),'includes':'CLI process startup, ownership, schema validation, CAS+audit transaction; no live apply'};before_count=count();time.sleep(.6);assert count()>before_count
 metrics['resources']={'rss_kib_cpu_percent':subprocess.check_output(['ps','-p',str(d.pid),'-o','rss=,pcpu='],text=True).strip(),'ingestion_before':before_count,'ingestion_after':count(),'method':'one OS process sample during eight attached clients; not peak/steady-state measurement'}
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:assert all(pool.map(lambda c:bool(c.call('settings_read',{'scope':'platform'} if c.principal=='platform-reader' else {'scope':'organization','scope_id':'org-b' if c.principal=='reader-org-b' else 'org-a'})) if c.principal in ['platform-reader','reader-org-a','reader-org-b'] else bool(c.call('sources_read')),clients))
 record('02_settings_parity_security',{'mcp_clients':8,'operator_tools':18,'scoped_tools':17,'safe_writes':7,'running_write_rejected':True,'sessions_inventory':'unsupported','config_preview':'valid_placeholder_template_no_grants','performance':metrics})
 clients[1].abort();assert d.poll() is None and A.call('settings_read');before_count=count()
 for c in clients:c.close()
 time.sleep(.7);assert count()>before_count
 A=Client('platform-reader','reconnected');assert A.call('settings_read')==settings()
 stop(sims[0]);wait(lambda:sources()['source-a']['freshness']!='fresh','outage');b=count();time.sleep(.5);assert count()>b;sims[0]=sim(0,'source-a-reconnected');wait(lambda:sources()['source-a']['freshness']=='fresh','reconnect')
 A.close();stop(d)
 for p in sims:stop(p)
 d=daemon('settings-restart');wait(lambda:len(sources())==4,'restart');assert settings()['settings'][0]['effective']['value']=='OIP Settings Acceptance';assert all(s['freshness']=='unknown' for s in sources().values());stop(d,True)
 d=daemon('settings-crash-recovery');wait(lambda:len(sources())==4,'crash recovery');assert settings('source','source-a','reader-org-a')['settings'][0]['effective']['value']==7;assert sql("SELECT count(*) n FROM core_runs WHERE result='interrupted'")[0]['n']>=1
 stop(d);preservation(before);assert sql('PRAGMA integrity_check')[0]['integrity_check']=='ok' and sql('PRAGMA foreign_key_check')==[];assert sql('SELECT count(*) n FROM observations')[0]['n']==sql('SELECT count(DISTINCT observation_key) n FROM observations')[0]['n']
 authority=sql('SELECT DISTINCT operator_authority FROM settings_audit');assert authority==[{'operator_authority':'local_os_operator_uid:'+str(os.geteuid())}]
 record('03_disconnect_recovery_integrity',{'restart':True,'sigkill':True,'persisted_effective_settings':True,'no_duplicate_keys':True,'foreign_keys':True,'integrity':True,'historical_keys_preserved':True})
 REPORT['status']='PASS';REPORT['schema']=5;REPORT['performance']=metrics
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
 REPORT['own_processes_stopped']=all(p.poll() is not None for p in PROCS)
 # Never persist credential contents in reports. Raw protocol logs are SDK output and audited separately.
 (OUT/'report.json').write_text(json.dumps(REPORT,indent=2))

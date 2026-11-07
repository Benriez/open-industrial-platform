#!/usr/bin/env python3
"""Generate genuine schema5 evidence with the protected0084 binary, upgrade without loss.
All data are isolated simulation fixtures; source provenance is never relabeled as manual.
"""
import ast,pathlib,json,os,subprocess,hashlib,time,signal
ROOT=pathlib.Path(__file__).resolve().parents[2];base=ROOT/'tests/oip0082/acceptance.py';nodes=[]
for n in ast.parse(base.read_text(),filename=str(base)).body:
 if isinstance(n,ast.Try):break
 nodes.append(n)
ns={'__file__':str(base),'__name__':'migration85_helpers'};exec(compile(ast.Module(body=nodes,type_ignores=[]),str(base),'exec'),ns);globals().update({k:v for k,v in ns.items() if not k.startswith('__')})
OUT=pathlib.Path(os.environ.get('OIP_EVIDENCE_DIR',ROOT/'target/oip0085-migration'));OUT.mkdir(parents=True,exist_ok=True);ns['OUT']=OUT
BASE=pathlib.Path(os.environ['OIP0084_BASELINE_BINARY']);digest=hashlib.sha256(BASE.read_bytes()).hexdigest();assert digest==os.environ['OIP0084_BASELINE_SHA256'];REPORT.update(baseline='f9969f0a21f2885a8b6c4695b3c105ad28708d33',baseline_binary_sha256=digest)
plan=json.loads((RUN/'plan.json').read_text());plan['roles'].append({'id':'settings-bootstrap','name':'Explicit baseline fixture settings','permissions':['settings_write','settings_read','mcp_management_read']});plan['bindings'].append({'principal_id':'platform-reader','role_id':'settings-bootstrap','scope':{'kind':'platform'}});(RUN/'plan.json').write_text(json.dumps(plan))
try:
 p=start('schema5-provision',[BASE,'--config',RUN/'core.json','--provision',RUN/'plan.json']);assert p.wait(timeout=15)==0
 sims=[sim(i,'schema5-source-'+str(i)) for i in range(4)];d=start('schema5-daemon',[BASE,'--daemon','--config',RUN/'core.json','--ipc-config',RUN/'ipc.json']);wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'four schema5 sources');wait(lambda:count()>15,'actual persisted observations');stop(sims[0]);wait(lambda:sources()['source-a']['freshness']!='fresh','actual outage');stop(d)
 for p in sims[1:]:stop(p)
 setting=RUN/'setting.json';setting.write_text(json.dumps({'principal':'platform-reader','scope':{'kind':'platform'},'key':'history_page_size','value':{'type':'integer','value':17},'expected_revision':0}));p=start('schema5-setting',[BASE,'--config',RUN/'core.json','--settings-change',setting]);assert p.wait(timeout=15)==0
 assert sql('PRAGMA user_version')[0]['user_version']==5
 tables=['organizations','infrastructures','sites','source_placements','principals','read_roles','role_bindings','settings','settings_audit','observations','collection_events','data_gaps','source_health_history']
 before={t:sql('SELECT * FROM '+t+' ORDER BY rowid') for t in tables};assert before['observations'] and before['data_gaps'] and before['source_health_history'] and before['settings']
 backup=OUT/'schema5-pristine.sqlite';subprocess.run([SQL,'-readonly',str(DB),'.backup '+str(backup)],check=True);backup.chmod(0o600)
 dry=RUN/'dry.json';dry.write_text(json.dumps({'principal':'platform-reader','changes':[]}));physical=DB.read_bytes();p=start('schema5-dry-run-no-migration',[BIN,'--config',RUN/'core.json','--inventory-plan',dry]);assert p.wait(timeout=15)!=0;assert DB.read_bytes()==physical and sql('PRAGMA user_version')[0]['user_version']==5
 d=daemon('schema6-upgrade');wait(lambda:len(sources())==4,'schema6 startup');assert sql('PRAGMA user_version')[0]['user_version']==7
 inventory=get('/api/v2/inventory/devices','platform-reader')['items'];assert len(inventory)==4
 assert {r['record']['device']['id'] for r in inventory}=={r['device_id'] for r in before['source_placements']}
 assert all(r['record']['origin']=='existing_simulation_source' and r['record']['device']['device_type']=='other' and r['record']['created_ms'] is None and r['record']['registered_by'] is None for r in inventory)
 assert get('/api/v2/settings','platform-reader')['settings'][2]['effective']['value']==17
 assert all(o['freshness']=='stale' for o in get('/api/v2/observations','platform-reader'))
 stop(d)
 for table,rows in before.items():
  current=sql('SELECT * FROM '+table+' ORDER BY rowid')
  assert all(r in current for r in rows),(table,len(rows),len(current))
 ledger=sql('SELECT version,checksum FROM schema_migrations ORDER BY version');assert [r['version'] for r in ledger]==[1,2,3,4,5,6,7]
 assert sql('PRAGMA foreign_key_check')==[] and sql('PRAGMA integrity_check')[0]['integrity_check']=='ok'
 d=daemon('idempotent-reopen');wait(lambda:len(sources())==4,'idempotent reopen');stop(d);assert sql('SELECT count(*) n FROM inventory_devices')[0]['n']==4
 REPORT.update(status='PASS',schema=7,preserved_tables={t:len(rows) for t,rows in before.items()},history_ids_payloads_settings_and_policies_preserved=True,source_origins_preserved=True,no_fabricated_old_timestamps=True,dry_run_schema5_unchanged=True,foreign_keys=True,integrity=True,ledger=ledger,backup_sha256=hashlib.sha256(backup.read_bytes()).hexdigest())
 print('PASS genuine schema5→7 migration, historical identities and settings preserved',flush=True)
except Exception:
 REPORT['status']='FAIL';raise
finally:
 for p in reversed(PROCS):
  if p.poll() is None:p.send_signal(signal.SIGINT)
  try:p.wait(timeout=15)
  except subprocess.TimeoutExpired:p.kill();p.wait()
 REPORT['own_processes_stopped']=all(p.poll() is not None for p in PROCS);(OUT/'report.json').write_text(json.dumps(REPORT,indent=2))

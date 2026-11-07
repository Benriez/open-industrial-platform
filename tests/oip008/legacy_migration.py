#!/usr/bin/env python3
"""Migrate a genuinely generated OIP-007 schema2 DB using the preserved baseline binary."""
import hashlib,json,os,pathlib,signal,socket,subprocess,time
R=pathlib.Path(__file__).resolve().parents[2];D=pathlib.Path('/private/tmp')/('oip8-legacy-'+str(os.getpid()));D.mkdir(mode=0o700);O=R/'target/oip008-legacy';O.mkdir(exist_ok=True)
# The schema2 writer has to be a protected OIP-007 binary. The canonical binary is only the
# default so that an accidental run without the protected baseline stays visibly wrong.
BASE=pathlib.Path(os.environ.get('OIP007_BASELINE_BINARY','/Users/benny/Code/open-industrial-platform/target/debug/oip-server'));NEW=R/'target/debug/oip-server';SIM=R/'target/debug/oip-simulated-server';SQL='/opt/homebrew/opt/sqlite/bin/sqlite3';DB=D/'legacy.sqlite';P=[];report={'baseline_binary_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest()}
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def start(name,args):
 f=(O/(name+'.log')).open('w');p=subprocess.Popen(list(map(str,args)),cwd=R,stdout=f,stderr=f);f.close();P.append(p);return p
def stop(p):
 if p.poll() is None:p.send_signal(signal.SIGINT)
 p.wait(timeout=20);assert p.returncode==0

def sql(q):return json.loads(subprocess.check_output([SQL,'-readonly','-json',DB,q],text=True) or '[]')
def run(name,args,ok=True):
 p=start(name,args);p.wait(timeout=15);assert (p.returncode==0)==ok,(name,p.returncode);return (O/(name+'.log')).read_text()
try:
 pa,pb,http=port(),port(),port();cfg={'database':str(DB),'http_port':http,'web_dir':None,'sources':[{'id':'source-a','name':'source-a','endpoint':f'opc.tcp://127.0.0.1:{pa}'},{'id':'source-b','name':'source-b','endpoint':f'opc.tcp://127.0.0.1:{pb}'}]};(D/'core.json').write_text(json.dumps(cfg))
 sims=[start('sim-'+str(i),[SIM,'--port',port_, '--tick-ms',250,'--seed',42+i]) for i,port_ in enumerate([pa,pb])];core=start('baseline-core',[BASE,'--config',D/'core.json','--no-web'])
 deadline=time.monotonic()+30
 while time.monotonic()<deadline:
  try:
   if len(sql('select distinct data_source_id from observations'))==2:break
  except (subprocess.CalledProcessError,KeyError):pass
  time.sleep(.1)
 else:raise AssertionError('legacy ingestion')
 stop(core)
 for s in sims:stop(s)
 assert sql('pragma user_version')[0]['user_version']==2
 # These test-owned files were created by OIP-007's older mode defaults.
 for f in [DB,pathlib.Path(str(DB)+'.oip-lock')]:f.chmod(0o600)
 before=sql('select observation_key from observations order by observation_key');counts=sql('select (select count(*) from observations) observations,(select count(*) from collection_events) events,(select count(*) from data_gaps) gaps')[0]
 text=run('inspect',[NEW,'--config',D/'core.json','--inspect-legacy']);evidence=json.loads(text);assert not evidence['confirms_single_infrastructure'];(D/'adoption.json').write_text(json.dumps(evidence))
 plan=json.loads((R/'examples/multi-infrastructure-plan.json').read_text());plan['organizations']=plan['organizations'][:1];plan['infrastructures']=plan['infrastructures'][:1];plan['sites']=plan['sites'][:1];plan['sources']=plan['sources'][:2];plan['principals']=plan['principals'][:1];plan['bindings']=plan['bindings'][:1];plan['legacy_single_infrastructure']=True
 for i,s in enumerate(plan['sources']):s['device_id']='M-01' if i==0 else 'source-b:M-01'
 (D/'plan.json').write_text(json.dumps(plan));args=[NEW,'--config',D/'core.json','--provision',D/'plan.json','--adopt-legacy',D/'adoption.json']
 run('unattested-refused',args,False);assert sql('pragma user_version')[0]['user_version']==2
 evidence['confirms_single_infrastructure']=True;evidence['observations']+=1;(D/'adoption.json').write_text(json.dumps(evidence));run('changed-refused',args,False);assert sql('pragma user_version')[0]['user_version']==2
 evidence['observations']-=1;(D/'adoption.json').write_text(json.dumps(evidence));result=json.loads(run('migration',args));assert result['legacy_migrated'];assert sql('pragma user_version')[0]['user_version']==3;assert sql('select observation_key from observations order by observation_key')==before
 assert sql('pragma foreign_key_check')==[];assert sql('pragma integrity_check')[0]['integrity_check']=='ok';assert sql('select (select count(*) from observations) observations,(select count(*) from collection_events) events,(select count(*) from data_gaps) gaps')[0]==counts
 report.update(status='PASS',before_counts=counts,after_counts=counts,same_observation_keys=True,unattested_refused=True,changed_evidence_refused=True,migration=result,hierarchy=sql('select source_id,site_id,device_id from source_placements'))
except BaseException as e:report.update(status='FAIL',error=repr(e));raise
finally:
 for p in P:
  if p.poll() is None:p.send_signal(signal.SIGINT);p.wait(timeout=20)
 (O/'report.json').write_text(json.dumps(report,indent=2)+'\n')

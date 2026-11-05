#!/usr/bin/env python3
"""Real local four-source, three-principal acceptance. No model, mocks or remote hosts.
Runtime credentials/databases remain in private /private/tmp; sanitized report under target.
"""
import concurrent.futures,hashlib,json,os,pathlib,select,secrets,signal,socket,subprocess,threading,time,urllib.request,urllib.error
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'target'/'oip0082-migration';OUT.mkdir(parents=True,exist_ok=True)
RUN=pathlib.Path('/private/tmp')/('oip82-migration-'+str(os.getpid()));RUN.mkdir(mode=0o700)
BIN=ROOT/'target/debug/oip-server';SDK=ROOT/'target/debug/examples/mcp_probe';SIM=ROOT/'target/debug/oip-simulated-server';SQL='/opt/homebrew/opt/sqlite/bin/sqlite3'
PROCS=[];REPORT={'baseline':'79639ff42c68ee2ede34862929822a4789845268','phases':[],'runtime_directory':str(RUN),'model_used':False};CLIENTS=[]
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
PORTS=[port() for _ in range(4)];HTTP=port();URL=f'http://127.0.0.1:{HTTP}';DB=RUN/'core.sqlite';SOCK=RUN/'s'
config=json.loads((ROOT/'examples/multi-infrastructure-core.json').read_text());config.update(database=str(DB),http_port=HTTP,stale_after_ms=2000,shutdown_timeout_ms=6000)
for source,p in zip(config['sources'],PORTS):source['endpoint']=f'opc.tcp://127.0.0.1:{p}'
(RUN/'core.json').write_text(json.dumps(config));(RUN/'plan.json').write_bytes((ROOT/'examples/multi-infrastructure-plan.json').read_bytes())
TOKENS={p:secrets.token_bytes(32) for p in ['reader-org-a','reader-infra-a1','reader-org-b','reader-source-b','reader-site-a1','platform-reader']}
for p,t in TOKENS.items():f=RUN/(p+'.credential');f.write_bytes(t);f.chmod(0o600)
ipc={'socket':str(SOCK),'max_sessions':16,'clients':[{'uid':os.geteuid(),'credential_file':str(RUN/(p+'.credential')),'policy':{'principal':p}} for p in TOKENS]}
(RUN/'ipc.json').write_text(json.dumps(ipc));(RUN/'ipc.json').chmod(0o600)
def start(name,args,pipe=False):
 f=(OUT/(name+'.log')).open('w');p=subprocess.Popen(list(map(str,args)),cwd=ROOT,stdin=subprocess.PIPE if pipe else subprocess.DEVNULL,stdout=subprocess.PIPE if pipe else f,stderr=f,text=True,bufsize=1);f.close();PROCS.append(p);return p

def stop(p,crash=False):
 if p.poll() is None:p.send_signal(signal.SIGKILL if crash else signal.SIGINT)
 p.wait(timeout=25);assert p.returncode==(-signal.SIGKILL if crash else 0),(p.pid,p.returncode)
def wait(fn,label,timeout=35):
 begin=time.monotonic();last=None
 while time.monotonic()-begin<timeout:
  try:
   last=fn()
   if last:return last
  except (OSError,ValueError,KeyError,AssertionError,urllib.error.HTTPError):pass
  time.sleep(.05)
 raise AssertionError(label+': '+str(last))
def req(path,principal='reader-org-a',headers=None):
 h={} if principal is None else {'Authorization':'Bearer '+TOKENS[principal].hex()};h.update(headers or {})
 r=urllib.request.Request(URL+path,headers=h)
 try:
  with urllib.request.urlopen(r,timeout=4) as response:return response.status,json.load(response)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
def get(path,p='reader-org-a'):
 status,value=req(path,p);assert status==200,(path,status,value);return value
def sql(q):return json.loads(subprocess.check_output([SQL,'-readonly','-json',str(DB),q],text=True) or '[]')
def count():return sql('select count(*) n from observations')[0]['n']
def sse(p,old=None):
 headers={'Authorization':'Bearer '+TOKENS[p].hex()}
 if old:headers['Last-Event-ID']=old
 with urllib.request.urlopen(urllib.request.Request(URL+'/api/v2/stream',headers=headers),timeout=4) as r:
  cursor=None
  for line in r:
   if line.startswith(b'id:'):cursor=line[3:].strip().decode()
   if line.startswith(b'data:'):return cursor,json.loads(line[5:])
def record(name,details):REPORT['phases'].append({'phase':name,'status':'PASS','details':details});print('PASS',name,flush=True)
def receive(p,timeout=25):
 assert select.select([p.stdout],[],[],timeout)[0],('timeout',p.pid)
 line=p.stdout.readline();assert line,('closed',p.pid,p.poll());return json.loads(line)
class Client:
 def __init__(self,principal,name):
  self.principal=principal;self.p=start(name,[SDK,'modern',BIN,'--mcp-bridge','--ipc-socket',SOCK,'--ipc-credential',RUN/(principal+'.credential')],True);self.ready=receive(self.p);assert self.ready['ready'];CLIENTS.append(self)
 def command(self,body):self.p.stdin.write(json.dumps(body)+'\n');self.p.stdin.flush();return receive(self.p)
 def call(self,name,args=None):
  r=self.command({'op':'call','name':'oip_'+name,'arguments':args or {}});assert r['ok'] and not r['result'].get('isError'),r;return r['result']['structuredContent']['value']
 def resource(self,uri):
  r=self.command({'op':'resource','uri':uri});assert r['ok'],r;return json.loads(r['result']['contents'][0]['text'])['value']
 def denied(self,name,args):
  r=self.command({'op':'call','name':'oip_'+name,'arguments':args});assert not r['ok'] or r['result'].get('isError'),r;return r
 def close(self):
  if self.p.poll() is not None:return
  self.p.stdin.close();r=receive(self.p);assert r['closed'] and r['success'];self.p.wait(timeout=10);assert self.p.returncode==0
 def abort(self):os.kill(self.ready['pid'],signal.SIGKILL);self.p.stdin.close();self.p.wait(timeout=10)
def daemon(name):return start(name,[BIN,'--daemon','--config',RUN/'core.json','--ipc-config',RUN/'ipc.json'])
def sim(i,name):return start(name,[SIM,'--port',PORTS[i],'--seed',42+i*7,'--tick-ms',250])
def sources(p='platform-reader'):return {s['id']:s for s in get('/api/v2/sources',p)}
def parity(c):
 a={s['id']:s for s in c.call('sources_read')};b=sources(c.principal);assert set(a)==set(b)
 for k in a:
  for field in ['connection','reachability','service','freshness','validity']:assert a[k][field]==b[k][field],(field,a,b)
 return sorted(a)
def snapshot_scope(snapshot,expected):
 assert {s['id'] for s in snapshot['sources']}==set(expected)
 assert all(o['data_source_id'] in expected for o in snapshot['observations'])
 assert all(d['data_source_id'] in expected for d in snapshot['devices'])
 assert {l['source_id'] for l in snapshot['locations']}==set(expected)
 assert all(e['context']['data_source_id'] in expected for e in snapshot['events'])
 assert not any(k in snapshot for k in ['revision','run_id','queue','core','system','persisted_observations'])

import argparse
parser=argparse.ArgumentParser();parser.add_argument('--baseline-binary',required=True,type=pathlib.Path);parser.add_argument('--baseline-sha256',required=True);args=parser.parse_args();BASE=args.baseline_binary
assert hashlib.sha256(BASE.read_bytes()).hexdigest()==args.baseline_sha256
REPORT['baseline_binary_sha256']=args.baseline_sha256
try:
 provision=start('schema3-provision',[BASE,'--config',RUN/'core.json','--provision',RUN/'plan.json']);provision.wait(timeout=10);assert provision.returncode==0
 assert sql('pragma user_version')[0]['user_version']==3
 sims=[sim(i,'schema3-source-'+str(i)) for i in range(4)];d=start('schema3-daemon',[BASE,'--daemon','--config',RUN/'core.json','--ipc-config',RUN/'ipc.json']);wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'schema3 real ingestion')
 for p in sims:stop(p)
 stop(d)
 before={table:sql('select '+key+' from '+table+' order by '+key) for table,key in [('observations','observation_key'),('collection_events','event_key'),('data_gaps','gap_key')]}
 assert before['observations'] and before['collection_events'];counts={k:len(v) for k,v in before.items()}
 upgrade=start('schema4-upgrade',[BIN,'--config',RUN/'core.json','--provision',RUN/'plan.json']);upgrade.wait(timeout=10);assert upgrade.returncode==0
 assert json.loads((OUT/'schema4-upgrade.log').read_text())['schema_version']==3
 for table,key in [('observations','observation_key'),('collection_events','event_key'),('data_gaps','gap_key')]:assert sql('select '+key+' from '+table+' order by '+key)==before[table]
 assert sql('pragma user_version')[0]['user_version']==3 and sql('pragma foreign_key_check')==[]
 d=daemon('schema4-stale-restore');wait(lambda:len(sources())==4,'schema4 sources');assert sql('pragma user_version')[0]['user_version']==4
 for table,key in [('observations','observation_key'),('collection_events','event_key'),('data_gaps','gap_key')]:assert all(row in sql('select '+key+' from '+table+' order by '+key) for row in before[table])
 assert all(s['last_received_ms'] is None and s['freshness']=='unknown' for s in sources().values())
 assert all(o['freshness']=='stale' for o in get('/api/v2/observations','platform-reader'))
 sims=[sim(i,'schema4-source-'+str(i)) for i in range(4)];wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'fresh requires actual new receive')
 stop(d)
 for p in sims:stop(p)
 assert sql('pragma integrity_check')[0]['integrity_check']=='ok';REPORT.update(status='PASS',before_counts=counts,keys_preserved=True,foreign_keys=True,integrity=True,stale_restore=True,schema=4)
except BaseException as e:REPORT.update(status='FAIL',error=repr(e));raise
finally:
 for p in reversed(PROCS):
  if p.poll() is None:p.send_signal(signal.SIGINT);p.wait(timeout=20)
 REPORT['all_owned_processes_stopped']=all(p.poll() is not None for p in PROCS)
 (OUT/'report.json').write_text(json.dumps(REPORT,indent=2)+'\n')

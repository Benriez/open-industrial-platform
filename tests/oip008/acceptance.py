#!/usr/bin/env python3
"""Real local four-source, three-principal acceptance. No model, mocks or remote hosts.
Runtime credentials/databases remain in private /private/tmp; sanitized report under target.
"""
import concurrent.futures,hashlib,json,os,pathlib,select,secrets,signal,socket,subprocess,threading,time,urllib.request,urllib.error
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'target'/'oip008-e2e';OUT.mkdir(parents=True,exist_ok=True)
RUN=pathlib.Path('/private/tmp')/('oip8-'+str(os.getpid()));RUN.mkdir(mode=0o700)
BIN=ROOT/'target/debug/oip-server';SDK=ROOT/'target/debug/examples/mcp_probe';SIM=ROOT/'target/debug/oip-simulated-server';SQL='/opt/homebrew/opt/sqlite/bin/sqlite3'
PROCS=[];REPORT={'baseline':'a27e7b1e01dc1cb6f4d97c34319b0aa6d7321871','phases':[],'runtime_directory':str(RUN),'model_used':False};CLIENTS=[]
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
try:
 provision=start('provision',[BIN,'--config',RUN/'core.json','--provision',RUN/'plan.json']);provision.wait(timeout=10);assert provision.returncode==0
 same=start('provision-idempotent',[BIN,'--config',RUN/'core.json','--provision',RUN/'plan.json']);same.wait(timeout=10);assert same.returncode==0 and json.loads((OUT/'provision-idempotent.log').read_text())['idempotent']
 sims=[sim(i,'source-'+str(i)) for i in range(4)];d=daemon('daemon');wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'four fresh sources')
 assert len(sql('select distinct data_source_id from observations'))==4
 assert sql('pragma foreign_key_check')==[]
 assert sql('pragma integrity_check')[0]['integrity_check']=='ok'
 record('01_provision_ingestion',{'sources':sql('select p.source_id,p.site_id,s.infrastructure_id,i.organization_id,count(o.observation_key) samples from source_placements p join sites s on s.id=p.site_id join infrastructures i on i.id=s.infrastructure_id left join observations o on o.data_source_id=p.source_id group by p.source_id'),'ownership_private':oct(DB.stat().st_mode&0o777)})
 A=Client('reader-org-a','client-A');B=Client('reader-infra-a1','client-B');C=Client('reader-org-b','client-C')
 expected=[['source-a','source-b','source-c'],['source-a','source-b','source-c'],['source-d']]
 with concurrent.futures.ThreadPoolExecutor(3) as pool:result=list(pool.map(parity,[A,B,C]))
 assert result==expected
 for c,org in [(A,'org-a'),(B,'org-a'),(C,'org-b')]:
  assert [o['id'] for o in c.call('organizations_read')['items']]==[org]
  assert len(c.command({'op':'tools'})['result']['tools'])==18
  for resource in c.command({'op':'resources'})['result']['resources']:assert resource['uri'] not in ['oip://v1/core/health','oip://v1/snapshot/current','oip://v1/core/queue']
  allowed=expected[[A,B,C].index(c)];snapshot_scope(c.resource('oip://v2/snapshot/current'),allowed)
  devices=c.call('devices_read');assert {d['data_source_id'] for d in devices}==set(allowed)
  detail=c.call('device_read',{'id':devices[0]['id']});assert all(o['data_source_id']==devices[0]['data_source_id'] for o in detail['metrics'])
  assert all(o['data_source_id'] in allowed for o in c.call('observations_read'))
  assert all(e['context']['data_source_id'] in allowed for e in c.call('events_read')['records'])
 assert [i['id'] for i in B.call('infrastructures_read')['items']]==['infra-a1']
 assert [i['id'] for i in A.call('infrastructures_read')['items']]==['infra-a1','infra-a2']
 site=Client('reader-site-a1','client-site');source=Client('reader-source-b','client-source');assert len(site.call('sources_read'))==2;assert len(source.call('sources_read'))==1
 for c in [A,B,C]:
  own=c.call('sources_read')[0]['id'];page=c.call('opcua_nodes_read',{'source':own,'folder':'all','limit':100});assert page['limit']==100 and page['total']>=1000
 record('02_real_clients_scope_parity',{'principals':[c.principal for c in [A,B,C]],'source_sets':result,'tools':18,'node_page_limit':100})
 for c,args in [(B,{'infrastructure':'infra-b1'}),(C,{'site':'site-a1'}),(A,{'organization':'org-b'}),(A,{'source':'source-d'}),(source,{'source':'source-a'})]:c.denied('sources_read',args)
 for args in [{'principal':'platform-reader'},{'actor':'platform-reader'},{'permissions':['core_read']},{'sources':{'kind':'all'}},{'limit':101},{'offset':-1}]:B.denied('sources_read',args)
 B.denied('simulation_scenario_set',{'scenario':'offline'})
 # Malicious framing is tested with raw bytes, separately from real SDK interop.
 with socket.socket(socket.AF_UNIX) as attack:
  attack.settimeout(4);attack.connect(str(SOCK));attack.sendall(b'OIPIPC1\n'+TOKENS['reader-infra-a1']);assert attack.recv(1)==b'\x01';attack.sendall((json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'oversized':'x'*17000}})+'\n').encode());attack.sendall((json.dumps({'jsonrpc':'2.0','id':2,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'negative-frame-test','version':'1'}}})+'\n').encode());reply=attack.makefile('rb').readline();assert json.loads(reply)['id']==2
 assert d.poll() is None and C.call('sources_read')
 for path in ['/api/v2/sources?source=source-d','/api/v2/sources?source=missing']:
  status,value=req(path);assert status==404 and value['code']=='RESOURCE_NOT_ACCESSIBLE'
 for path in ['/api/v1/core/health','/api/v1/stream']:
  assert req(path)[0]==403
 assert req('/api/v2/sources',None)[0]==403
 assert req('/api/v2/sources',None,{'Authorization':'Bearer '+'00'*32})[0]==403
 for p,ids in [('reader-org-a',expected[0]),('reader-org-b',expected[2])]:
  cursor,snap=sse(p);snapshot_scope(snap,ids);_,again=sse(p,'forged-foreign-cursor');snapshot_scope(again,ids);assert len(cursor)==64
 record('03_negative_auth_sse',{'foreign_and_missing_same_error':True,'tampered_context_rejected':True,'sse_reconnect_scoped':True})
 before=count();A.abort();assert d.poll() is None;assert B.call('sources_read');assert C.call('sources_read');wait(lambda:count()>before,'after client abort');A=Client('reader-org-a','client-A-reconnect');assert parity(A)==expected[0]
 for c in CLIENTS:c.close()
 before=count();wait(lambda:count()>before+10,'ingestion without any clients');A=Client('reader-org-a','client-A-after-zero');assert parity(A)==expected[0]
 record('04_independent_lifecycle',{'before':before,'after':count(),'daemon_alive':d.poll() is None})
 # Real eight SDK clients and independent bridges, parallel source-scoped reads.
 for c in CLIENTS:c.close()
 poolclients=[Client(['reader-org-a','reader-infra-a1','reader-org-b'][i%3],'load-'+str(i)) for i in range(8)]
 measurements=[]
 for n in [1,3,8]:
  begin=time.perf_counter()
  with concurrent.futures.ThreadPoolExecutor(n) as pool:results=list(pool.map(parity,poolclients[:n]))
  measurements.append({'clients':n,'MCP_plus_REST_parallel_elapsed_ms':(time.perf_counter()-begin)*1000})
 record('05_eight_clients',{'measurements':measurements,'clients':len(results),'rss_cpu':subprocess.check_output(['ps','-p',str(d.pid),'-o','rss=,%cpu='],text=True).strip()})
 for c in poolclients:c.close()
 A=Client('reader-org-a','client-A-failure');C=Client('reader-org-b','client-C-failure')
 previous_c_events=C.call('events_read')['records']
 old=sources()['source-d']['accepted'];stop(sims[0]);wait(lambda:sources()['source-a']['connection']=='disconnected','source A offline');wait(lambda:sources()['source-d']['accepted']>old,'organization B progresses');assert parity(C)==['source-d'];assert C.call('events_read')['records']==previous_c_events;assert A.call('sources_read')[0]['freshness']=='stale'
 sims[0]=sim(0,'source-A-recovered');wait(lambda:sources()['source-a']['freshness']=='fresh','source A recovered');assert A.call('events_read')['records'];assert sql("select count(*) n from data_gaps where data_source_id='source-a'")[0]['n']>0
 record('06_source_failure_reconnect',{'B_independent':True,'gaps':sql('select data_source_id,count(*) n from data_gaps group by data_source_id')})
 for c in CLIENTS:c.close()
 for p in sims:stop(p)
 stop(d);total=count();d=daemon('daemon-restored');wait(lambda:len(sources())==4,'restore metadata');assert count()==total
 for s in sources().values():
  assert s['freshness']=='unknown' and s['reachability'] in ['unknown','unreachable'] and s['last_received_ms'] is None
  if s['reachability']=='unreachable':assert s['connection']=='disconnected' and s['last_error']
 A=Client('reader-org-a','client-stale');snapshot_scope(A.resource('oip://v2/snapshot/current'),expected[0]);assert all(o['freshness']=='stale' for o in A.call('observations_read'))
 sims=[sim(i,'source-restart-'+str(i)) for i in range(4)];wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'fresh after actual observations');A.close()
 record('07_restart_stale_restore',{'restored_count':total,'fresh_requires_receive':True,'restored_source_health_is_unknown':True})
 stop(d,True);d=daemon('daemon-crash-recovery');wait(lambda:all(s['freshness']=='fresh' for s in sources().values()),'crash recovery');assert sql("select count(*) n from core_runs where result='interrupted'")[0]['n']>=1;assert sql('pragma integrity_check')[0]['integrity_check']=='ok';assert sql('select count(*) n from (select observation_key,count(*) c from observations group by observation_key having c>1)')[0]['n']==0
 record('08_crash_recovery',{'runs':sql('select result,count(*) n from core_runs group by result'),'observations':count(),'hierarchy':sql('select count(*) n from organizations')})
 stop(d)
 for p in sims:stop(p)
 REPORT['status']='PASS'
except BaseException as error:
 REPORT['status']='FAIL';REPORT['error']=repr(error);raise
finally:
 for p in reversed(PROCS):
  if p.poll() is None:
   p.send_signal(signal.SIGINT)
   try:p.wait(timeout=12)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
 REPORT['all_owned_processes_stopped']=all(p.poll() is not None for p in PROCS)
 (OUT/'report.json').write_text(json.dumps(REPORT,indent=2)+'\n')

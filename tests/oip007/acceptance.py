#!/usr/bin/env python3
"""Model-free multi-client acceptance: real SDK clients → stdio bridges → UDS daemon.
Runtime fixtures/credentials stay in ignored target/, not transferable evidence.
"""
import concurrent.futures,hashlib,json,os,pathlib,select,signal,socket,subprocess,time,urllib.request,threading,statistics,secrets
ROOT=pathlib.Path(__file__).resolve().parents[2];OUT=ROOT/'docs/evidence/oip007/e2e';OUT.mkdir(parents=True,exist_ok=True)
RUN=ROOT/'target'/('i7-'+str(os.getpid()));RUN.mkdir(mode=0o700)
PROCS=[];TRANSCRIPT=[];REPORT={'phases':[],'processes':[],'model_used':False};SQLITE='/opt/homebrew/opt/sqlite/bin/sqlite3'
BIN=str(ROOT/'target/debug/oip-server');SDK=str(ROOT/'target/debug/examples/mcp_probe')
def freeport():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
PA,PB,HTTP=freeport(),freeport(),freeport();URL=f'http://127.0.0.1:{HTTP}';DB=RUN/'core.sqlite';SOCK=RUN/'s'
CONFIG={'database':str(DB),'http_port':HTTP,'sources':[{'id':'sim-a','name':'Simulation A','endpoint':f'opc.tcp://127.0.0.1:{PA}'},{'id':'sim-b','name':'Simulation B','endpoint':f'opc.tcp://127.0.0.1:{PB}'}],'web_dir':str(ROOT/'apps/flutter/build/web'),'stale_after_ms':2000,'queue_capacity':16,'shutdown_timeout_ms':6000}
(RUN/'core.json').write_text(json.dumps(CONFIG));ALL=json.loads((ROOT/'examples/mcp-read-local.json').read_text());CLIENTS=[];TOKENS={}
for name,scope in [('all',None),('a','sim-a'),('b','sim-b')]:
 p=dict(ALL,actor='ipc-client-'+name);p['sources']={'kind':'all'} if scope is None else {'kind':'only','sources':[scope]};token=secrets.token_bytes(32);TOKENS[name]=token;f=RUN/(name+'.credential');f.write_bytes(token);f.chmod(0o600);CLIENTS.append({'uid':os.geteuid(),'credential_file':str(f),'policy':p})
IPCCONFIG={'socket':str(SOCK),'max_sessions':16,'clients':CLIENTS,'rest_policy':dict(ALL,actor='local-rest-operator')};(RUN/'ipc.json').write_text(json.dumps(IPCCONFIG));(RUN/'ipc.json').chmod(0o600)
def start(name,argv,pipe=False):
 f=(OUT/(name+'.log')).open('w');p=subprocess.Popen(list(map(str,argv)),cwd=ROOT,stdin=subprocess.PIPE if pipe else subprocess.DEVNULL,stdout=subprocess.PIPE if pipe else f,stderr=f,text=True,bufsize=1,env=dict(os.environ,RUST_LOG='trace,rmcp::service=trace'));f.close();PROCS.append(p);REPORT['processes'].append({'name':name,'pid':p.pid,'argv':list(map(str,argv))});return p
def receive(p,timeout=25):
 if not select.select([p.stdout],[],[],timeout)[0]:raise AssertionError('client timeout '+str(p.pid))
 line=p.stdout.readline();assert line,('closed',p.pid,p.poll());v=json.loads(line);TRANSCRIPT.append({'pid':p.pid,'response':v});return v
class Client:
 def __init__(self,name,credential='all',legacy=False,standalone=False):
  args=[BIN,'--legacy-single-infrastructure','--config',str(RUN/'core.json'),'--mcp-stdio','--mcp-policy',str(ROOT/'examples/mcp-read-local.json')] if standalone else [BIN,'--mcp-bridge','--ipc-socket',str(SOCK),'--ipc-credential',str(RUN/(credential+'.credential'))]
  self.p=start(name,[SDK,'legacy' if legacy else 'modern']+args,True);self.lock=threading.Lock();self.ready=receive(self.p);assert self.ready['ready'];self.bridge_pid=self.ready['pid']
 def command(self,v):
  with self.lock:
   TRANSCRIPT.append({'pid':self.p.pid,'request':v});self.p.stdin.write(json.dumps(v)+'\n');self.p.stdin.flush();return receive(self.p)
 def call(self,name,args=None):
  r=self.command({'op':'call','name':'oip_'+name,'arguments':args or {}});assert r['ok'],r;assert not r['result'].get('isError'),r;return r['result']['structuredContent']['value']
 def resource(self,uri):
  r=self.command({'op':'resource','uri':uri});assert r['ok'],r;return json.loads(r['result']['contents'][0]['text'])['value']
 def close(self):
  self.p.stdin.close();r=receive(self.p);assert r['closed'] and r['success'];self.p.wait(timeout=10);assert self.p.returncode==0
 def abort(self):
  os.kill(self.bridge_pid,signal.SIGKILL);self.p.stdin.close();self.p.wait(timeout=10)
def stop(p,crash=False):
 if p.poll() is None:p.send_signal(signal.SIGKILL if crash else signal.SIGINT)
 p.wait(timeout=20)
 assert p.returncode==(-signal.SIGKILL if crash else 0),(p.pid,p.returncode)
def daemon(name):return start(name,[BIN,'--daemon','--legacy-single-infrastructure','--config',RUN/'core.json','--ipc-config',RUN/'ipc.json'])
def sim(name,p,seed,scenario='normal'):return start(name,[ROOT/'target/debug/oip-simulated-server','--port',p,'--seed',seed,'--tick-ms','250','--scenario',scenario])
def get(path):
 with urllib.request.urlopen(URL+path,timeout=3) as r:return json.load(r)
def sources():return {s['id']:s for s in get('/api/v1/sources')}
def sql(q):return json.loads(subprocess.check_output([SQLITE,'-readonly','-json',str(DB),q],text=True) or '[]')
def scalar(q):return next(iter(sql(q)[0].values()))
def wait(fn,label,timeout=35):
 start=time.monotonic();last=None
 while time.monotonic()-start<timeout:
  try:
   last=fn()
   if last:return last
  except (OSError,ValueError,KeyError,AssertionError):pass
  time.sleep(.05)
 raise AssertionError(label+' timed out: '+str(last))
def record(phase,data):REPORT['phases'].append({'phase':phase,'status':'PASS','details':data});print('PASS',phase,flush=True)
def parity(c):
 r=sources();m={s['id']:s for s in c.call('sources_read')};assert set(r)==set(m)
 for key in r:
  for field in ['connection','reachability','service','freshness','validity']:assert r[key][field]==m[key][field],(key,field,r,m)
 h=c.resource('oip://v1/core/health');assert h['run_id']==get('/api/v1/core/health')['run_id'];return {'run_id':h['run_id'],'sources':m}
def ui(op):
 u.stdin.write(json.dumps({'op':op})+'\n');u.stdin.flush();v=receive(u,30);assert v['ok'];return v
def sse():
 with urllib.request.urlopen(URL+'/api/v1/stream',timeout=3) as r:
  for line in r:
   if line.startswith(b'data:'):return json.loads(line[5:])
def ps(p):
 return subprocess.check_output(['ps','-p',str(p.pid),'-o','rss=,time=,%cpu='],text=True).strip()
try:
 a=sim('source-a',PA,42);b=sim('source-b',PB,77);d=daemon('daemon-first');wait(lambda:get('/api/v1/core/health')['lifecycle']=='ready','daemon sources ready');initial_run=get('/api/v1/core/health')['run_id']
 wait(lambda:scalar('SELECT count(DISTINCT data_source_id) FROM observations')==2,'two persisted sources')
 u=start('flutter-daemon-browser',['node','tests/oip007/ui_probe.mjs',URL,str(OUT/'ui')],True);ui_ready=receive(u,45);assert ui_ready['ready']
 record('01_daemon_two_sources_sqlite_rest_sse',{'pid':d.pid,'health':get('/api/v1/core/health'),'snapshot':sse(),'sql':sql('SELECT data_source_id,count(*) n FROM observations GROUP BY data_source_id'),'ui':ui_ready})
 A=Client('client-A');B=Client('client-B','a');C=Client('client-C','b',legacy=True)
 def scoped(client,source):return client.call('observations_read',{'source':source})
 with concurrent.futures.ThreadPoolExecutor(3) as pool:results=list(pool.map(lambda x:scoped(*x),[(A,'sim-a'),(B,'sim-a'),(C,'sim-b')]))
 assert all(o['data_source_id']=='sim-a' for o in results[1]);assert all(o['data_source_id']=='sim-b' for o in results[2]);assert len(A.command({'op':'tools'})['result']['tools'])==6;assert len(A.command({'op':'resources'})['result']['resources'])==8
 assert len(B.command({'op':'resources'})['result']['resources'])==1
 for target in ['sim-b','sim-c']:
  denied=B.command({'op':'call','name':'oip_sources_read','arguments':{'source':target}});assert denied['result']['structuredContent']['kind']=='permission_denied'
 assert not B.command({'op':'resource','uri':'oip://v1/snapshot/current'})['ok']
 record('02_three_clients_parity_and_scopes',{'parity':parity(A),'B_allowed':'sim-a','C_allowed':'sim-b','peer_modern':A.ready,'peer_legacy':C.ready,'denials':True})
 # Database duplicate rejected before collector start; use distinct IPC endpoint.
 dupcfg=dict(IPCCONFIG,socket=str(RUN/'duplicate-s'));(RUN/'duplicate-ipc.json').write_text(json.dumps(dupcfg));(RUN/'duplicate-ipc.json').chmod(0o600)
 duplicate=start('duplicate-daemon',[BIN,'--daemon','--legacy-single-infrastructure','--config',RUN/'core.json','--port',freeport(),'--ipc-config',RUN/'duplicate-ipc.json']);duplicate.wait(timeout=5);assert duplicate.returncode!=0
 assert 'source_connected' not in (OUT/'duplicate-daemon.log').read_text();assert not (RUN/'duplicate-s').exists();assert d.poll() is None
 # Actual canonical symlink alias also cannot start a second writer.
 alias=RUN/'alias.sqlite';alias.symlink_to(DB)
 duplicate=start('duplicate-alias',[BIN,'--daemon','--legacy-single-infrastructure','--config',RUN/'core.json','--database',alias,'--port',freeport(),'--ipc-config',RUN/'duplicate-ipc.json']);duplicate.wait(timeout=5);assert duplicate.returncode!=0
 # A live non-cooperating listener with a saturated backlog cannot hang startup.
 busy_path=RUN/'busy-s';busy=socket.socket(socket.AF_UNIX);busy.bind(str(busy_path));busy.listen(1);fill=[]
 for _ in range(12):
  z=socket.socket(socket.AF_UNIX);z.settimeout(.05)
  try:z.connect(str(busy_path));fill.append(z)
  except (TimeoutError,OSError):z.close();break
 busycfg=dict(IPCCONFIG,socket=str(busy_path));(RUN/'busy-ipc.json').write_text(json.dumps(busycfg));(RUN/'busy-ipc.json').chmod(0o600)
 begun=time.monotonic();busy_probe=start('saturated-existing-socket',[BIN,'--daemon','--legacy-single-infrastructure','--config',RUN/'core.json','--port',freeport(),'--ipc-config',RUN/'busy-ipc.json']);busy_probe.wait(timeout=3);assert busy_probe.returncode!=0 and time.monotonic()-begun<2;assert busy_path.exists();assert 'ipc_ready' not in (OUT/'saturated-existing-socket.log').read_text()
 for z in fill:z.close()
 busy.close();busy_path.unlink()
 record('03_single_writer_duplicate_alias_protection',{'duplicates_rejected':True,'core_alive':d.poll() is None})
 before=sources()['sim-b']['accepted'];A.abort();assert d.poll() is None;assert B.call('sources_read',{'source':'sim-a'});assert C.call('sources_read',{'source':'sim-b'});wait(lambda:sources()['sim-b']['accepted']>before,'ingestion after abrupt bridge death');ui('connected')
 A=Client('client-A-reconnected');assert parity(A)['run_id']==initial_run
 record('04_abrupt_client_isolation_and_reconnect',{'daemon_pid':d.pid,'run_id':initial_run,'UI':ui('connected')})
 for c in [A,B,C]:c.close()
 before=scalar('SELECT count(*) FROM observations');wait(lambda:scalar('SELECT count(*) FROM observations')>before,'no-client persistence');ui('connected');A=Client('client-A-after-zero');assert parity(A)['run_id']==initial_run
 record('05_zero_clients_persistent_ingestion',{'before':before,'after':scalar('SELECT count(*) FROM observations'),'health':get('/api/v1/core/health')})
 # 1, 3, 8 real clients; each official SDK client uses an independent bridge.
 perf=[]
 for n in [1,3,8]:
  clients=[A]+[Client(f'load-{n}-{i}') for i in range(n-1)]
  start_count=scalar('SELECT count(*) FROM observations');measure_before=ps(d);started=time.perf_counter()
  def reads(c):
   samples=[]
   for _ in range(20):
    t=time.perf_counter();assert len(c.call('sources_read'))==2;samples.append((time.perf_counter()-t)*1000)
   return samples
  with concurrent.futures.ThreadPoolExecutor(n) as pool:latencies=sum(pool.map(reads,clients),[])
  wait(lambda:scalar('SELECT count(*) FROM observations')>start_count,'ingestion during load');elapsed=time.perf_counter()-started
  perf.append({'clients':n,'reads':len(latencies),'mean_ms':statistics.mean(latencies),'p95_ms':sorted(latencies)[int(len(latencies)*.95)-1],'max_ms':max(latencies),'elapsed_s':elapsed,'process_before':measure_before,'process_after':ps(d),'observations_added':scalar('SELECT count(*) FROM observations')-start_count})
  for c in clients[1:]:c.close()
 connect=[]
 for i in range(12):
  t=time.perf_counter();c=Client('cycle-'+str(i));assert c.call('sources_read');c.close();connect.append((time.perf_counter()-t)*1000)
 ipc_latency=[]
 for _ in range(25):
  z=socket.socket(socket.AF_UNIX);z.settimeout(3);t=time.perf_counter();z.connect(str(SOCK));z.sendall(b'OIPIPC1\n'+TOKENS['all']);assert z.recv(1)==b'\x01';ipc_latency.append((time.perf_counter()-t)*1000);z.close()
 record('06_multiclient_load_and_session_cleanup',{'ipc_auth_latency_ms':ipc_latency,'runs':perf,'connect_read_close_ms':connect,'pid':d.pid})
 # Protocol and secret-boundary attacks; no JSON tool fields choose authority.
 errors=[]
 for cmd in [
 {'op':'call','name':'oip_sources_read','arguments':{'source':'sim-a','actor':'SECRET_SENTINEL','grants':['all']}},
 {'op':'call','name':'oip_opcua_nodes_read','arguments':{'limit':101}},
 {'op':'call','name':'oip_simulation_scenario_set','arguments':{}},
 {'op':'resource','uri':'file:///etc/passwd'},
 {'op':'call','name':'oip_device_read','arguments':{'id':'missing'}},
 {'op':'call','name':'oip_events_read','arguments':{'timestamp':-1}},
 {'op':'call','name':'oip_devices_read','arguments':{'q':'x'*257}}]:
  r=A.command(cmd);assert not r['ok'] or r.get('result',{}).get('isError');assert 'SECRET_SENTINEL' not in json.dumps(r);errors.append(r)
 for credential in ['a','b']:
  c=Client('new-bridge-'+credential,credential);foreign='sim-b' if credential=='a' else 'sim-a';r=c.command({'op':'call','name':'oip_sources_read','arguments':{'source':foreign}});assert r['result']['structuredContent']['kind']=='permission_denied';c.close()
 # Raw unauthorized local IPC, bad magic and unregistered credential.
 for prelude in [b'BADMAGIC'+TOKENS['all'],b'OIPIPC1\n'+secrets.token_bytes(32)]:
  s=socket.socket(socket.AF_UNIX);s.settimeout(3);s.connect(str(SOCK));s.sendall(prelude)
  try:assert s.recv(1)==b''
  except ConnectionResetError:pass
  s.close()
 (RUN/'bad.credential').write_bytes(secrets.token_bytes(32));(RUN/'bad.credential').chmod(0o600)
 bad=start('wrong-bridge-credential',[BIN,'--mcp-bridge','--ipc-socket',SOCK,'--ipc-credential',RUN/'bad.credential'],True);bad.stdin.close();bad.wait(timeout=5);assert bad.returncode!=0 and bad.stdout.read()==''
 # Oversized/malformed MCP frames over a real authenticated bridge followed by valid ping.
 raw=start('slow-raw-bridge',[BIN,'--mcp-bridge','--ipc-socket',SOCK,'--ipc-credential',RUN/'all.credential'],True)
 raw.stdin.write('{malformed json\n'+json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'raw-test','version':'1'}}})+'\n');raw.stdin.flush();assert receive(raw)['id']==1
 raw.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'})+'\n');raw.stdin.write('x'*17000+'\n'+json.dumps({'jsonrpc':'2.0','id':2,'method':'ping'})+'\n');raw.stdin.flush();assert receive(raw)['id']==2
 # Paginated reads verify1000nodes. Snapshot intentionally excludes bulk values;
 # use actual100-node TOOL results below to fill the stdout pipe, not tiny snapshots.
 nodes=[A.call('opcua_nodes_read',{'folder':'Bulk','source':'sim-b','offset':i,'limit':100}) for i in range(0,1000,100)];assert sum(len(p['items']) for p in nodes)==1000
 assert all(o['observation']['data_source_id']=='sim-b' for p in nodes for o in p['items'] if o['observation'])
 before=sources()['sim-b']['accepted']
 for i in range(8):raw.stdin.write(json.dumps({'jsonrpc':'2.0','id':100+i,'method':'tools/call','params':{'name':'oip_opcua_nodes_read','arguments':{'source':'sim-b','folder':'Bulk','limit':100,'offset':i*100}}})+'\n')
 raw.stdin.flush();wait(lambda:sources()['sim-b']['accepted']>before+4,'ingestion with unread slow client');assert A.call('sources_read');ui('connected')
 # stdin remains open and stdout remains unread: the bridge must stop itself.
 raw.wait(timeout=10);assert raw.returncode!=0;raw.stdin.close();wire=raw.stdout.read()
 assert all(json.loads(line).get('jsonrpc')=='2.0' for line in wire.splitlines(keepends=True) if line.endswith('\n'))
 assert 'bridge stdout stalled' in (OUT/'slow-raw-bridge.log').read_text()
 record('07_security_slow_client_and_bounded_pagination',{'errors':errors,'nodes':1000,'core_alive':d.poll() is None,'slow_client_bytes':len(wire),'stdout_protocol_only':True})
 before=sources()['sim-b']['accepted'];stop(a);wait(lambda:sources()['sim-a']['connection']=='disconnected','source A stopped');wait(lambda:sources()['sim-b']['accepted']>before+4,'source B continues');ui('offline');record('08_source_isolation_UI_MCP_REST_SSE',{'parity':parity(A),'snapshot':sse()})
 a=sim('source-a-alarm',PA,42,'critical_sensor');wait(lambda:get('/api/v1/devices/M-01')['device']['is_faulted'],'source real alarm');ui('alarm');stop(a);a=sim('source-a-normal',PA,42);wait(lambda:get('/api/v1/core/health')['lifecycle']=='ready','source recovered');wait(lambda:scalar("SELECT count(*) FROM data_gaps WHERE data_source_id='sim-a'")>0,'durable gaps');record('09_source_reconnect_alarm_and_gaps',{'parity':parity(A),'gaps':sql('SELECT * FROM data_gaps')})
 A.close();stop(a);stop(b);stop(d);assert not SOCK.exists();count=scalar('SELECT count(*) FROM observations');d=daemon('daemon-restored');wait(lambda:get('/api/v1/core/health')['live'],'restart');A=Client('restored-client',legacy=True);restored=A.call('observations_read');assert restored and all(o['freshness']=='stale' for o in restored);assert all(s['reachability']=='unknown' and s['last_received_ms'] is None for s in sources().values());assert scalar('SELECT count(*) FROM observations')==count;ui('stale');record('10_graceful_restart_stale_restore',{'parity':parity(A),'observation_count':count})
 a=sim('source-a-after-restart',PA,42);b=sim('source-b-after-restart',PB,77);wait(lambda:get('/api/v1/core/health')['lifecycle']=='ready','genuine new receipt');ui('connected');before=scalar('SELECT count(*) FROM observations');wait(lambda:scalar('SELECT count(*) FROM observations')>before,'restart ingestion');A.close();stop(a);stop(b)
 # Actual SIGKILL leaves socket, run-journal and SQLite process state unclean.
 stop(d,crash=True);assert SOCK.exists();d=daemon('daemon-crash-recovered');wait(lambda:get('/api/v1/core/health')['live'],'crash recovery');A=Client('crash-restored-client');assert all(o['freshness']=='stale' for o in A.call('observations_read'));assert all(s['reachability']=='unknown' for s in sources().values());assert scalar('PRAGMA quick_check')=='ok';assert scalar('SELECT count(*) FROM (SELECT observation_key FROM observations GROUP BY observation_key HAVING count(*)>1)')==0
 # Inspect actual run journal schema and rows, not a fabricated clean result.
 journal=sql('SELECT * FROM core_runs');assert any(row['result']=='interrupted' for row in journal[:-1]),journal
 record('11_actual_crash_stale_socket_and_journal_recovery',{'journal':journal,'integrity':scalar('PRAGMA quick_check'),'parity':parity(A)})
 a=sim('source-a-after-crash',PA,42);b=sim('source-b-after-crash',PB,77);wait(lambda:get('/api/v1/core/health')['lifecycle']=='ready','crash recovered live');u.stdin.write('{"op":"close"}\n');u.stdin.flush();u.stdin.close();assert receive(u,45)['closed'];u.wait(timeout=10);assert u.returncode==0
 assert A.call('sources_read');assert d.poll() is None
 A.close();stop(a);stop(b);stop(d);assert not SOCK.exists()
 logs='\n'.join(p.read_text() for p in OUT.glob('*.log'));assert 'SECRET_SENTINEL' not in logs;assert 'capability_execution' in logs and 'ipc_authorized' in logs and 'peer_uid' in logs and 'session_id' in logs
 assert all(token.hex() not in logs for token in TOKENS.values());record('12_audit_redaction_and_cleanup',{'audit_present':True,'token_not_logged':True,'socket_removed':True,'final_sqlite_integrity':scalar('PRAGMA quick_check')})
 REPORT['verdict']='PASS';REPORT['database']=str(DB);REPORT['url']=URL
except BaseException as e:REPORT['verdict']='FAIL';REPORT['error']=repr(e);raise
finally:
 for p in reversed(PROCS):
  if p.poll() is None:
   try:p.send_signal(signal.SIGINT);p.wait(timeout=15)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
 (OUT/'report.json').write_text(json.dumps(REPORT,indent=2));(OUT/'sdk-transcript.json').write_text(json.dumps(TRANSCRIPT,indent=2));

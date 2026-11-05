#!/usr/bin/env python3
"""Real SDK stdio client + two independent local sources; no model or UI required."""
import json,os,select,signal,socket,subprocess,time,urllib.request,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(os.environ.get('OIP_EVIDENCE_DIR',str(ROOT/'docs/evidence/oip007/mcp')));OUT.mkdir(parents=True,exist_ok=True)
RUN=ROOT/'target'/('oip006-e2e-'+str(os.getpid()));RUN.mkdir(parents=True)
PROCESSES=[];REPORT={'phases':[],'processes':[],'model_used':False};TRANSCRIPT=[]
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
PA,PB,HTTP=port(),port(),port();DB=RUN/'evidence.sqlite'
CONFIG={'database':str(DB),'http_port':HTTP,'sources':[{'id':'sim-a','name':'Simulation A','endpoint':f'opc.tcp://127.0.0.1:{PA}'},{'id':'sim-b','name':'Simulation B','endpoint':f'opc.tcp://127.0.0.1:{PB}'}],'web_dir':None,'queue_capacity':8,'stale_after_ms':2000,'shutdown_timeout_ms':6000}
(RUN/'core.json').write_text(json.dumps(CONFIG))
SQLITE=os.environ.get('OIP_SQLITE_CLI') or ('/opt/homebrew/opt/sqlite/bin/sqlite3' if Path('/opt/homebrew/opt/sqlite/bin/sqlite3').exists() else shutil.which('sqlite3'))
def sql(q):return json.loads(subprocess.check_output([SQLITE,'-readonly','-json',str(DB),q],text=True) or '[]')
def scalar(q):return next(iter(sql(q)[0].values()))
def wait(fn,label,timeout=30):
 start=time.monotonic();last=None
 while time.monotonic()-start<timeout:
  try:
   last=fn()
   if last:return last
  except (OSError,ValueError,KeyError,AssertionError):pass
  time.sleep(.05)
 raise AssertionError(label+' timed out: '+str(last))
def get(path):
 with urllib.request.urlopen(f'http://127.0.0.1:{HTTP}'+path,timeout=3) as r:return json.load(r)
def start(name,argv,pipe=False):
 f=(OUT/(name+'.log')).open('w');p=subprocess.Popen(argv,cwd=ROOT,stdin=subprocess.PIPE if pipe else subprocess.DEVNULL,stdout=subprocess.PIPE if pipe else f,stderr=f,text=True,bufsize=1,env=dict(os.environ,RUST_LOG='trace,rmcp::service=trace') if pipe else None);f.close();PROCESSES.append(p);REPORT['processes'].append({'name':name,'pid':p.pid,'argv':list(map(str,argv))});return p
def sim(name,p,seed):return start(name,[str(ROOT/'target/debug/oip-simulated-server'),'--port',str(p),'--seed',str(seed),'--tick-ms','250'])
def receive(p,timeout=25):
 if not select.select([p.stdout],[],[],timeout)[0]:raise AssertionError('SDK client timeout')
 line=p.stdout.readline();assert line,('client closed',p.poll());value=json.loads(line);TRANSCRIPT.append({'response':value});return value
class Client:
 def __init__(self,name,policy='examples/mcp-read-local.json',era='modern',rest=True):
  self.p=start(name,[str(ROOT/'target/debug/examples/mcp_probe'),era,str(ROOT/'target/debug/oip-server'),'--legacy-single-infrastructure','--config',str(RUN/'core.json'),'--mcp-stdio','--mcp-policy',policy]+(['--mcp-rest'] if rest else []),True);self.ready=receive(self.p);assert self.ready['ready']
 def command(self,value):
  TRANSCRIPT.append({'request':value});self.p.stdin.write(json.dumps(value)+'\n');self.p.stdin.flush();return receive(self.p)
 def call(self,name,args={}):
  r=self.command({'op':'call','name':'oip_'+name,'arguments':args});assert r['ok'],r;assert not r['result'].get('isError'),r;return r['result']['structuredContent']['value']
 def resource(self,uri):
  r=self.command({'op':'resource','uri':uri});assert r['ok'],r;return json.loads(r['result']['contents'][0]['text'])['value']
 def close(self):
  self.p.stdin.close();r=receive(self.p);assert r['closed'] and r['success'];self.p.wait(timeout=25);assert self.p.returncode==0

def stop(p):
 if p.poll() is None:p.send_signal(signal.SIGINT)
 p.wait(timeout=15);assert p.returncode==0

def record(phase,data):REPORT['phases'].append({'phase':phase,'status':'PASS','details':data});print('PASS',phase,flush=True)
def sources(c):return {s['id']:s for s in c.call('sources_read')}
def sse():
 with urllib.request.urlopen(f'http://127.0.0.1:{HTTP}/api/v1/stream',timeout=3) as r:
  for line in r:
   if line.startswith(b'data:'):return json.loads(line[5:])
try:
 a=sim('sim-a',PA,42);b=sim('sim-b',PB,77);c=Client('core-sdk-modern')
 wait(lambda:c.resource('oip://v1/core/health')['lifecycle']=='ready','both ready')
 devices=c.call('devices_read');assert {d['id'] for d in devices}=={'M-01','sim-b:M-01'}
 assert {o['data_source_id'] for o in c.call('observations_read')}=={'sim-a','sim-b'}
 assert {o['simulation_origin']['seed'] for o in c.call('observations_read')}=={42,77}
 assert len(sql('SELECT DISTINCT data_source_id FROM observations'))==2
 # Duplicate process rejected even through a different path to the same inode.
 duplicate=start('duplicate-core',[str(ROOT/'target/debug/oip-server'),'--legacy-single-infrastructure','--config',str(RUN/'core.json'),'--mcp-stdio','--mcp-policy','examples/mcp-read-local.json'],True)
 duplicate.stdin.close();duplicate.wait(timeout=5);assert duplicate.returncode!=0;assert not duplicate.stdout.read()
 record('A_single_runtime_sqlite_rest_sse',{'sdk':c.ready,'devices':devices,'health':get('/api/v1/core/health'),'snapshot':sse(),'db':sql('SELECT data_source_id,count(*) n FROM observations GROUP BY data_source_id'),'duplicate_rejected':True})
 tools=c.command({'op':'tools'})['result']['tools'];resources=c.command({'op':'resources'})['result']['resources'];assert len(tools)==6;assert len(resources)==8
 assert all(t['annotations']['readOnlyHint'] for t in tools)
 assert all('scenario' not in t['name'] for t in tools)
 for tool in tools:assert tool['inputSchema']['type']=='object' and tool['inputSchema']['additionalProperties']==False
 record('B_discovery',{'tools':tools,'resources':resources,'protocol':c.ready['peer']['protocolVersion']})
 for d in devices:assert c.call('device_read',{'id':d['id']})['device']['id']==d['id']
 assert c.call('events_read')['replay_supported']==False
 pages=[c.call('opcua_nodes_read',{'source':'sim-b','folder':'Bulk','offset':i,'limit':100}) for i in range(0,1000,100)]
 assert all(p['total']==1000 and p['limit']==100 and len(p['items'])==100 for p in pages)
 assert len({n['node_id'] for p in pages for n in p['items']})==1000
 assert all(n['observation']['data_source_id']=='sim-b' for p in pages for n in p['items'] if n['observation'])
 metrics=c.call('observations_read',{'source':'sim-b'});assert all(o['data_source_id']=='sim-b' for o in metrics)
 before=metrics[0]['timestamps']['received'];wait(lambda:any(o['timestamps']['received']!=before for o in c.call('observations_read',{'source':'sim-b'})),'new observation')
 record('C_data_pagination',{'metrics_count':len(metrics),'node_pages':len(pages),'nodes':1000,'sources':sources(c)})
 before=sources(c)['sim-b']['accepted'];stop(a)
 wait(lambda:sources(c)['sim-a']['connection']=='disconnected','A offline');wait(lambda:sources(c)['sim-b']['accepted']>before+4,'B continues')
 mcp=sources(c);rest={s['id']:s for s in get('/api/v1/sources')};assert mcp['sim-a']['connection']==rest['sim-a']['connection'];assert mcp['sim-b']['freshness']=='fresh'
 assert all(o['data_source_id']=='sim-b' for o in c.call('device_read',{'id':'sim-b:M-01'})['metrics'])
 record('D_isolation',{'mcp':mcp,'rest':rest})
 a=sim('sim-a-recovered',PA,42);wait(lambda:c.resource('oip://v1/core/health')['lifecycle']=='ready','A reconnect')
 wait(lambda:scalar("SELECT count(*) FROM data_gaps WHERE data_source_id='sim-a'")>0,'durable gaps')
 assert any('Reconnected' in r['event'] for r in c.call('events_read',{'source':'sim-a'})['records'])
 record('E_recovery',{'sources':sources(c),'gaps':sql('SELECT * FROM data_gaps')})
 # Close actual MCP stdin: the same process drains core+HTTP, not a second runtime.
 c.close();stop(a);stop(b);count=scalar('SELECT count(*) FROM observations');c=Client('core-sdk-legacy',era='legacy')
 stale=c.call('observations_read');assert stale and all(o['freshness']=='stale' for o in stale)
 restored=sources(c);assert all(s['last_received_ms'] is None and s['reachability']=='unknown' for s in restored.values());assert scalar('SELECT count(*) FROM observations')==count
 a=sim('sim-a-after-restart',PA,42);b=sim('sim-b-after-restart',PB,77);wait(lambda:c.resource('oip://v1/core/health')['lifecycle']=='ready','restart live');wait(lambda:scalar('SELECT count(*) FROM observations')>count,'new persistence')
 assert scalar('SELECT count(*) FROM (SELECT observation_key FROM observations GROUP BY observation_key HAVING count(*)>1)')==0
 record('F_restart',{'legacy_sdk':c.ready,'restored':restored,'live':sources(c),'integrity':scalar('PRAGMA quick_check')})
 # Security on the real wire, no grants accepted in tool inputs.
 errors=[]
 for cmd in [
 {'op':'call','name':'oip_devices_read','arguments':{'actor':'SECRET_SENTINEL','permissions':['simulation_control']}},
 {'op':'call','name':'oip_devices_read','arguments':{'q':'x'*17000}},
 {'op':'call','name':'oip_events_read','arguments':{'timestamp':-1}},
 {'op':'call','name':'oip_opcua_nodes_read','arguments':{'limit':101}},
 {'op':'call','name':'oip_simulation_scenario_set','arguments':{'scenario':'sensor'}},
 {'op':'call','name':'configuration_read','arguments':{}},
 {'op':'resource','uri':'file:///etc/passwd'},
 ]:
  # A >16KiB frame is intentionally discarded by the SDK before parsing and
  # has no response; the transport bound is separately exercised below.
  if len(json.dumps(cmd))>16000:cmd['arguments']['q']='x'*257
  result=c.command(cmd);assert not result['ok'] or result.get('result',{}).get('isError');assert 'SECRET_SENTINEL' not in json.dumps(result);errors.append(result)
 unknown=c.command({'op':'call','name':'oip_device_read','arguments':{'id':'missing'}});assert unknown['result']['structuredContent']['kind']=='resource_not_found'
 batch=c.command({'op':'batch'});assert batch['ok'] and len(batch['result'])==8 and all('Ok' in r for r in batch['result'])
 timings=[]
 for _ in range(25):
  now=time.monotonic();c.call('sources_read',{'source':'sim-b'});timings.append((time.monotonic()-now)*1000)
 rss=int(subprocess.check_output(['ps','-o','rss=','-p',str(c.ready['pid'])],text=True).strip());c.close()
 c=Client('core-scoped',policy='examples/mcp-read-source-a.json')
 scoped=c.call('devices_read',{'source':'sim-a'});assert len(scoped)==1
 denied=c.command({'op':'call','name':'oip_sources_read','arguments':{'source':'sim-b'}});assert denied['result']['structuredContent']['kind']=='permission_denied'
 denied_snapshot=c.command({'op':'resource','uri':'oip://v1/snapshot/current'});assert not denied_snapshot['ok']
 scoped_resources=c.command({'op':'resources'})['result']['resources'];assert [r['uri'] for r in scoped_resources]==['oip://v1/sources/sim-a/health']
 c.close();record('G_authorization_security_performance',{'errors':errors,'scoped_resources':scoped_resources,'source_denial':denied,'snapshot_denial':denied_snapshot,'read_latency_ms':{'min':min(timings),'max':max(timings),'mean':sum(timings)/len(timings)},'rss_kib':rss})
 d=Client('core-stdio-only',rest=False);wait(lambda:d.resource('oip://v1/core/health')['lifecycle']=='ready','stdio-only core ready')
 try:
  connection=socket.create_connection(('127.0.0.1',HTTP),timeout=1);connection.close();raise AssertionError('stdio-only mode opened HTTP')
 except ConnectionRefusedError:pass
 assert len(d.call('sources_read'))==2;d.close();record('G3_stdio_only_no_http_listener',{'model_used':False,'http_listener':False})
 # Raw protocol fault/slow-client exercises supplement, never replace, SDK interop.
 raw=start('core-raw-slow',[str(ROOT/'target/debug/oip-server'),'--legacy-single-infrastructure','--config',str(RUN/'core.json'),'--mcp-stdio','--mcp-rest','--mcp-policy','examples/mcp-read-local.json'],True)
 raw.stdin.write(json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','clientInfo':{'name':'raw-security-verifier','version':'1'},'capabilities':{}}})+'\n');raw.stdin.flush();assert 'result' in receive(raw)
 raw.stdin.write('{bad json}\n');raw.stdin.write(json.dumps({'jsonrpc':'2.0','id':3,'method':'ping'})+'\n');raw.stdin.flush();assert receive(raw)['id']==3
 raw.stdin.write(json.dumps({'jsonrpc':'2.0','id':4,'method':42})+'\n');raw.stdin.flush();assert 'error' in receive(raw)
 raw.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'})+'\n');raw.stdin.flush()
 raw.stdin.write('x'*17000+'\n');raw.stdin.write(json.dumps({'jsonrpc':'2.0','id':2,'method':'ping'})+'\n');raw.stdin.flush();assert receive(raw)['id']==2
 wait(lambda:get('/api/v1/core/health')['lifecycle']=='ready','raw core ready');initial=scalar('SELECT count(*) + coalesce(sum(duplicate_count),0) FROM observations')
 # Do not read replies for eight full snapshots. This backpressures stdout only.
 for i in range(8):raw.stdin.write(json.dumps({'jsonrpc':'2.0','id':10+i,'method':'resources/read','params':{'uri':'oip://v1/snapshot/current'}})+'\n')
 raw.stdin.flush()
 # Force a real, authorized sample through the independent REST/OPC-UA/writer path.
 # Idempotent writes may advance duplicate_count rather than create a new key.
 assert get('/api/v1/opcua/nodes?source=sim-b&folder=Bulk&limit=1')['items'][0]['observation']['data_source_id']=='sim-b'
 wait(lambda:scalar('SELECT count(*) + coalesce(sum(duplicate_count),0) FROM observations')>initial,'persisted processing while MCP output is unread',timeout=2.5)
 raw.stdin.close();wire=raw.stdout.read();raw.wait(timeout=20);assert raw.returncode==0
 assert all(json.loads(line).get('jsonrpc')=='2.0' for line in wire.splitlines() if line)
 record('G2_slow_client_invalid_json_and_frame_limit',{'ingestion_advanced':True,'stdout_protocol_only':True,'response_bytes':len(wire),'clean_exit':raw.returncode})
 stop(a);stop(b)
 logs='\n'.join(p.read_text() for p in OUT.glob('*.log'));assert 'SECRET_SENTINEL' not in logs
 assert 'capability_execution' in logs and 'source_scope' in logs and 'correlation_id' in logs
 assert scalar('PRAGMA quick_check')=='ok'
 REPORT['verdict']='PASS';REPORT['database']=str(DB);REPORT['config']=CONFIG
except BaseException as e:REPORT['verdict']='FAIL';REPORT['error']=repr(e);raise
finally:
 for p in reversed(PROCESSES):
  if p.poll() is None:
   try:p.send_signal(signal.SIGINT);p.wait(timeout=15)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
 (OUT/'report.json').write_text(json.dumps(REPORT,indent=2));(OUT/'sdk-transcript.json').write_text(json.dumps(TRANSCRIPT,indent=2))

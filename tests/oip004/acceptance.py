#!/usr/bin/env python3
"""Own loopback-only subprocesses, no Flutter or browser/tool dependency."""
import json, os, signal, socket, subprocess, time, urllib.request, sqlite3, shutil
from urllib.error import HTTPError
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(os.environ.get('OIP_EVIDENCE_DIR',str(ROOT/'docs/evidence/oip004/acceptance')))
OUT.mkdir(parents=True,exist_ok=True)
RUN=ROOT/'target'/('oip004-acceptance-'+str(os.getpid()))
RUN.mkdir(parents=True,exist_ok=True)
SQLITE=os.environ.get('OIP_SQLITE_CLI') or (str(Path('/opt/homebrew/opt/sqlite/bin/sqlite3')) if Path('/opt/homebrew/opt/sqlite/bin/sqlite3').exists() else shutil.which('sqlite3'))
REPORT={'phases':[], 'processes':[], 'flutter_used':False}
processes=[]
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
PA,PB,HTTP=port(),port(),port()
DB=RUN/'evidence.sqlite'
CONFIG={'database':str(DB),'http_port':HTTP,'sources':[{'id':'sim-a','name':'Simulation A','endpoint':f'opc.tcp://127.0.0.1:{PA}'},{'id':'sim-b','name':'Simulation B','endpoint':f'opc.tcp://127.0.0.1:{PB}'}],'web_dir':None,'queue_capacity':8,'shutdown_timeout_ms':6000,'stale_after_ms':3000}
(RUN/'core.json').write_text(json.dumps(CONFIG))
def start(name,args):
 log=OUT/(name+'.log'); f=log.open('w');p=subprocess.Popen(args,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT);f.close();processes.append(p);REPORT['processes'].append({'name':name,'pid':p.pid,'argv':[str(a) for a in args]});return p

def sim(name,p,seed):return start(name,[str(ROOT/'target/debug/oip-simulated-server'),'--port',str(p),'--seed',str(seed),'--tick-ms','250'])
def core(name):return start(name,[str(ROOT/'target/debug/oip-server'),'--config',str(RUN/'core.json'),'--no-web'])
def wait(fn,label,timeout=25):
 start_time=time.monotonic();last=None
 while time.monotonic()-start_time<timeout:
  try:
   last=fn()
   if last:return last
  except (OSError,ValueError,KeyError,StopIteration):pass
  time.sleep(.05)
 raise AssertionError(label+' timed out; last='+str(last))
def get(path):
 with urllib.request.urlopen(f'http://127.0.0.1:{HTTP}'+path,timeout=3) as r:return json.load(r)
def health():return get('/api/v1/core/health')
def sources():return {s['id']:s for s in get('/api/v1/sources')}
def stop(p,hard=False):
 if p.poll() is None:p.send_signal(signal.SIGKILL if hard else signal.SIGINT)
 p.wait(timeout=15)
 if not hard:assert p.returncode==0,('shutdown failed',p.pid,p.returncode)
def sql(query):
 if sqlite3.sqlite_version_info>=(3,37):
  with sqlite3.connect('file:'+str(DB)+'?mode=ro',uri=True,timeout=2) as c:return [list(r) for r in c.execute(query)]
 return json.loads(subprocess.check_output([SQLITE,'-readonly','-json',str(DB),query],text=True) or '[]')
def scalar(query):
 rows=sql(query)
 if not rows:return None
 return next(iter(rows[0].values())) if isinstance(rows[0],dict) else rows[0][0]
def record(phase,details):REPORT['phases'].append({'phase':phase,'status':'PASS','details':details});print('PASS',phase,flush=True)
def stream(last=None):
 headers={} if last is None else {'Last-Event-ID':last}
 response=urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{HTTP}/api/v1/stream',headers=headers),timeout=3)
 event_id=None;data=None
 while True:
  line=response.readline().decode().strip()
  if line.startswith('id:'):event_id=line[3:].strip()
  if line.startswith('data:'):data=json.loads(line[5:])
  if not line and data is not None:return response,event_id,data
try:
 a=sim('sim-a',PA,42);b=sim('sim-b',PB,77);c=core('core-first')
 wait(lambda:health()['lifecycle']=='ready','two sources ready')
 initial=sources();assert set(initial)=={'sim-a','sim-b'}
 assert all(s['connection']=='connected' and s['freshness']=='fresh' for s in initial.values())
 # The primary device keeps its OIP-003 identifier; other sources are qualified.
 assert {d['id'] for d in get('/api/v1/devices')}=={'M-01','sim-b:M-01'}
 for device in get('/api/v1/devices'):
  assert get('/api/v1/devices/'+device['id'])['device']['id']==device['id']
 assert get('/health/live')['live']
 wait(lambda:get('/health/ready')['ready'],'HTTP readiness after initial subscription')
 try:
  urllib.request.urlopen(f'http://127.0.0.1:{HTTP}/',timeout=3)
  raise AssertionError('headless core served a frontend')
 except HTTPError as error:assert error.code==404
 record('1_start_without_flutter',{'health':health(),'sources':initial})
 wait(lambda:scalar('SELECT count(DISTINCT data_source_id) FROM observations')==2,'SQLite source separation')
 metrics=get('/api/v1/metrics/current');assert {o['data_source_id'] for o in metrics}=={'sim-a','sim-b'}
 assert {o['simulation_origin']['seed'] for o in metrics}=={42,77}
 sse,old_event_id,snapshot=stream();assert snapshot['resync_required'] is True and len(snapshot['sources'])==2
 # A TCP consumer stops reading entirely. Its tiny receive window eventually
 # backpressures HTTP output; ingestion must keep advancing independently.
 slow=socket.socket();slow.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1024);slow.connect(('127.0.0.1',HTTP));slow.sendall(f'GET /api/v1/stream HTTP/1.1\r\nHost: 127.0.0.1:{HTTP}\r\n\r\n'.encode())
 before=sources()['sim-b']['accepted'];time.sleep(3);assert sources()['sim-b']['accepted']>before
 record('2_ingestion_sqlite_rest_sse_and_slow_client',{'persisted':scalar('SELECT count(*) FROM observations'),'sse_event_id':old_event_id,'queue':snapshot['queue']})
 before=sources()['sim-b']['accepted'];stop(a)
 wait(lambda:sources()['sim-a']['connection']=='disconnected','A disconnected')
 wait(lambda:sources()['sim-b']['accepted']>before+4,'B continues while A offline')
 assert health()['lifecycle']=='degraded' and health()['ready'] and health()['live']
 record('3_A_failure_isolated',{'health':health(),'sources':sources()})
 stop(b);wait(lambda:all(s['connection']=='disconnected' for s in sources().values()),'both offline')
 assert health()['live'] and not health()['ready'] and health()['lifecycle']=='degraded'
 try:
  get('/health/ready')
  raise AssertionError('offline readiness must return HTTP 503')
 except HTTPError as error:assert error.code==503
 assert all(o['freshness']!='fresh' for o in get('/api/v1/metrics/current'))
 record('3b_both_offline',health())
 a=sim('sim-a-recovered',PA,42);wait(lambda:sources()['sim-a']['freshness']=='fresh','A recovered')
 assert health()['lifecycle']=='degraded' and health()['ready']
 b=sim('sim-b-recovered',PB,77);wait(lambda:health()['lifecycle']=='ready','B recovered')
 wait(lambda:scalar('SELECT count(*) FROM data_gaps')>=2,'durable source gaps')
 records=get('/api/v1/events')['records'];assert {r['context']['data_source_id'] for r in records if 'Reconnected' in r['event']}=={'sim-a','sim-b'}
 record('4_recovery',{'health':health(),'events':records,'gaps':sql('SELECT data_source_id,started_at_ms,ended_at_ms,reason FROM data_gaps')})
 # Deliberately keep both SSE clients open during coordinated core shutdown.
 stop(c);sse.close();slow.close();tail=(OUT/'core-first.log').read_text().splitlines();shutdown=[json.loads(line) for line in tail if line.startswith('{') and '"clean"' in line][-1];assert shutdown['clean'] and shutdown['uncommitted']==0
 count=scalar('SELECT count(*) FROM observations');stop(a);stop(b)
 c=core('core-restored-offline');wait(lambda:get('/api/v1/system/status'),'restored API')
 restored=sources();assert all(s['last_received_ms'] is None and s['reachability']=='unknown' for s in restored.values())
 assert scalar('SELECT count(*) FROM observations')==count
 assert all(o['freshness']=='stale' for o in get('/api/v1/metrics/current'))
 duplicates_before=scalar('SELECT coalesce(sum(duplicate_count),0) FROM observations')
 a=sim('sim-a-after-core-restart',PA,42);b=sim('sim-b-after-core-restart',PB,77)
 wait(lambda:health()['lifecycle']=='ready','restarted collection')
 wait(lambda:scalar('SELECT coalesce(sum(duplicate_count),0) FROM observations')>duplicates_before,'idempotent redelivery')
 fresh_sse,new_event_id,new_snapshot=stream(old_event_id);assert new_snapshot['resync_required'] and old_event_id.split(':')[0]!=new_event_id.split(':')[0];fresh_sse.close()
 assert get('/api/v1/events')['replay_supported'] is False
 assert scalar('SELECT count(*) FROM core_sources')==2
 record('5_coordinated_restart_and_resync',{'shutdown':shutdown,'restored':restored,'current':sources(),'old_event_id':old_event_id,'new_event_id':new_event_id,'duplicates':scalar('SELECT sum(duplicate_count) FROM observations')})
 # Crash while a writer is blocked on a transaction. No uncommitted snapshot
 # may be published, and the next run must retain explicit interruption evidence.
 lock=None
 if sqlite3.sqlite_version_info>=(3,37):
  lock=sqlite3.connect(DB);lock.execute('BEGIN IMMEDIATE')
 else:
  lock=subprocess.Popen([SQLITE,str(DB)],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,text=True);lock.stdin.write('BEGIN IMMEDIATE;\n');lock.stdin.flush();time.sleep(.2)
 wait(lambda:not health()['persistence_healthy'],'writer blocked')
 stop(c,hard=True)
 if isinstance(lock,sqlite3.Connection):lock.rollback();lock.close()
 else:lock.stdin.write('ROLLBACK;\n');lock.stdin.flush();lock.stdin.close();lock.wait(timeout=3)
 c=core('core-after-crash');wait(lambda:health()['lifecycle']=='ready','recovery after uncommitted crash')
 assert scalar("SELECT count(*) FROM core_runs WHERE result='interrupted'")>=1
 assert scalar('PRAGMA quick_check')=='ok'
 assert scalar('SELECT count(*) FROM (SELECT observation_key,count(*) n FROM observations GROUP BY observation_key HAVING n>1)')==0
 record('5b_crash_during_ingestion',{'health':health(),'runs':sql('SELECT * FROM core_runs'),'integrity':scalar('PRAGMA quick_check')})
 stop(c);stop(a);stop(b)
 REPORT['verdict']='PASS';REPORT['database']=str(DB);REPORT['config']=CONFIG
except BaseException as error:
 REPORT['verdict']='FAIL';REPORT['error']=repr(error);raise
finally:
 for p in reversed(processes):
  if p.poll() is None:
   p.send_signal(signal.SIGINT)
   try:p.wait(timeout=10)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)
 (OUT/'report.json').write_text(json.dumps(REPORT,indent=2))

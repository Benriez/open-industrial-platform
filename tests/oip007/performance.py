#!/usr/bin/env python3
"""Short comparable local runs: legacy OIP-006 mode vs daemon 1/3/8 clients.
Not a production SLA/leak test. Uses real official SDK subprocess clients.
"""
import pathlib,subprocess,os,json,socket,time,select,threading,concurrent.futures,statistics,signal,urllib.request
R=pathlib.Path(__file__).resolve().parents[2];O=R/'docs/evidence/oip007/performance';O.mkdir(parents=True,exist_ok=True);D=R/'target'/('p7-'+str(os.getpid()));D.mkdir(mode=0o700);PROCS=[];RESULT=[]
BIN=str(R/'target/debug/oip-server');SDK=str(R/'target/debug/examples/mcp_probe')
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def start(name,args,pipe=False):
 f=(O/(name+'.log')).open('w');p=subprocess.Popen(args,cwd=R,stdin=subprocess.PIPE if pipe else subprocess.DEVNULL,stdout=subprocess.PIPE if pipe else f,stderr=f,text=True,bufsize=1);f.close();PROCS.append(p);return p
def receive(p):
 assert select.select([p.stdout],[],[],20)[0],'timeout';line=p.stdout.readline();assert line;return json.loads(line)
class Client:
 def __init__(self,args,name):self.p=start(name,[SDK,'modern',BIN]+args,True);self.ready=receive(self.p);assert self.ready['ready']
 def cmd(self,c):self.p.stdin.write(json.dumps(c)+'\n');self.p.stdin.flush();v=receive(self.p);assert v['ok'];return v['result']
 def read(self):
  v=self.cmd({'op':'call','name':'oip_sources_read'});assert not v.get('isError');assert len(v['structuredContent']['value'])==2;return v
 def health(self):return json.loads(self.cmd({'op':'resource','uri':'oip://v1/core/health'})['contents'][0]['text'])['value']
 def close(self):self.p.stdin.close();assert receive(self.p)['success'];self.p.wait(timeout=10);assert self.p.returncode==0

def wait(fn):
 end=time.monotonic()+35
 while time.monotonic()<end:
  try:
   if fn():return
  except (OSError,AssertionError,KeyError):pass
  time.sleep(.05)
 raise AssertionError('readiness timeout')
def proc(pid):
 rss,cpu=subprocess.check_output(['ps','-p',str(pid),'-o','rss=,time='],text=True).split();parts=cpu.split(':');seconds=float(parts[-1])+int(parts[-2])*60
 lines=subprocess.check_output(['ps','-M','-p',str(pid)],text=True).splitlines()
 return {'rss_kib':int(rss),'cpu_s':seconds,'os_threads':len(lines)-1}
def measure(label,clients,pid):
 before=proc(pid);first=clients[0].health();start_time=time.monotonic();end=start_time+8
 def work(c):
  samples=[]
  while time.monotonic()<end:
   t=time.perf_counter();c.read();samples.append((time.perf_counter()-t)*1000);time.sleep(.05)
  return samples
 with concurrent.futures.ThreadPoolExecutor(len(clients)) as pool:samples=sum(pool.map(work,clients),[])
 elapsed=time.monotonic()-start_time;after=proc(pid);last=clients[0].health();assert last['persisted_observations']>first['persisted_observations']
 row={'mode':label,'clients':len(clients),'seconds':elapsed,'reads':len(samples),'read_mean_ms':statistics.mean(samples),'read_p95_ms':sorted(samples)[int(len(samples)*.95)-1],'read_max_ms':max(samples),'before':before,'after':after,'cpu_percent_one_logical_core':(after['cpu_s']-before['cpu_s'])/elapsed*100,'persisted_delta':last['persisted_observations']-first['persisted_observations']};RESULT.append(row);print(label,row['read_mean_ms'],flush=True)
try:
 pa,pb,h=port(),port(),port()
 for name,p,seed in [('a',pa,42),('b',pb,77)]:start('source-'+name,[str(R/'target/debug/oip-simulated-server'),'--port',str(p),'--seed',str(seed),'--tick-ms','250'])
 config={'database':str(D/'legacy.sqlite'),'http_port':h,'sources':[{'id':'sim-a','name':'A','endpoint':f'opc.tcp://127.0.0.1:{pa}'},{'id':'sim-b','name':'B','endpoint':f'opc.tcp://127.0.0.1:{pb}'}],'web_dir':None}
 cfg=D/'core.json';cfg.write_text(json.dumps(config));legacy=Client(['--mcp-stdio','--legacy-single-infrastructure','--config',str(cfg),'--mcp-policy',str(R/'examples/mcp-read-local.json')],'legacy');wait(lambda:legacy.health()['lifecycle']=='ready');measure('OIP-006 stdio-owned mode (same final binary)',[legacy],legacy.ready['pid']);legacy.close()
 subprocess.run(['python3','examples/prepare-local-ipc.py',str(D/'ipc')],cwd=R,stdout=subprocess.DEVNULL,check=True)
 config['database']=str(D/'daemon.sqlite');cfg.write_text(json.dumps(config));daemon=start('daemon',[BIN,'--daemon','--legacy-single-infrastructure','--config',str(cfg),'--ipc-config',str(D/'ipc/ipc.json')]);sock=D/'ipc/mcp.sock';wait(lambda:sock.exists())
 args=['--mcp-bridge','--ipc-socket',str(sock),'--ipc-credential',str(D/'ipc/all.credential')]
 for n in [1,3,8]:
  clients=[Client(args,f'client-{n}-{i}') for i in range(n)];wait(lambda:clients[0].health()['lifecycle']=='ready');measure('OIP-007 daemon',clients,daemon.pid)
  for c in clients:c.close()
 daemon.send_signal(signal.SIGINT);daemon.wait(timeout=20);assert daemon.returncode==0
 logs=(O/'daemon.log').read_text();entries=[]
 for line in logs.splitlines():
  try:
   v=json.loads(line);f=v.get('fields',{})
   if f.get('code') in ['ipc_session_admitted','ipc_session_cleanup']:entries.append({'timestamp':v['timestamp'],**f})
  except (ValueError,KeyError):pass
 assert entries[-1]['active_sessions']==0;assert max(x['active_sessions'] for x in entries)>=8
 (O/'report.json').write_text(json.dumps({'verdict':'PASS','method':'8-second runs, SourceRead each50ms/client, same host/profile/two sources; SDK control-hop included; CPU clock10ms granularity, RSS point samples, OS threads not Tokio task count','runs':RESULT,'session_task_telemetry':entries,'scope':'short local development sample; no production SLA'},indent=2))
finally:
 for p in reversed(PROCS):
  if p.poll() is None:
   try:p.send_signal(signal.SIGINT);p.wait(timeout=15)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)

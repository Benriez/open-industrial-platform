#!/usr/bin/env python3
"""Physically unread stdout pipe, open stdin: legacy owned-core mode must exit."""
import pathlib,json,subprocess,socket,signal,time,select,urllib.request,os
R=pathlib.Path(__file__).resolve().parents[2];O=R/'docs/evidence/oip007/blocked-stdio';O.mkdir(parents=True,exist_ok=True);D=R/'target'/('b7-'+str(os.getpid()));D.mkdir();PROCS=[]
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def start(name,args,pipe=False):
 f=(O/(name+'.log')).open('w');p=subprocess.Popen(list(map(str,args)),cwd=R,stdin=subprocess.PIPE if pipe else subprocess.DEVNULL,stdout=subprocess.PIPE if pipe else f,stderr=f,text=True,bufsize=1);f.close();PROCS.append(p);return p
h,p=port(),port();db=D/'core.sqlite';cfg=D/'core.json';cfg.write_text(json.dumps({'database':str(db),'http_port':h,'web_dir':None,'sources':[{'id':'sim-a','name':'A','endpoint':f'opc.tcp://127.0.0.1:{p}'}]}))
try:
 sim=start('sim',[R/'target/debug/oip-simulated-server','--port',p,'--seed',42,'--tick-ms',250]);core=start('core',[R/'target/debug/oip-server','--mcp-stdio','--mcp-rest','--config',cfg,'--mcp-policy',R/'examples/mcp-read-local.json'],True)
 end=time.monotonic()+30
 while True:
  try:
   with urllib.request.urlopen(f'http://127.0.0.1:{h}/api/v1/core/health',timeout=2) as f:
    if json.load(f)['ready']:break
  except OSError:pass
  assert time.monotonic()<end;time.sleep(.1)
 core.stdin.write(json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'blocked-pipe-test','version':'1'}}})+'\n');core.stdin.flush();assert select.select([core.stdout],[],[],5)[0];assert json.loads(core.stdout.readline())['id']==1
 core.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
 for i in range(8):core.stdin.write(json.dumps({'jsonrpc':'2.0','id':i+2,'method':'tools/call','params':{'name':'oip_opcua_nodes_read','arguments':{'source':'sim-a','folder':'Bulk','limit':100,'offset':i*100}}})+'\n')
 core.stdin.flush();t=time.monotonic();core.wait(timeout=20);elapsed=time.monotonic()-t;assert core.returncode==0
 # No read or stdin-close before exit. All own runtime data must have drained.
 core.stdin.close();wire=core.stdout.read();log=(O/'core.log').read_text();report=[json.loads(x) for x in log.splitlines() if x.startswith('{') and '"clean"' in x][-1];assert report['clean'] and report['persistence_thread_joined'] and report['uncommitted']==0
 sim.send_signal(signal.SIGINT);sim.wait(timeout=10);assert sim.returncode==0
 (O/'report.json').write_text(json.dumps({'verdict':'PASS','elapsed_s':elapsed,'unread_pipe_bytes':len(wire),'stdin_open_until_exit':True,'shutdown':report,'mode':'legacy stdio-owned, no daemon'},indent=2))
finally:
 for p in reversed(PROCS):
  if p.poll() is None:
   try:p.send_signal(signal.SIGINT);p.wait(timeout=10)
   except subprocess.TimeoutExpired:p.kill();p.wait(timeout=3)

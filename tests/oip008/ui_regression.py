#!/usr/bin/env python3
"""Run unchanged browser/native clients against an owned local demo core; assert teardown."""
import subprocess,pathlib,socket,time,urllib.request,os,signal,json
ROOT=pathlib.Path(__file__).resolve().parents[2];OUT=pathlib.Path(os.environ.get('OIP_EVIDENCE_DIR',ROOT/'target/oip008-ui'));OUT.mkdir(parents=True,exist_ok=True);UI=pathlib.Path(os.environ.get('OIP_UI_DIR',ROOT/'apps/flutter'));RUN=ROOT/'target'/('oip0061-ui-'+str(os.getpid()));RUN.mkdir(parents=True)
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
h,p=port(),port();url=f'http://127.0.0.1:{h}'
with (OUT/'ui-backend.log').open('w') as log:core=subprocess.Popen([os.environ.get('OIP_SERVER_BIN',str(ROOT/'target/debug/oip-server')),'--demo','--web-dir',os.environ.get('OIP_WEB_DIR',str(UI/'build/web')),'--port',str(h),'--opcua-port',str(p),'--database',str(RUN/'demo.sqlite')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
results=[]
def ready():
 start=time.monotonic()
 while True:
  try:
   with urllib.request.urlopen(url+'/api/v1/system/status',timeout=1) as response:
    if json.load(response)['opcua_status']=='connected':return
  except (OSError,ValueError):pass
  if time.monotonic()-start>30:raise RuntimeError('demo core not ready')
  time.sleep(.1)
try:
 ready();env=dict(os.environ,OIP_URL=url,OIP_EVIDENCE_DIR=str(OUT/'browser'))
 commands=[('browser',['node','test/browser_oip004.mjs']),('interactions',['node','test/browser_spectrum.mjs']),('visual',['node','test/browser_visual_oip004.mjs']),('native_macos',['flutter','test','integration_test/live_dashboard_test.dart','-d','macos','--dart-define=OIP_API_URL='+url,'--reporter','expanded'])]
 # A cold native macOS build needs about eight minutes on this machine, the web
 # steps stay short. The bound only protects the owned process group; it never
 # replaces the positive test completion marker.
 bounds={'browser':300,'interactions':300,'visual':300,'native_macos':1800}
 for name,cmd in commands:
  env['OIP_EVIDENCE_DIR']=str(OUT/({'browser':'browser','interactions':'interactions','visual':'visual'}.get(name,'native')))
  with (OUT/(name+'-console.log')).open('w') as f:
   test=subprocess.Popen(cmd,cwd=UI,env=env,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
   started=time.monotonic()
   try:code=test.wait(timeout=bounds[name])
   except subprocess.TimeoutExpired:
    # Only the explicitly owned test process group, never other Xcode/previews.
    os.killpg(test.pid,signal.SIGTERM)
    try:test.wait(timeout=10)
    except subprocess.TimeoutExpired:os.killpg(test.pid,signal.SIGKILL);test.wait()
    code=124
   seconds=round(time.monotonic()-started,1)
  # Flutter can exit zero when interrupted before running a native test.
  # Exit status alone must never turn a cancelled build into acceptance.
  marker='All tests passed!' in (OUT/(name+'-console.log')).read_text(errors='replace')
  if name=='native_macos' and code==0 and not marker:code=125
  results.append({'name':name,'exit_code':code,'seconds':seconds,'test_completion_marker':marker,'status':'PASS' if code==0 else 'FAIL'});assert code==0,name
 ready()
finally:
 if core.poll() is None:core.send_signal(signal.SIGINT)
 core.wait(timeout=20);results.append({'name':'demo_core_shutdown','exit_code':core.returncode,'status':'PASS' if core.returncode==0 else 'FAIL'})
 (OUT/'ui-regression.json').write_text(json.dumps({'url':url,'process_id':core.pid,'results':results},indent=2))
assert core.returncode==0,'core shutdown failed'
print(json.dumps(results))

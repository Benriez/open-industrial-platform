#!/usr/bin/env python3
"""Run unchanged browser/native clients against an owned local demo core; assert teardown."""
import subprocess,pathlib,socket,time,urllib.request,os,signal,json
ROOT=pathlib.Path(__file__).resolve().parents[2];OUT=pathlib.Path(os.environ.get('OIP_EVIDENCE_DIR',ROOT/'target/oip008-ui'));OUT.mkdir(parents=True,exist_ok=True);UI=pathlib.Path(os.environ.get('OIP_UI_DIR',ROOT/'apps/flutter'));RUN=ROOT/'target'/('oip0061-ui-'+str(os.getpid()));RUN.mkdir(parents=True)
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
h,p=port(),port();url=f'http://127.0.0.1:{h}'
# The legacy web regression reads the rendered text from the document, so it
# needs the HTML renderer build. The CanvasKit build stays the artifact of the
# real SSH onboarding run. The served directory is recorded in the result.
WEB=os.environ.get('OIP_WEB_DIR') or str(UI/('build/web-html' if (UI/'build/web-html').is_dir() else 'build/web'))
with (OUT/'ui-backend.log').open('w') as log:core=subprocess.Popen([os.environ.get('OIP_SERVER_BIN',str(ROOT/'target/debug/oip-server')),'--demo','--web-dir',WEB,'--port',str(h),'--opcua-port',str(p),'--database',str(RUN/'demo.sqlite')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
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
 commands=[
  ('browser',['node','test/browser_oip004.mjs'],None),
  ('interactions',['node','test/browser_spectrum.mjs'],None),
  ('visual',['node','test/browser_visual_oip004.mjs'],None),
  # The native macOS build is slow on this machine, so it is a separate step
  # with its own bound and its own positive build marker.
  ('native_build',['flutter','build','macos','--debug'],'Built build/macos/Build/Products/Debug/oip_dashboard.app'),
  # The native integration test needs its own timeout: the default test timeout
  # also covers the native build and expires before the test itself runs.
  ('native_macos',['flutter','test','integration_test/live_dashboard_test.dart','-d','macos','--dart-define=OIP_API_URL='+url,'--reporter','expanded','--timeout','30m'],'All tests passed!'),
 ]
 # A cold native macOS build needs about eight minutes on this machine, the web
 # steps stay short. The bound only protects the owned process group; it never
 # replaces the positive test completion marker.
 bounds={'browser':300,'interactions':300,'visual':300,'native_build':1800,'native_macos':1800}
 for name,cmd,marker in commands:
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
  found=marker is None or marker in (OUT/(name+'-console.log')).read_text(errors='replace')
  if marker is not None and code==0 and not found:code=125
  results.append({'name':name,'exit_code':code,'seconds':seconds,'marker_required':marker,'marker_found':found,'status':'PASS' if code==0 else 'FAIL'});assert code==0,name
 ready()
finally:
 if core.poll() is None:core.send_signal(signal.SIGINT)
 core.wait(timeout=20);results.append({'name':'demo_core_shutdown','exit_code':core.returncode,'status':'PASS' if core.returncode==0 else 'FAIL'})
 (OUT/'ui-regression.json').write_text(json.dumps({'url':url,'web_dir':WEB,'process_id':core.pid,'results':results},indent=2))
assert core.returncode==0,'core shutdown failed'
print(json.dumps(results))

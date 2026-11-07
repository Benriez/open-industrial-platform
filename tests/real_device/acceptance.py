#!/usr/bin/env python3
"""Actual daemon/SSH/REST/browser-session/official MCP integration on owned loopback fixtures.
Never uses an operator DB or contacts a personal endpoint. Private keys stay in /private/tmp.
"""
import ast, pathlib, os, json, subprocess, time, urllib.request, urllib.error, http.cookiejar
ROOT=pathlib.Path(__file__).resolve().parents[2]
base=ROOT/'tests/oip0082/acceptance.py'; nodes=[]
for n in ast.parse(base.read_text().replace("('oip82-'+str(os.getpid()))","('oip-device-'+str(os.getpid())+'-'+str(time.time_ns()))")).body:
    if isinstance(n,ast.Try): break
    nodes.append(n)
exec(compile(ast.Module(body=nodes,type_ignores=[]),str(base),'exec'),globals())
OUT=pathlib.Path(os.environ['OIP_EVIDENCE_DIR']); OUT.mkdir(parents=True,exist_ok=True)
BIN=pathlib.Path(os.environ['OIP_SERVER_BIN']);SDK=BIN.parent/'examples/mcp_probe'
config.update(sources=[],web_dir=os.environ.get('OIP_WEB_DIR'))
plan=json.loads((ROOT/'examples/multi-infrastructure-plan.json').read_text())
plan['sources']=[];plan['bindings']=[b for b in plan['bindings'] if b['scope']['kind']!='source']
plan['roles'].append({'id':'inventory-admin','name':'Explicit scoped operator','permissions':['inventory_manage','devices_read','telemetry_read']})
plan['bindings'].append({'principal_id':'reader-org-a','role_id':'inventory-admin','scope':{'kind':'organization','id':'org-a'}})
plan['bindings'].append({'principal_id':'platform-reader','role_id':'inventory-admin','scope':{'kind':'platform'}})
from ssh_fixture import SshFixture
owned_fixture = None
if os.environ.get('OIP_SSH_FIXTURE'):
    fixture=json.loads(pathlib.Path(os.environ['OIP_SSH_FIXTURE']).read_text())
else:
    owned_fixture=SshFixture();fixture=owned_fixture.metadata()
    fixture_path=RUN/'ssh-fixture.json';fixture_path.write_text(json.dumps(fixture));os.environ['OIP_SSH_FIXTURE']=str(fixture_path)
fdir=pathlib.Path(fixture['directory'])
config['ssh']={'profiles':[{'id':'fixture','label':'Owned loopback SSH fixture','principals':['reader-org-a'],'allowed_hosts':['127.0.0.1'],'allowed_ports':[fixture['port'],port()],'identity_file':str(fdir/'client'),'agent_socket':None,'known_hosts_file':None,'aliases':{}}]}
(RUN/'core.json').write_text(json.dumps(config));(RUN/'plan.json').write_text(json.dumps(plan))
REPORT.update(baseline='49a86bb0aa9f737fe9392eb2b5421e1ffe2f8c68',physical_raspberry_pi_tested=False,ssh_fixture='owned loopback OpenSSH, actual host facts')
def request(path,body=None,principal='reader-org-a',headers=None,method=None,opener=None):
    h={} if principal is None else {'Authorization':'Bearer '+TOKENS[principal].hex()}
    if body is not None:h['Content-Type']='application/json'
    h.update(headers or {})
    q=urllib.request.Request(URL+path,data=None if body is None else json.dumps(body).encode(),headers=h,method=method)
    try:
        r=(opener or urllib.request).open(q,timeout=15) if opener else urllib.request.urlopen(q,timeout=15)
        with r:return r.status,json.load(r),r.headers
    except urllib.error.HTTPError as e:return e.code,json.load(e),e.headers
def change(body,ok=True,**kw):
    s,v,_=request('/api/v2/device-connections',body,**kw)
    assert (s==200)==ok,(s,v);return v
def poll(id,stage):
    def read():
        v=get('/api/v2/device-connections?plan_id='+id)
        if v['plan']['stage']=='failed':raise RuntimeError(v['plan']['error'])
        return v if v['plan']['stage']==stage else None
    return wait(read,'connection stage '+stage,timeout=35)
def endpoint(port_=None,user=None):return {'host':'127.0.0.1','port':port_ or fixture['port'],'user':user or fixture['user'],'identity_profile':'fixture'}
def issue(principal='reader-org-a'):
    # Intentionally capture in memory, never write the short-lived code to evidence logs.
    p=subprocess.run([str(BIN),'--browser-login','--ipc-socket',str(SOCK),'--ipc-credential',str(RUN/(principal+'.credential'))],capture_output=True,text=True,timeout=10)
    assert p.returncode==0,p.stderr
    return json.loads(p.stdout)['login_code']
try:
    p=start('provision',[BIN,'--config',RUN/'core.json','--provision',RUN/'plan.json']);assert p.wait(timeout=20)==0
    d=daemon('daemon');wait(lambda:req('/api/v2/inventory/devices')[0]==200,'daemon')
    assert request('/api/v2/device-connections',principal=None)[0]==403
    code=issue();jar=http.cookiejar.CookieJar();browser=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    assert request('/api/v2/browser/login',{'code':code},None,{'Origin':'http://foreign.invalid'},opener=browser)[0]==403
    s,session,h=request('/api/v2/browser/login',{'code':code},None,{'Origin':URL},opener=browser);assert s==200 and session['principal_id']=='reader-org-a'
    assert 'HttpOnly' in h['Set-Cookie'] and 'SameSite=Strict' in h['Set-Cookie'] and h['Cache-Control']=='no-store'
    assert h['X-Frame-Options']=='DENY' and h['Content-Security-Policy']=="frame-ancestors 'none'"
    assert request('/api/v2/browser/login',{'code':code},None,{'Origin':URL})[0]==403
    assert request('/api/v2/inventory/devices',principal=None,opener=browser)[0]==200
    body={'changes':[{'operation':'register','device':{'id':'existing-pi','display_name':'Existing inventory identity','device_type':'single_board_computer','site_id':'site-a1','metadata':{}}}]}
    assert request('/api/v2/inventory/apply',body,None,{'Origin':URL},opener=browser)[0]==403
    bh={'Origin':URL,'x-oip-csrf':session['csrf_token']}
    assert request('/api/v2/inventory/apply',body,None,bh,opener=browser)[0]==200
    assert request('/api/v2/inventory/apply',body,None,dict(bh,Origin='http://foreign.invalid'),opener=browser)[0]==403
    foreign=json.loads(json.dumps(body));foreign['changes'][0]['device'].update(id='foreign-write',site_id='site-b1')
    assert request('/api/v2/inventory/apply',foreign,None,bh,opener=browser)[0] in [400,403,404]
    foreign['principal']='platform-reader';assert request('/api/v2/inventory/apply',foreign,None,bh,opener=browser)[0]!=200
    inv=get('/api/v2/inventory/devices');assert len(inv['items'])==1 and inv['items'][0]['telemetry']=='no_collector'
    record('browser_identity_online_writer',{'single_use_pairing':True,'http_only_cookie':True,'csrf_origin':True,'trusted_principal':'reader-org-a','foreign_site_denied':True,'single_writer_online_registration':True})
    target={'kind':'existing','id':'existing-pi','expected_revision':1}
    dead=config['ssh']['profiles'][0]['allowed_ports'][1]
    fail=change({'operation':'start','target':target,'endpoint':endpoint(dead)})['plan']['plan_id']
    wait(lambda:get('/api/v2/device-connections?plan_id='+fail)['plan']['stage']=='failed','dead endpoint fails')
    assert get('/api/v2/inventory/devices')['items'][0]['record']['revision']==1
    assert not get('/api/v2/device-connections?device_id=existing-pi')['connection']
    change({'operation':'start','target':target,'endpoint':dict(endpoint(),host='192.0.2.9')},ok=False)
    change({'operation':'start','target':target,'endpoint':endpoint()},ok=False,principal='reader-org-b')
    cancelled=change({'operation':'start','target':target,'endpoint':endpoint()})['plan']['plan_id']
    assert change({'operation':'cancel','plan_id':cancelled})['plan']['stage']=='cancelled'
    wrong=change({'operation':'start','target':target,'endpoint':endpoint(user=fixture['user']+'-not-authorized')})['plan']['plan_id']
    wrong_key=poll(wrong,'awaiting_host_key')['plan']['host_key_fingerprint']
    change({'operation':'trust_host_key','plan_id':wrong,'fingerprint':wrong_key})
    change({'operation':'verify','plan_id':wrong})
    wait(lambda:get('/api/v2/device-connections?plan_id='+wrong)['plan']['stage']=='failed','authentication failure')
    assert get('/api/v2/device-connections?plan_id='+wrong)['plan']['error']['code']=='SSH_AUTHENTICATION_FAILED'
    assert not get('/api/v2/device-connections?device_id=existing-pi')['connection']
    assert request('/api/v2/device-connections',dict(operation='start',target=target,endpoint=endpoint(),principal='platform-reader'))[0]==400
    assert request('/api/v2/device-connections',dict(operation='start',target=target,endpoint=endpoint(),actor='platform-reader'))[0]==400
    r=change({'operation':'start','target':target,'endpoint':endpoint()});pid=r['plan']['plan_id']
    r=poll(pid,'awaiting_host_key');fp=r['plan']['host_key_fingerprint'];assert fp.startswith('SHA256:') and not r['plan']['identity']
    change({'operation':'verify','plan_id':pid},ok=False)
    change({'operation':'trust_host_key','plan_id':pid,'fingerprint':'SHA256:incorrect'},ok=False)
    change({'operation':'trust_host_key','plan_id':pid,'fingerprint':fp})
    change({'operation':'verify','plan_id':pid});r=poll(pid,'verification_complete')
    facts=r['plan']['identity'];assert facts['operating_system'] in ['Linux','Darwin'] and facts['hostname'] and facts['memory_total_bytes']>0
    assert get('/api/v2/inventory/devices')['items'][0]['record']['revision']==1
    change({'operation':'confirm','plan_id':pid,'identity_confirmed':False,'enable_monitoring':True,'poll_seconds':10},ok=False)
    r=change({'operation':'confirm','plan_id':pid,'identity_confirmed':True,'enable_monitoring':True,'poll_seconds':10});c=r['connection'];assert c['device_id']=='existing-pi'
    assert get('/api/v2/inventory/devices')['items'][0]['record']['revision']==2
    wait(lambda:get('/api/v2/device-connections?device_id=existing-pi')['connection']['status']=='collecting','actual monitoring')
    v=get('/api/v2/device-connections?device_id=existing-pi');assert v['connection']['observations']
    assert sql('PRAGMA foreign_key_check')==[] and sql('PRAGMA integrity_check')[0]['integrity_check']=='ok'
    assert sql('select count(*) n from inventory_devices')[0]['n']==1
    client=Client('reader-org-a','official-mcp');assert client.call('device_connection_read',{'device_id':'existing-pi'})['connection']['device_id']=='existing-pi'
    change({'operation':'monitoring','device_id':'existing-pi','expected_revision':1,'enabled':False,'poll_seconds':10})
    time.sleep(.4)
    assert client.call('device_connection_read',{'device_id':'existing-pi'})==get('/api/v2/device-connections?device_id=existing-pi')
    change({'operation':'monitoring','device_id':'existing-pi','expected_revision':1,'enabled':True,'poll_seconds':10},ok=False)
    change({'operation':'monitoring','device_id':'existing-pi','expected_revision':2,'enabled':True,'poll_seconds':0},ok=False)
    change({'operation':'monitoring','device_id':'existing-pi','expected_revision':2,'enabled':True,'poll_seconds':10})
    change({'operation':'monitoring','device_id':'existing-pi','expected_revision':3,'enabled':True,'poll_seconds':10},ok=False,principal='platform-reader')
    client.denied('device_connection_configure',{'operation':'monitoring','device_id':'existing-pi','enabled':False,'poll_seconds':10,'expected_revision':1})
    other=Client('reader-org-b','foreign-mcp');other.denied('device_connection_read',{'device_id':'existing-pi'});other.close();client.close()
    record('ssh_handshake_confirmation_monitoring',{'explicit_host_key_consent':True,'verified_hostname_present':True,'facts_os':facts['operating_system'],'existing_id_preserved':True,'inventory_count':1,'actual_observations':count(),'read_only_mcp_parity':True,'physical_pi':False})
    live=browser.open(urllib.request.Request(URL+'/api/v2/stream'),timeout=5)
    while not live.readline().startswith(b'data:'): pass
    assert request('/api/v2/browser/session',principal=None,headers=bh,method='DELETE',opener=browser)[0]==200
    assert request('/api/v2/inventory/devices',principal=None,opener=browser)[0]==403
    while True:
        line=live.readline()
        if line.startswith(b'event:'):
            assert line.strip()==b'event: error'; break
    live.close()
    if owned_fixture: owned_fixture.stop()
    stop(d);stored=count();d=daemon('restart');wait(lambda:req('/api/v2/device-connections?device_id=existing-pi')[0]==200,'restart connection')
    if owned_fixture:
        restored=get('/api/v2/device-connections?device_id=existing-pi')['connection']
        assert restored['observations'] and all(o['freshness']=='stale' for o in restored['observations']) and count()==stored
        owned_fixture.start()
    wait(lambda:get('/api/v2/device-connections?device_id=existing-pi')['connection']['status']=='collecting','restart actual sampling',timeout=50)
    before_crash=count()
    if owned_fixture: owned_fixture.stop()
    stop(d,True);d=daemon('crash-recovery');wait(lambda:req('/api/v2/device-connections?device_id=existing-pi')[0]==200,'crash restore')
    if owned_fixture:
        assert all(o['freshness']=='stale' for o in get('/api/v2/device-connections?device_id=existing-pi')['connection']['observations']) and count()==before_crash
        owned_fixture.start()
    wait(lambda:count()>before_crash,'new genuine crash-recovery sampling',timeout=50)
    assert sql('select count(*) n from inventory_devices')[0]['n']==1
    assert sql('PRAGMA integrity_check')[0]['integrity_check']=='ok' and sql('PRAGMA foreign_key_check')==[]
    assert sql('select count(*) n from (select observation_key from observations group by observation_key having count(*)>1)')[0]['n']==0
    record('restart_sigkill_identity',{'same_device_id':True,'config_survives':True,'integrity':'ok','foreign_keys':True,'duplicate_keys':0})
    if os.environ.get('OIP_BROWSER_SCRIPT'):
        body={'changes':[{'operation':'register','device':{'id':'browser-existing','display_name':'Browser SSH fixture','device_type':'server','site_id':'site-a1','metadata':{}}}]}
        assert request('/api/v2/inventory/apply',body)[0]==200
        env=dict(os.environ,OIP_URL=URL,OIP_IPC_SOCKET=str(SOCK),OIP_BROWSER_CREDENTIAL=str(RUN/'reader-org-a.credential'),OIP_BROWSER_EVIDENCE=str(OUT/'browser'))
        with (OUT/'browser.log').open('w') as log:
            p=subprocess.run(['node',os.environ['OIP_BROWSER_SCRIPT']],env=env,cwd=ROOT,stdout=log,stderr=log,timeout=180)
        assert p.returncode==0,'Actual Flutter onboarding failed; inspect browser receipt'
        assert get('/api/v2/device-connections?device_id=browser-existing')['connection']['status']=='collecting'
        record('actual_flutter_ssh_onboarding',{'existing_id':'browser-existing','real_loopback_ssh':True,'no_private_hardware_contact':True})
    readers=[Client('reader-org-a','ssh-parallel-'+str(i)) for i in range(8)]
    import concurrent.futures
    with concurrent.futures.ThreadPoolExecutor(8) as pool:
        values=list(pool.map(lambda c:c.call('device_connection_read',{'device_id':'existing-pi'}),readers))
    assert all(v['connection']['device_id']=='existing-pi' for v in values)
    latency=[]
    for _ in range(20):
        t=time.perf_counter();readers[1].call('device_connection_read',{'device_id':'existing-pi'});latency.append((time.perf_counter()-t)*1000)
    REPORT['performance']={'connection_read_official_mcp':{'samples':20,'p50_ms':sorted(latency)[9],'p95_ms':sorted(latency)[18]},'core_rss_kib_cpu_percent':subprocess.check_output(['ps','-p',str(d.pid),'-o','rss=,%cpu='],text=True).strip(),'short_local_measurement_not_sla':True}
    readers[0].abort();assert d.poll() is None
    for client in readers:client.close()
    without_clients=count()
    wait(lambda:count()>without_clients,'ingestion without MCP or browser sessions',timeout=40)
    record('no_clients_ingestion_progress',{'before':without_clients,'after':count(),'no_browser_or_mcp_sessions':True})
    if owned_fixture:
        before=count();owned_fixture.rotate()
        wait(lambda:get('/api/v2/device-connections?device_id=existing-pi')['connection']['status']=='host_key_changed','changed host key blocked',timeout=45)
        blocked=count();time.sleep(1);assert count()==blocked
        assert get('/api/v2/inventory/devices?id=existing-pi')['items'][0]['record']['device']['id']=='existing-pi'
        record('host_key_change_blocks_collection',{'changed_key_rejected':True,'existing_id_unchanged':True,'new_observations_after_block':0})
    record('eight_official_mcp_clients',{'clients':8,'shared_core':True,'disconnect_isolated':True})
    REPORT['status']='PASS'
finally:
    for c in CLIENTS:
        try:c.close()
        except Exception:pass
    for p in reversed(PROCS):
        if p.poll() is None:p.send_signal(signal.SIGINT)
        try:p.wait(timeout=20)
        except subprocess.TimeoutExpired:p.kill();p.wait()
    if owned_fixture: owned_fixture.stop()
    REPORT['own_processes_stopped']=all(p.poll() is not None for p in PROCS)
    (OUT/'report.json').write_text(json.dumps(REPORT,indent=2))

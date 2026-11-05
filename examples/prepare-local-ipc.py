#!/usr/bin/env python3
"""Operator-only local setup. Create a NEW private directory; never replace credentials.
No service is installed or started. Keep directory outside transferable source.
"""
import argparse,json,os,pathlib,secrets
p=argparse.ArgumentParser();p.add_argument('directory',type=pathlib.Path);a=p.parse_args();d=a.directory
if not d.is_absolute() or d.parent.resolve()!=d.parent:raise SystemExit('use an absolute path with canonical existing parent')
if len(str(d/'mcp.sock').encode())>100:raise SystemExit('Unix socket path too long; use a shorter directory')
d.mkdir(mode=0o700)
permissions=['core_read','sources_read','devices_read','telemetry_read','events_read','opcua_read']
clients=[]
def create(name,data):
 fd=os.open(d/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 with os.fdopen(fd,'wb') as f:f.write(data)
for name,source in [('all',None),('source-a','sim-a'),('source-b','sim-b')]:
 credential=d/(name+'.credential');create(credential.name,secrets.token_bytes(32))
 clients.append({'uid':os.geteuid(),'credential_file':str(credential),'policy':{'actor':'local-'+name+'-reader','permissions':permissions,'sources':{'kind':'all'} if source is None else {'kind':'only','sources':[source]}}})
config={'socket':str(d/'mcp.sock'),'max_sessions':16,'clients':clients,'rest_policy':{'actor':'local-rest-operator','permissions':permissions,'sources':{'kind':'all'}}}
create('ipc.json',(json.dumps(config,indent=2)+'\n').encode())
print(json.dumps({'ipc_config':str(d/'ipc.json'),'socket':config['socket'],'credential_files':[c['credential_file'] for c in clients]},indent=2))

#!/usr/bin/env python3
"""Local operator frontend: serialization only; Rust performs all validation/authorization/CAS.
No network discovery, credential export, daemon launch or silent global grant.
"""
import argparse,csv,io,json,os,pathlib,secrets,subprocess,tempfile,uuid,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--binary',type=pathlib.Path,default=pathlib.Path(os.environ.get('OIP_SERVER_BIN',ROOT/'target/debug/oip-server')));sub=p.add_subparsers(dest='operation',required=True)
i=sub.add_parser('init');i.add_argument('--directory',type=pathlib.Path,required=True)
for name in ['organization','infrastructure','site','operator']:i.add_argument('--'+name+'-name',required=True)
i.add_argument('--port',type=int,default=8080);i.add_argument('--apply',action='store_true')
for op in ['add','update','archive','import','list','show','cleanup-plan']:
 q=sub.add_parser(op);q.add_argument('--config',type=pathlib.Path,required=True);q.add_argument('--principal',required=True)
 if op in ['add','update','archive','import']:q.add_argument('--apply',action='store_true')
 if op in ['add','update']:
  q.add_argument('--id',required=op=='update');q.add_argument('--name',required=op=='add');q.add_argument('--type',required=op=='add');q.add_argument('--site',required=op=='add');q.add_argument('--description',default='' if op=='add' else None);q.add_argument('--metadata',type=pathlib.Path)
 if op in ['update','archive']:q.add_argument('--revision',type=int,required=True)
 if op in ['archive','show']:q.add_argument('--id',required=True)
 if op=='import':q.add_argument('--file',type=pathlib.Path,required=True)
 if op=='list':q.add_argument('--site');q.add_argument('--search');q.add_argument('--limit',type=int,default=40);q.add_argument('--offset',type=int,default=0)
a=p.parse_args()
def invoke(config,flag,body,apply=False,capture=False):
 # Own bounded request file only. No shell, no credentials in arguments or output.
 with tempfile.TemporaryDirectory(prefix='oip-inventory-') as d:
  f=pathlib.Path(d)/'request.json';f.write_text(json.dumps(body));f.chmod(0o600)
  cmd=[str(a.binary),'--config',str(config),flag,str(f)]+(['--inventory-apply'] if apply else [])
  r=subprocess.run(cmd,cwd=ROOT,capture_output=capture,text=capture)
  return r if capture else r.returncode
def current_device(config,principal,id):
 with tempfile.TemporaryDirectory(prefix='oip-inventory-read-') as d:
  f=pathlib.Path(d)/'query.json';f.write_text(json.dumps({'principal':principal,'query':{'id':id}}));f.chmod(0o600)
  r=subprocess.run([str(a.binary),'--config',str(config),'--inventory-query',str(f)],cwd=ROOT,capture_output=True,text=True)
  if r.returncode:sys.stderr.write(r.stderr);raise SystemExit(r.returncode)
  return json.loads(r.stdout)['value']['items'][0]['record']
def ident():return str(uuid.uuid4())
if a.operation=='init':
 directory=a.directory
 if not directory.is_absolute() or directory.parent.resolve()!=directory.parent or len(str(directory/'s'))>95:p.error('use a new short canonical absolute private directory')
 if not 1<=a.port<=65535:p.error('invalid local HTTP port')
 directory.mkdir(mode=0o700,exist_ok=False)
 org,infra,site,principal=[ident() for _ in range(4)];role=ident()
 config={'database':str(directory/'core.sqlite'),'http_port':a.port,'sources':[],'web_dir':None}
 plan={'organizations':[{'id':org,'name':a.organization_name}],'infrastructures':[{'id':infra,'organization_id':org,'name':a.infrastructure_name}],'sites':[{'id':site,'infrastructure_id':infra,'name':a.site_name}],'sources':[],'principals':[{'id':principal,'name':a.operator_name,'enabled':True}],'roles':[{'id':role,'name':'Explicit organization-local inventory operator','permissions':['hierarchy_read','devices_read','sources_read','telemetry_read','events_read','opcua_read','settings_read','inventory_manage']}],'bindings':[{'principal_id':principal,'role_id':role,'scope':{'kind':'organization','id':org}}],'legacy_single_infrastructure':False}
 credential=directory/'operator.credential';credential.write_bytes(secrets.token_bytes(32));credential.chmod(0o600)
 # UID comes from OS, not an asserted MCP principal.
 ipc={'socket':str(directory/'s'),'clients':[{'uid':os.geteuid(),'credential_file':str(credential),'policy':{'principal':principal}}]}
 for name,body in [('core.json',config),('plan.json',plan),('ipc.json',ipc),('operator.json',{'principal':principal})]:f=directory/name;f.write_text(json.dumps(body,indent=2)+'\n');f.chmod(0o600)
 if a.apply:
  subprocess.run([str(a.binary),'--config',str(directory/'core.json'),'--provision',str(directory/'plan.json')],check=True,cwd=ROOT)
  subprocess.run([str(a.binary),'--config',str(directory/'core.json'),'--inventory-initialize',str(directory/'operator.json')],check=True,cwd=ROOT)
 print(json.dumps({'directory':str(directory),'organization_id':org,'infrastructure_id':infra,'site_id':site,'principal_id':principal,'applied':a.apply,'devices_seeded':0,'sources_seeded':0,'platform_grants':False,'credentials_exported':False}));raise SystemExit(0)
if a.operation in ['list','show']:
 query={'id':a.id} if a.operation=='show' else {'site':a.site,'q':a.search,'offset':a.offset,'limit':a.limit}
 raise SystemExit(invoke(a.config,'--inventory-query',{'principal':a.principal,'query':query}))
if a.operation=='cleanup-plan':raise SystemExit(invoke(a.config,'--inventory-cleanup-plan',{'principal':a.principal}))
if a.operation in ['add','update']:
 sys.stderr.write('Inventory only: this command does not connect to a device, verify SSH identity or enable monitoring.\n')
 if a.operation=='update':
  if all(v is None for v in [a.name,a.type,a.site,a.description,a.metadata]):p.error('update requires an explicit changed field')
  record=current_device(a.config,a.principal,a.id)
  if record['revision']!=a.revision:p.error('revision conflict; reread before updating')
  device=record['device']
  for name,key in [('name','display_name'),('type','device_type'),('site','site_id')]:
   value=getattr(a,name)
   if value is not None:device[key]=value
  if a.description is not None:device['metadata']['description']=a.description
 else:device={'id':a.id or ident(),'display_name':a.name,'device_type':a.type,'site_id':a.site,'metadata':{'description':a.description}}
 if a.metadata:
  if a.metadata.stat().st_size>16384:p.error('metadata request too large')
  patch=json.loads(a.metadata.read_text())
  if not isinstance(patch,dict):p.error('metadata must be an object')
  device['metadata'].update(patch)
 change={'operation':'register' if a.operation=='add' else 'update','device':device}
 if a.operation=='update':change['expected_revision']=a.revision
 changes=[change]
elif a.operation=='archive':changes=[{'operation':'archive','id':a.id,'expected_revision':a.revision}]
else:
 if a.file.stat().st_size>1_048_576:p.error('import too large')
 data=a.file.read_text(encoding='utf-8')
 if a.file.suffix.lower()=='.csv':
  reader=csv.DictReader(io.StringIO(data),strict=True);required={'id','display_name','device_type','site_id'};allowed=required|{'description','manufacturer','model','hostname','ip_address','mac_address','serial_number','operating_system','physical_location','notes','tags'}
  if not reader.fieldnames or len(set(reader.fieldnames))!=len(reader.fieldnames) or not required<=set(reader.fieldnames) or set(reader.fieldnames)-allowed:p.error('invalid or duplicate CSV headers')
  changes=[]
  for row in reader:
   if len(changes)>=100 or None in row:p.error('invalid/bounded CSV row')
   metadata={k:v for k,v in row.items() if k not in required and v}
   if 'tags' in metadata:metadata['tags']=json.loads(metadata['tags'])
   changes.append({'operation':'register','device':{**{k:row[k] for k in required},'metadata':metadata}})
 else:
  body=json.loads(data);changes=body['changes'] if isinstance(body,dict) and set(body)=={'changes'} else body
# Dry-run output contains stable IDs. Reuse the printed normalized plan to apply an add later.
body={'principal':a.principal,'changes':changes}
validated=invoke(a.config,'--inventory-plan',body,capture=True)
if validated.returncode:
 sys.stderr.write(validated.stderr);raise SystemExit(validated.returncode)
# Never echo rejected unknown/credential fields from a metadata/import file.
print(json.dumps({'normalized_plan':body},ensure_ascii=False),flush=True)
if getattr(a,'apply',False):raise SystemExit(invoke(a.config,'--inventory-plan',body,True))
sys.stdout.write(validated.stdout);sys.stderr.write(validated.stderr);raise SystemExit(0)

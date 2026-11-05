#!/usr/bin/env python3
"""Create new private, local development config. Never overwrite a previous setup.
No core/collector/database is started; provisioning still needs exclusive operator CLI.
"""
import argparse,json,os,pathlib,secrets
p=argparse.ArgumentParser();p.add_argument('--directory',type=pathlib.Path,required=True);args=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];directory=args.directory
if not directory.is_absolute() or directory.parent.resolve()!=directory.parent or len(str(directory/'s'))>95:
 p.error('use a short absolute directory under a canonical parent, e.g. /private/tmp/oip008-local')
directory.mkdir(mode=0o700,exist_ok=False)
config=json.loads((root/'examples/multi-infrastructure-core.json').read_text());config['database']=str(directory/'core.sqlite');config['web_dir']=None
(directory/'core.json').write_text(json.dumps(config,indent=2)+'\n');(directory/'plan.json').write_bytes((root/'examples/multi-infrastructure-plan.json').read_bytes())
clients=[]
for principal in ['reader-org-a','reader-infra-a1','reader-org-b','reader-site-a1','reader-source-b','platform-reader']:
 credential=directory/(principal+'.credential')
 with credential.open('xb') as f:f.write(secrets.token_bytes(32))
 credential.chmod(0o600);clients.append({'uid':os.geteuid(),'credential_file':str(credential),'policy':{'principal':principal}})
file=directory/'ipc.json';file.write_text(json.dumps({'socket':str(directory/'s'),'max_sessions':16,'clients':clients},indent=2)+'\n');file.chmod(0o600)
print(json.dumps({'directory':str(directory),'http':'http://127.0.0.1:18808','config':'core.json','provisioning_required':True,'credential_contents_printed':False}))

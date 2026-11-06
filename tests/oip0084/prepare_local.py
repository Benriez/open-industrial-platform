#!/usr/bin/env python3
"""Explicit, offline-only development settings profile. No DB/service/credentials export.
Creates a new private directory via the existing setup generator. Never overwrites a profile.
"""
import argparse,json,pathlib,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('--directory',type=pathlib.Path,required=True);p.add_argument('--settings-operator-principal',choices=['platform-reader'],required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2]
subprocess.run([sys.executable,str(root/'tests/oip008/prepare_local.py'),'--directory',str(a.directory)],check=True,stdout=subprocess.DEVNULL)
file=a.directory/'plan.json';plan=json.loads(file.read_text());plan['roles'].append({'id':'explicit-settings-operator','name':'Explicit offline local settings operator','permissions':['settings_read','settings_write','mcp_management_read']});plan['bindings'].append({'principal_id':a.settings_operator_principal,'role_id':'explicit-settings-operator','scope':{'kind':'platform'}});file.write_text(json.dumps(plan,indent=2)+'\n')
print(json.dumps({'directory':str(a.directory),'provisioning_required':True,'explicit_settings_operator':a.settings_operator_principal,'credentials_exported':False,'service_started':False}))

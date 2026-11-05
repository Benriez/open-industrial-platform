#!/usr/bin/env python3
"""Repeat the existing local OIP-006 Rust gates without altering their arguments."""
import pathlib,json,os,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[2];OUT=ROOT/'docs/evidence/oip007'
env=dict(os.environ,CARGO_INCREMENTAL='0',CARGO_PROFILE_DEV_DEBUG='0',CARGO_PROFILE_TEST_DEBUG='0',CARGO_BUILD_JOBS='2')
commands=[(r['name'],r['command']) for r in json.loads((ROOT/'docs/evidence/oip006/rust-regression.json').read_text())]
commands += [('deny',['target/oip-002-tools/bin/cargo-deny','check','advisories','licenses','bans','sources']),('build',['cargo','build','--locked','--workspace']),('examples',['cargo','build','--locked','-p','oip-server','--examples'])]
results=[]
for name,cmd in commands:
 with (OUT/('rust-'+name+'.log')).open('w') as f:code=subprocess.call(cmd,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT)
 results.append({'name':name,'command':cmd,'status':'PASS' if code==0 else 'FAIL','exit_code':code});(OUT/'rust-regression.json').write_text(json.dumps(results,indent=2));print(name,code,flush=True)
 if code:raise SystemExit(code)

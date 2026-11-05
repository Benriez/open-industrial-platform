#!/usr/bin/env python3
"""Validate the fixed supplier package and reconstruct all three merge inputs, outside checkout."""
import json,hashlib,tarfile,re,subprocess,shutil,struct
from pathlib import Path,PurePosixPath
ROOT=Path(__file__).resolve().parents[2]
BACKUP=Path('/Users/benny/Documents/OIP-Handoffs/core-0061-baseline-20261104T232930Z')
HANDOFF=Path('/Users/benny/Documents/OIP-Handoffs/ui-005-spectrum/20261104T231122Z-ses_e574f4783ffe57EjpGTv3i535K')
OUT=ROOT/'docs/evidence/oip0061';WORK=BACKUP/'validation';WORK.mkdir(exist_ok=True)
archive=HANDOFF/'oip-005-ui-spectrum-handoff.tar.gz'
sha=lambda b:hashlib.sha256(b).hexdigest()
assert sha(archive.read_bytes())=='be767ee48de12d120b46b599da2e4fa6906c29bfccfe21a7189bbe9ff4da6ad6'
def safe(name,directory=False):
 assert '\\' not in name and not any(ord(c)<32 for c in name),name
 raw=name[2:] if name.startswith('./') else name
 if directory:raw=raw.rstrip('/')
 if raw in ['', '.']:
  assert directory;return ''
 p=PurePosixPath(raw);assert not p.is_absolute() and '..' not in p.parts and str(p)==raw,name
 return raw
files={};seen=set();sizes=0
with tarfile.open(archive,'r:gz') as t:
 members=t.getmembers();assert len(members)<512
 for m in members:
  assert m.isfile() or m.isdir(),m.name
  n=safe(m.name,m.isdir());assert n not in seen,n;seen.add(n)
  assert m.size<=64*1024*1024; sizes+=m.size;assert sizes<128*1024*1024
  if m.isfile():files[n]=t.extractfile(m).read()
manifest={}
for line in files['SHA256SUMS'].decode().splitlines():
 match=re.fullmatch(r'([0-9a-f]{64})  (.+)',line);assert match,line
 n=safe(match[2]);assert n not in manifest;nbytes=files[n];assert sha(nbytes)==match[1],n;manifest[n]=match[1]
assert set(files)==set(manifest)|{'SHA256SUMS'},set(files)^set(manifest)
for n in ['change-manifest.json','spectrum.patch','OIP_005_UI_SPECTRUM_HANDOFF.md']:assert files[n]==(HANDOFF/n).read_bytes(),n
changes=json.loads(files['change-manifest.json']);assert changes['changed_files']==15 and len(changes['files'])==15
paths={c['path'] for c in changes['files']};assert len(paths)==15
assert {n.removeprefix('payload/') for n in files if n.startswith('payload/')}==paths
for c in changes['files']:
 p=c['path'];assert p.startswith('apps/flutter/') and p.endswith(('.dart','.md','.mjs','.json'))
 assert not any(v in p for v in ['/../','.env','.pem','.key'])
 assert sha(files['payload/'+p])==c['spectrum_sha256']
 assert b'-----BEGIN PRIVATE KEY-----' not in files['payload/'+p]
patch_paths=set()
for line in files['spectrum.patch'].decode().splitlines():
 if line.startswith(('--- ','+++ ')):
  p=line[4:].split('\t')[0]
  if p=='/dev/null':continue
  assert p.startswith(('a/','b/')),p;p=p[2:];assert p in paths,p;patch_paths.add(p)
assert patch_paths==paths
# No extractall; only already validated regular files, into the external workspace.
theirs=WORK/'theirs';base=WORK/'base';roundtrip=WORK/'roundtrip'
for directory in [theirs,base,roundtrip]:assert not directory.exists(),directory
for n,data in files.items():
 target=theirs/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
shutil.copytree(theirs/'payload',base)
patch=theirs/'spectrum.patch'
with (WORK/'reverse.log').open('w') as log:subprocess.run(['patch','--batch','--fuzz=0','-R','-p1','-i',str(patch)],cwd=base,stdout=log,stderr=subprocess.STDOUT,check=True)
canonical=json.loads((ROOT/'docs/evidence/oip005/reconciliation-005-1/final-source-hashes.json').read_text());canonical={p:h for p,h in canonical.items() if p.startswith('apps/flutter/')};assert len(canonical)==79
assert all(sha((ROOT/p).read_bytes())==h for p,h in canonical.items())
rows=[]
for c in changes['files']:
 p=c['path'];bp=base/p;ours=ROOT/p;theirs_bytes=files['payload/'+p]
 if c['baseline_sha256'] is None:
  assert p not in canonical and (not bp.exists() or not bp.read_bytes());assert not ours.exists()
  if bp.exists():bp.unlink() # Reverse patch can leave an empty new-file placeholder.
  kind='Neu'
 else:
  assert bp.exists() and sha(bp.read_bytes())==c['baseline_sha256']==canonical[p]
  oh=sha(ours.read_bytes())
  kind='Identisch' if oh==c['baseline_sha256']==c['spectrum_sha256'] else 'Bereits integriert' if oh==c['spectrum_sha256'] else 'Konfliktfrei geändert' if oh==c['baseline_sha256'] else 'Semantischer Konflikt'
 rows.append({'path':p,'classification':kind,'base_sha256':c['baseline_sha256'],'ours_sha256':sha(ours.read_bytes()) if ours.exists() else None,'theirs_sha256':c['spectrum_sha256']})
shutil.copytree(base,roundtrip)
with (WORK/'forward.log').open('w') as log:subprocess.run(['patch','--batch','--fuzz=0','-p1','-i',str(patch)],cwd=roundtrip,stdout=log,stderr=subprocess.STDOUT,check=True)
assert all(sha((roundtrip/c['path']).read_bytes())==c['spectrum_sha256'] for c in changes['files'])
screens=json.loads(files['screenshot-manifest.json']);assert len(screens['files'])==66
for c in screens['files']:
 data=files[c['path']];assert sha(data)==c['sha256'] and len(data)==c['bytes'];assert data[:8]==b'\x89PNG\r\n\x1a\n';assert struct.unpack('>II',data[16:24])==(c['width'],c['height'])
result={'archive_sha256':sha(archive.read_bytes()),'archive_members':len(members),'manifested_files':len(manifest),'payload_files':len(rows),'canonical_baseline_files_verified':len(canonical),'screenshots_verified':66,'roundtrip_files':15,'workspace':str(WORK),'files':rows,'verdict':'PASS'}
(OUT/'handoff-verification.json').write_text(json.dumps(result,indent=2))
for n in ['change-manifest.json','SHA256SUMS','OIP_005_UI_SPECTRUM_HANDOFF.md','performance.json','screenshot-manifest.json']:(OUT/('supplier-'+n)).write_bytes(files[n])
for n in ['baseline.json','sessions.json']:(OUT/n).write_bytes((BACKUP/n).read_bytes())
print(json.dumps(result,indent=2))

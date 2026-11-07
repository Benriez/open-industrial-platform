#!/usr/bin/env python3
"""Explicit offline local operator configuration. No SSH connection or key export.
Requires the existing exclusive DB ownership sidecar; never modifies SQLite.
Core validates Principal permissions again at every use. Same-UID local trust applies.
"""
import argparse, pathlib, os, stat, json, fcntl, hashlib, datetime, ipaddress, re
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--config',type=pathlib.Path,required=True)
p.add_argument('--principal',required=True)
p.add_argument('--profile',default='operator-ssh')
p.add_argument('--label',default='Lokale Operator-SSH-Identität')
p.add_argument('--host',required=True)
p.add_argument('--port',type=int,default=22)
p.add_argument('--identity-file',type=pathlib.Path,required=True)
p.add_argument('--apply',action='store_true')
a=p.parse_args()
def private(path):
    if not path.is_absolute() or path.is_symlink():p.error('absolute non-symlink private file required')
    m=path.stat()
    if not stat.S_ISREG(m.st_mode) or m.st_uid!=os.geteuid() or m.st_mode&0o077 or m.st_nlink!=1:p.error('file must be private, singly linked and operator-owned')
    for component in path.parents:
        if component.is_symlink():p.error('symlink path components are not permitted')
    return m
private(a.config);private(a.identity_file)
try:ipaddress.ip_address(a.host);host_ok=True
except ValueError:host_ok=bool(len(a.host)<=253 and all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?',s) for s in a.host.split('.')))
if not host_ok or not 1<=a.port<=65535:p.error('one explicit hostname/IP and valid port required; no scanning ranges')
if not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}',a.profile) or not a.principal or len(a.label)>128:p.error('invalid profile identity or label')
original=a.config.read_bytes();cfg=json.loads(original);db=pathlib.Path(cfg['database'])
if not db.is_absolute():p.error('configuration requires an absolute database path')
private(db);lock=pathlib.Path(str(db.resolve())+'.oip-lock');private(lock)
with lock.open('r+b') as ownership:
    try:fcntl.flock(ownership,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:p.error('Core/operator owns the database; stop it cleanly first')
    profile={'id':a.profile,'label':a.label,'principals':[a.principal],'allowed_hosts':[a.host],'allowed_ports':[a.port],'identity_file':str(a.identity_file),'agent_socket':None,'known_hosts_file':None,'aliases':{}}
    profiles=cfg.setdefault('ssh',{'profiles':[]})['profiles']
    if any(v['id']==a.profile for v in profiles):p.error('profile already exists; explicit reviewed configuration edit required, no overwrite')
    if len(profiles)>=32:p.error('profile limit reached')
    profiles.append(profile)
    if a.apply:
        if a.config.read_bytes()!=original:p.error('configuration changed; reread before applying')
        stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        backup=a.config.with_name(a.config.name+'.before-ssh-'+stamp)
        with backup.open('xb') as f:os.fchmod(f.fileno(),0o600);f.write(original);f.flush();os.fsync(f.fileno())
        pending=a.config.with_name(a.config.name+'.ssh-pending-'+stamp)
        with pending.open('xb') as f:os.fchmod(f.fileno(),0o600);f.write(json.dumps(cfg,indent=2).encode());f.flush();os.fsync(f.fileno())
        os.replace(pending,a.config)
    print(json.dumps({'applied':a.apply,'profile':a.profile,'principal':a.principal,'endpoint_explicitly_authorized':True,'configuration_before_sha256':hashlib.sha256(original).hexdigest(),'requires_restart':True,'network_contacted':False,'ssh_verified':False,'keys_exported':False,'permissions_granted':False}))

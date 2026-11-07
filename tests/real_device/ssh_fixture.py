"""Owned OpenSSH loopback fixture. No system service, sudo, real endpoint or password.
Test private keys live outside receipts. Only a public authorized key is placed under
the private user's cache, because OpenSSH StrictModes rejects /private/tmp parents.
"""
import pathlib, tempfile, subprocess, os, socket, time, json, uuid

class SshFixture:
    def __init__(self):
        self.directory=pathlib.Path(tempfile.mkdtemp(prefix='oip-owned-ssh-',dir='/private/tmp'))
        self.public_directory=pathlib.Path.home()/'Library/Caches'/('oip-owned-ssh-'+str(uuid.uuid4()))
        self.public_directory.mkdir(mode=0o700)
        self.user=subprocess.check_output(['/usr/bin/id','-un'],text=True).strip()
        assert self.user!='root','fixture must run as an unprivileged operator'
        self.key('host');self.key('client')
        public=self.public_directory/'authorized_keys';public.write_bytes((self.directory/'client.pub').read_bytes());public.chmod(0o600)
        with socket.socket() as s:s.bind(('127.0.0.1',0));self.port=s.getsockname()[1]
        self.config=self.directory/'sshd_config'
        self.config.write_text(f'''ListenAddress 127.0.0.1
Port {self.port}
HostKey {self.directory}/host
PidFile {self.directory}/sshd.pid
AuthorizedKeysFile {public}
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitRootLogin no
UsePAM no
AllowUsers {self.user}
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no
PermitUserRC no
StrictModes yes
LogLevel ERROR
''')
        self.process=None;self.start()
    def key(self,name):
        subprocess.run(['/usr/bin/ssh-keygen','-q','-t','ed25519','-N','','-f',str(self.directory/name)],check=True,stdout=subprocess.DEVNULL)
    def start(self):
        self.log=(self.directory/'sshd.log').open('a')
        self.process=subprocess.Popen(['/usr/sbin/sshd','-D','-e','-f',str(self.config)],stdout=self.log,stderr=self.log)
        for _ in range(100):
            if self.process.poll() is not None:raise RuntimeError('Owned SSH test server failed; inspect its private log')
            try:
                with socket.create_connection(('127.0.0.1',self.port),timeout=.2) as s:
                    assert s.recv(100).startswith(b'SSH-');return
            except OSError:time.sleep(.05)
        raise RuntimeError('SSH fixture did not become ready')
    def stop(self):
        if self.process and self.process.poll() is None:self.process.terminate()
        if self.process:self.process.wait(timeout=10)
        if hasattr(self,'log'):self.log.close()
    def rotate(self):
        self.stop()
        # Only keys generated and owned by this fixture. Preserve previous public identity.
        for suffix in ['', '.pub']:(self.directory/('host'+suffix)).rename(self.directory/('old-host'+suffix))
        self.key('host');self.start()
    def metadata(self):return {'directory':str(self.directory),'pid':self.process.pid,'port':self.port,'user':self.user,'loopback_only':True,'private_key_content_recorded':False}

if __name__=='__main__':
    import signal
    fixture=SshFixture();print(json.dumps(fixture.metadata()),flush=True)
    try:signal.pause()
    finally:fixture.stop()

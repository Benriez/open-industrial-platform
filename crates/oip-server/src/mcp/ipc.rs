//! Unix local transport boundary. Policies and runtime stay in the daemon.
//! This module deliberately has no SQL, collector, HTTP or device operations.
use super::{transport::BoundedTransport, McpAdapter, McpPolicy};
use oip_core::CapabilityService;
use rmcp::ServiceExt;
use serde::Deserialize;
use std::{
    fs::{File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Component, Path, PathBuf},
    sync::Arc,
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{UnixListener, UnixStream},
    task::JoinSet,
};
use tokio_util::sync::CancellationToken;
use tracing::Instrument;

const MAGIC: &[u8; 8] = b"OIPIPC1\n";
const AUTH_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_CLIENTS: usize = 32;
const SESSION_DRAIN: Duration = Duration::from_secs(8);

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IpcConfig {
    pub socket: PathBuf,
    pub clients: Vec<IpcClient>,
    #[serde(default = "default_sessions")]
    pub max_sessions: usize,
    #[serde(default)]
    pub rest_policy: Option<McpPolicy>,
}
fn default_sessions() -> usize {
    16
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IpcClient {
    pub uid: u32,
    pub credential_file: PathBuf,
    pub policy: McpPolicy,
}
struct Authority {
    uid: u32,
    // Fixed-size binary credential, never Debug/Serialize or logged.
    secret: [u8; 32],
    policy: McpPolicy,
}
fn denied() -> io::Error {
    io::Error::new(
        io::ErrorKind::PermissionDenied,
        "local IPC authority rejected",
    )
}
fn invalid() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        "invalid protected local IPC configuration/path",
    )
}
/// OS-derived identity; no environment variable, name or supplied UID is trusted.
pub fn local_uid() -> io::Result<u32> {
    Ok(UnixStream::pair()?.0.peer_cred()?.uid())
}
fn plain_path(path: &Path) -> io::Result<()> {
    if !path.is_absolute()
        || path
            .components()
            .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
    {
        return Err(invalid());
    }
    let mut p = PathBuf::new();
    for c in path.components() {
        p.push(c);
        if std::fs::symlink_metadata(&p)?.file_type().is_symlink() {
            return Err(invalid());
        }
    }
    Ok(())
}
fn socket_identity(m: &std::fs::Metadata) -> (u64, u64, i64, i64) {
    (m.dev(), m.ino(), m.ctime(), m.ctime_nsec())
}
fn same_file(a: &std::fs::Metadata, b: &std::fs::Metadata) -> bool {
    a.dev() == b.dev() && a.ino() == b.ino()
}
fn protected_file(path: &Path, uid: u32, max: u64) -> io::Result<File> {
    plain_path(path)?;
    let before = std::fs::symlink_metadata(path)?;
    if !before.is_file()
        || before.uid() != uid
        || before.mode() & 0o077 != 0
        || before.nlink() != 1
        || before.len() > max
    {
        return Err(denied());
    }
    let f = File::open(path)?;
    let after = f.metadata()?;
    if !same_file(&before, &after)
        || !after.is_file()
        || after.uid() != uid
        || after.mode() & 0o077 != 0
        || after.nlink() != 1
        || after.len() > max
    {
        return Err(denied());
    }
    Ok(f)
}
fn credential(path: &Path, uid: u32) -> io::Result<[u8; 32]> {
    let mut f = protected_file(path, uid, 32)?;
    let mut secret = [0; 32];
    f.read_exact(&mut secret)?;
    // Exact size also rejects empty/truncated files, no default credential.
    if secret == [0; 32] {
        return Err(denied());
    }
    Ok(secret)
}
fn secret_equal(a: &[u8; 32], b: &[u8; 32]) -> bool {
    // Fixed-size work, never log either value. OS owner remains trusted.
    a.iter()
        .zip(b)
        .fold(0u8, |difference, (x, y)| difference | (x ^ y))
        == 0
}
struct SocketOwnership {
    path: PathBuf,
    identity: std::fs::Metadata,
    _lock: File,
    record_committed: bool,
}
impl Drop for SocketOwnership {
    fn drop(&mut self) {
        if !self.record_committed {
            // Normal startup failure: do not strand a partially published
            // ownership record. A process crash still intentionally fails closed.
            let _ = self._lock.set_len(0);
            let _ = self._lock.sync_all();
        }
        if let Ok(m) = std::fs::symlink_metadata(&self.path) {
            if m.file_type().is_socket() && socket_identity(&m) == socket_identity(&self.identity) {
                let _ = std::fs::remove_file(&self.path);
            }
        }
    }
}
pub struct LocalIpc {
    listener: UnixListener,
    _ownership: SocketOwnership,
    authorities: Arc<Vec<Authority>>,
    max_sessions: usize,
    rest_policy: Option<McpPolicy>,
}
impl LocalIpc {
    /// Prepare before CoreRuntime starts; errors cannot orphan source workers.
    pub async fn prepare(path: &Path) -> io::Result<Self> {
        let uid = local_uid()?;
        let mut file = protected_file(path, uid, 65536)?;
        let mut bytes = Vec::new();
        Read::by_ref(&mut file)
            .take(65537)
            .read_to_end(&mut bytes)?;
        if bytes.len() > 65536 {
            return Err(invalid());
        }
        let config: IpcConfig = serde_json::from_slice(&bytes).map_err(|_| invalid())?;
        if config.clients.is_empty()
            || config.clients.len() > MAX_CLIENTS
            || !(1..=32).contains(&config.max_sessions)
        {
            return Err(invalid());
        }
        let principal_mode = config.clients.iter().all(|c| c.policy.principal.is_some());
        if config.clients.iter().any(|c| c.policy.principal.is_some()) != principal_mode {
            return Err(invalid());
        }
        if principal_mode {
            if config.rest_policy.is_some() {
                return Err(invalid());
            }
        } else {
            config
                .rest_policy
                .as_ref()
                .ok_or_else(invalid)?
                .validate()
                .map_err(|_| invalid())?;
        }
        let parent = config.socket.parent().ok_or_else(invalid)?;
        plain_path(parent)?;
        let m = std::fs::metadata(parent)?;
        // macOS UDS authorization relies on this directory, not socket chmod alone.
        if !m.is_dir()
            || m.uid() != uid
            || m.mode() & 0o077 != 0
            || config.socket.as_os_str().len() > 100
        {
            return Err(denied());
        }
        let mut authorities: Vec<Authority> = Vec::new();
        for client in config.clients {
            client.policy.validate().map_err(|_| invalid())?;
            // OIP-007 only supports the daemon OS user, not multi-user impersonation.
            if client.uid != uid {
                return Err(denied());
            }
            let secret = credential(&client.credential_file, uid)?;
            if authorities.iter().any(|a| secret_equal(&a.secret, &secret)) {
                return Err(invalid());
            }
            authorities.push(Authority {
                uid,
                secret,
                policy: client.policy,
            });
        }
        let lock_path = config.socket.with_extension("ipc-lock");
        let mut lock = match OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&lock_path)
        {
            Ok(f) => f,
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {
                let before = std::fs::symlink_metadata(&lock_path)?;
                if !before.is_file()
                    || before.uid() != uid
                    || before.mode() & 0o077 != 0
                    || before.nlink() != 1
                {
                    return Err(denied());
                }
                let f = OpenOptions::new().read(true).write(true).open(&lock_path)?;
                let after = f.metadata()?;
                if !same_file(&before, &after)
                    || !after.is_file()
                    || after.uid() != uid
                    || after.mode() & 0o077 != 0
                    || after.nlink() != 1
                    || after.len() > 256
                {
                    return Err(denied());
                }
                f
            }
            Err(e) => return Err(e),
        };
        lock.try_lock()
            .map_err(|_| io::Error::new(io::ErrorKind::AddrInUse, "IPC endpoint already owned"))?;
        // Refused connect is NOT proof of stale on macOS (full backlogs can
        // also refuse). Only recover a socket whose identity this sidecar
        // records as created by a previous cooperating daemon.
        let mut record = Vec::new();
        Read::by_ref(&mut lock).take(257).read_to_end(&mut record)?;
        let recorded: Option<(u64, u64, i64, i64)> = if record.len() <= 256 {
            serde_json::from_slice(&record).ok()
        } else {
            None
        };
        if !record.is_empty() && recorded.is_none() {
            return Err(denied());
        }
        match std::fs::symlink_metadata(&config.socket) {
            Ok(m) => {
                if !m.file_type().is_socket()
                    || m.uid() != uid
                    || recorded != Some(socket_identity(&m))
                {
                    return Err(denied());
                }
                match tokio::time::timeout(
                    Duration::from_millis(500),
                    UnixStream::connect(&config.socket),
                )
                .await
                {
                    Ok(Ok(_)) | Err(_) => {
                        return Err(io::Error::new(
                            io::ErrorKind::AddrInUse,
                            "IPC endpoint still active or unresponsive",
                        ))
                    }
                    Ok(Err(e)) if e.kind() == io::ErrorKind::ConnectionRefused => {
                        let current = std::fs::symlink_metadata(&config.socket)?;
                        if socket_identity(&current) != socket_identity(&m)
                            || !current.file_type().is_socket()
                        {
                            return Err(denied());
                        }
                        std::fs::remove_file(&config.socket)?
                    }
                    Ok(Err(e)) => return Err(e),
                }
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        let listener = UnixListener::bind(&config.socket)?;
        let mut ownership = SocketOwnership {
            identity: std::fs::symlink_metadata(&config.socket)?,
            path: config.socket.clone(),
            _lock: lock,
            record_committed: false,
        };
        std::fs::set_permissions(&config.socket, std::fs::Permissions::from_mode(0o600))?;
        ownership.identity = std::fs::symlink_metadata(&config.socket)?;
        ownership._lock.set_len(0)?;
        ownership._lock.seek(SeekFrom::Start(0))?;
        ownership._lock.write_all(
            &serde_json::to_vec(&socket_identity(&ownership.identity)).map_err(|_| invalid())?,
        )?;
        ownership._lock.sync_all()?;
        ownership.record_committed = true;
        tracing::info!(
            code = "ipc_ready",
            max_sessions = config.max_sessions,
            "protected local MCP endpoint prepared"
        );
        Ok(Self {
            listener,
            _ownership: ownership,
            authorities: Arc::new(authorities),
            max_sessions: config.max_sessions,
            rest_policy: config.rest_policy,
        })
    }
    pub fn session_limit(&self) -> usize {
        self.max_sessions
    }
    pub fn rest_context(&self) -> Option<oip_core::ExecutionContext> {
        self.rest_policy.as_ref().map(McpPolicy::execution_context)
    }
    pub fn rest_identities(&self) -> crate::identity::RestIdentities {
        crate::identity::RestIdentities::new(
            self.authorities
                .iter()
                .filter_map(|a| a.policy.principal.as_ref().map(|p| (a.secret, p.clone())))
                .collect(),
        )
    }
    pub fn validate_principals(&self, state: &crate::state::AppState) -> Result<(), &'static str> {
        for a in self.authorities.iter() {
            match &a.policy.principal {
                Some(p)
                    if state.hierarchy.as_ref().is_some_and(|h| {
                        h.plan.principals.iter().any(|x| &x.id == p && x.enabled)
                    }) => {}
                None if state.legacy_access => {}
                _ => return Err(
                    "IPC binding requires a provisioned enabled principal or explicit legacy mode",
                ),
            }
        }
        Ok(())
    }
    pub async fn run(
        self,
        service: Arc<dyn CapabilityService>,
        stop: CancellationToken,
    ) -> io::Result<()> {
        let mut sessions = JoinSet::new();
        let mut sequence = 0u64;
        let result = loop {
            tokio::select! {
                biased;
                _=stop.cancelled()=> break Ok(()),
                Some(result)=sessions.join_next(), if !sessions.is_empty()=> {
                    if result.is_err() { tracing::error!(code="ipc_session_task_failed","isolated MCP session task failed"); }
                    tracing::info!(code="ipc_session_cleanup",active_sessions=sessions.len(),"session resources joined");
                },
                result=self.listener.accept()=> {
                    let (stream, _) = match result { Ok(v)=>v,Err(e)=>break Err(e) };
                    if sessions.len()>=self.max_sessions { tracing::warn!(code="ipc_session_limit","client rejected at session limit");drop(stream);continue; }
                    sequence+=1;
                    let id=sequence;
                    let authorities=self.authorities.clone(); let service=service.clone(); let cancel=stop.child_token();
                    sessions.spawn(async move {
                        if session(stream, authorities, service, cancel).await.is_err() { tracing::warn!(code="ipc_session_rejected_or_closed","local session rejected or transport closed"); }
                    }.instrument(tracing::info_span!("mcp_session",session_id=id)));
                    tracing::info!(code="ipc_session_admitted",session_id=id,active_sessions=sessions.len(),"bounded session admitted");
                }
            }
        };
        stop.cancel();
        if tokio::time::timeout(SESSION_DRAIN, async {
            while sessions.join_next().await.is_some() {}
        })
        .await
        .is_err()
        {
            tracing::warn!(
                code = "ipc_session_drain_deadline",
                remaining = sessions.len(),
                "forcing transport tasks closed; core writer drains separately"
            );
            sessions.abort_all();
            while sessions.join_next().await.is_some() {}
        }
        result
    }
}
async fn session(
    mut stream: UnixStream,
    authorities: Arc<Vec<Authority>>,
    service: Arc<dyn CapabilityService>,
    stop: CancellationToken,
) -> io::Result<()> {
    let peer = stream.peer_cred()?;
    let policy = tokio::select! {
        _=stop.cancelled()=>return Ok(()),
        result=tokio::time::timeout(AUTH_TIMEOUT,async {
            let mut magic=[0;8];let mut secret=[0;32]; stream.read_exact(&mut magic).await?;stream.read_exact(&mut secret).await?;
            if &magic!=MAGIC { return Err(denied()); }
            let authority=authorities.iter().find(|a| a.uid==peer.uid() && secret_equal(&a.secret,&secret)).ok_or_else(denied)?;
            stream.write_all(&[1]).await?;
            Ok::<_,io::Error>(authority.policy.clone())
        })=>result.map_err(|_|denied())??,
    };
    tracing::info!(code="ipc_authorized",peer_uid=peer.uid(),peer_pid=?peer.pid(),principal=?policy.principal,actor=%policy.actor,source_scope=?policy.sources,"server-bound local authority");
    let adapter = McpAdapter::new(service, policy).map_err(|_| invalid())?;
    let (read, write) = stream.into_split();
    let transport = BoundedTransport::new(read, write).with_disconnect_token(stop.clone());
    // Discover is a bootstrap probe; legitimate clients may idle before the
    // first tool. Bound session count, not the lifetime of an authenticated idle client.
    let server = tokio::select! {biased; _=stop.cancelled()=>return Ok(()),result=adapter.serve_with_ct(transport,stop.clone())=>result.map_err(|_|denied())?};
    let cancel = server.cancellation_token();
    let waiting = server.waiting();
    tokio::pin!(waiting);
    let result = tokio::select! { result=&mut waiting=>result,_=stop.cancelled()=> {cancel.cancel();waiting.await} };
    result.map_err(|_| io::Error::other("MCP session service task failed"))?;
    Ok(())
}
/// Local transport adapter only. Authenticated bytes after the prelude are
/// relayed unchanged; the daemon's official SDK owns framing/correlation/cancel.
/// No reconnect in the middle of a session: client must create a new MCP session.
pub async fn bridge(socket: &Path, credential_file: &Path) -> io::Result<()> {
    let uid = local_uid()?;
    let parent = socket.parent().ok_or_else(invalid)?;
    plain_path(socket)?;
    let m = std::fs::metadata(parent)?;
    let s = std::fs::symlink_metadata(socket)?;
    if m.uid() != uid || m.mode() & 0o077 != 0 || !s.file_type().is_socket() || s.uid() != uid {
        return Err(denied());
    }
    let secret = credential(credential_file, uid)?;
    let mut stream = tokio::time::timeout(AUTH_TIMEOUT, UnixStream::connect(socket))
        .await
        .map_err(|_| denied())??;
    if stream.peer_cred()?.uid() != uid {
        return Err(denied());
    }
    tokio::time::timeout(AUTH_TIMEOUT, async {
        stream.write_all(MAGIC).await?;
        stream.write_all(&secret).await?;
        let mut reply = [0];
        stream.read_exact(&mut reply).await?;
        if reply != [1] {
            return Err(denied());
        }
        Ok(())
    })
    .await
    .map_err(|_| denied())??;
    let (mut read, mut write) = stream.into_split();
    let input = async {
        let result = tokio::io::copy(&mut tokio::io::stdin(), &mut write).await;
        let _ = write.shutdown().await;
        result
    };
    let output = async {
        let mut out = super::transport::protocol_stdout()?;
        let mut buffer = [0u8; 8192];
        loop {
            let n = read.read(&mut buffer).await?;
            if n == 0 {
                break;
            }
            tokio::time::timeout(Duration::from_secs(3), out.write_all(&buffer[..n]))
                .await
                .map_err(|_| {
                    io::Error::new(
                        io::ErrorKind::TimedOut,
                        "bridge stdout stalled; session closed",
                    )
                })??;
        }
        Ok::<_, io::Error>(0u64)
    };
    tokio::select! {result=input=>{result?;},result=output=>{result?;}}
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn failed_record_publication_rolls_back_owned_socket_and_partial_record() {
        let dir =
            PathBuf::from("/private/tmp").join(format!("oip8-rollback-{}", std::process::id()));
        std::fs::create_dir(&dir).unwrap();
        let path = dir.join("s");
        let lockpath = dir.join("lock");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        let mut lock = OpenOptions::new()
            .create_new(true)
            .read(true)
            .write(true)
            .open(&lockpath)
            .unwrap();
        lock.try_lock().unwrap();
        lock.write_all(b"partial-record").unwrap();
        let guard = SocketOwnership {
            identity: std::fs::metadata(&path).unwrap(),
            path: path.clone(),
            _lock: lock,
            record_committed: false,
        };
        drop(guard);
        drop(listener);
        assert!(!path.exists());
        assert_eq!(std::fs::metadata(&lockpath).unwrap().len(), 0);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}

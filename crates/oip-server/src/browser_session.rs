//! Local operator-issued, one-use pairing grants. No IPC credential enters the browser.
use oip_core::{denied, CapabilityError, ExecutionContext, PrincipalId, SourceScope};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    sync::Mutex,
    time::{Duration, Instant},
};
const GRANT_TTL: Duration = Duration::from_secs(120);
const MAX_SESSIONS: usize = 64;
const MAX_GRANTS: usize = 32;
const MAX_DEVICE_CREDENTIALS: usize = 32;
/// Bounded record of rejected codes. The counter never blocks a valid single-use
/// grant; it only keeps the rejection state itself bounded.
const MAX_FAILED: usize = 16;
pub const COOKIE: &str = "oip_session";
struct Grant {
    principal: PrincipalId,
    expires: Instant,
}
struct Session {
    principal: PrincipalId,
    csrf: String,
    last_used: Instant,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct DeviceCredential {
    principal: PrincipalId,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PersistedDeviceCredentials {
    version: u8,
    credentials: BTreeMap<String, DeviceCredential>,
}
#[derive(Default)]
struct Entries {
    grants: BTreeMap<String, Grant>,
    sessions: BTreeMap<String, Session>,
    device_credentials: BTreeMap<String, DeviceCredential>,
    failed: Vec<Instant>,
}
pub struct BrowserSessions {
    entries: Mutex<Entries>,
    credential_store: Option<PathBuf>,
}
#[derive(Clone, Serialize)]
pub struct SessionInfo {
    pub authenticated: bool,
    pub principal_id: Option<PrincipalId>,
    pub csrf_token: Option<String>,
    pub mode: &'static str,
}
pub fn random_token() -> std::io::Result<String> {
    let mut bytes = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}
fn digest(v: &str) -> String {
    format!("{:x}", Sha256::digest(v.as_bytes()))
}
fn context(p: PrincipalId) -> ExecutionContext {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    ExecutionContext {
        actor: p.to_string(),
        principal: Some(p),
        correlation_id: format!(
            "browser-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ),
        permissions: Default::default(),
        sources: SourceScope::Only(Default::default()),
    }
}
impl Entries {
    fn prune(&mut self) {
        let now = Instant::now();
        self.grants.retain(|_, g| g.expires > now);
        self.failed
            .retain(|t| now.duration_since(*t) < Duration::from_secs(60));
    }

    fn start_session(
        &mut self,
        principal: PrincipalId,
    ) -> Result<(String, SessionInfo), CapabilityError> {
        let token = random_token().map_err(|_| denied())?;
        let csrf = random_token().map_err(|_| denied())?;
        if self.sessions.len() >= MAX_SESSIONS {
            // Clients that close without logging out leave an entry behind.
            // Only a valid sign-in can reclaim an entry of the same principal.
            let oldest = self
                .sessions
                .iter()
                .filter(|(_, session)| session.principal == principal)
                .min_by_key(|(_, session)| session.last_used)
                .map(|(key, _)| key.clone())
                .ok_or_else(denied)?;
            self.sessions.remove(&oldest);
        }
        let info = SessionInfo {
            authenticated: true,
            principal_id: Some(principal.clone()),
            csrf_token: Some(csrf.clone()),
            mode: "local_operator_session",
        };
        self.sessions.insert(
            digest(&token),
            Session {
                principal,
                csrf,
                last_used: Instant::now(),
            },
        );
        Ok((token, info))
    }
}
impl BrowserSessions {
    /// Open a Core-owned store for device pairings. Browser sessions and
    /// one-use grants remain process-local and are never restored on restart.
    pub fn open(credential_store: impl Into<PathBuf>) -> io::Result<Self> {
        let credential_store = credential_store.into();
        let credentials = load_credentials(&credential_store)?;
        Ok(Self {
            entries: Mutex::new(Entries {
                device_credentials: credentials,
                ..Default::default()
            }),
            credential_store: Some(credential_store),
        })
    }

    pub fn issue(&self, principal: PrincipalId) -> Result<String, CapabilityError> {
        let mut e = self.entries.lock().map_err(|_| denied())?;
        e.prune();
        if e.grants.len() >= MAX_GRANTS {
            return Err(denied());
        }
        let code = random_token().map_err(|_| denied())?;
        e.grants.insert(
            digest(&code),
            Grant {
                principal,
                expires: Instant::now() + GRANT_TTL,
            },
        );
        Ok(code)
    }
    pub fn login(&self, code: &str) -> Result<(String, SessionInfo), CapabilityError> {
        let mut e = self.entries.lock().map_err(|_| denied())?;
        e.prune();
        if code.len() != 64 || !code.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(denied());
        }
        let key = digest(code);
        let Some(grant) = e.grants.get(&key) else {
            // Bounded rejection accounting. Earlier invalid attempts never block
            // a valid grant, and the recorded state stays capped.
            if e.failed.len() < MAX_FAILED {
                e.failed.push(Instant::now());
            }
            return Err(denied());
        };
        let principal = grant.principal.clone();
        let session = e.start_session(principal)?;
        e.grants.remove(&key);
        Ok(session)
    }
    pub fn authenticate(
        &self,
        token: &str,
        csrf: Option<&str>,
    ) -> Result<ExecutionContext, CapabilityError> {
        if token.len() != 64 {
            return Err(denied());
        }
        let mut e = self.entries.lock().map_err(|_| denied())?;
        e.prune();
        let s = e.sessions.get_mut(&digest(token)).ok_or_else(denied)?;
        if csrf.is_some_and(|c| {
            c.len() != s.csrf.len()
                || c.bytes()
                    .zip(s.csrf.bytes())
                    .fold(0u8, |d, (a, b)| d | (a ^ b))
                    != 0
        }) {
            return Err(denied());
        }
        s.last_used = Instant::now();
        Ok(context(s.principal.clone()))
    }
    /// Pair a native device credential with the currently authenticated
    /// principal. The caller stores the raw random credential in the platform
    /// keychain; only its digest is retained by the Core.
    pub fn pair_device(
        &self,
        token: &str,
        csrf: &str,
        credential: &str,
    ) -> Result<(), CapabilityError> {
        let mut e = self.entries.lock().map_err(|_| denied())?;
        e.prune();
        if credential.len() != 64 || !credential.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(denied());
        }
        let session = e.sessions.get(&digest(token)).ok_or_else(denied)?;
        if csrf.len() != session.csrf.len()
            || csrf
                .bytes()
                .zip(session.csrf.bytes())
                .fold(0u8, |d, (a, b)| d | (a ^ b))
                != 0
        {
            return Err(denied());
        }
        let principal = session.principal.clone();
        if !e.device_credentials.contains_key(&digest(credential))
            && e.device_credentials.len() >= MAX_DEVICE_CREDENTIALS
        {
            return Err(denied());
        }
        let mut credentials = e.device_credentials.clone();
        credentials.insert(digest(credential), DeviceCredential { principal });
        if let Some(path) = &self.credential_store {
            persist_credentials(path, &credentials).map_err(|_| denied())?;
        }
        e.device_credentials = credentials;
        Ok(())
    }
    /// Redeem a paired credential for a normal local browser session.
    pub fn device_login(&self, credential: &str) -> Result<(String, SessionInfo), CapabilityError> {
        let mut e = self.entries.lock().map_err(|_| denied())?;
        e.prune();
        if credential.len() != 64 || !credential.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(denied());
        }
        let Some(device) = e.device_credentials.get(&digest(credential)) else {
            if e.failed.len() < MAX_FAILED {
                e.failed.push(Instant::now());
            }
            return Err(denied());
        };
        let principal = device.principal.clone();
        e.start_session(principal)
    }
    pub fn info(&self, token: Option<&str>, legacy: bool) -> SessionInfo {
        let mut e = match self.entries.lock() {
            Ok(e) => e,
            Err(_) => {
                return SessionInfo {
                    authenticated: false,
                    principal_id: None,
                    csrf_token: None,
                    mode: "unavailable",
                };
            }
        };
        e.prune();
        if let Some(s) = token.and_then(|t| e.sessions.get_mut(&digest(t))) {
            s.last_used = Instant::now();
            return SessionInfo {
                authenticated: true,
                principal_id: Some(s.principal.clone()),
                csrf_token: Some(s.csrf.clone()),
                mode: "local_operator_session",
            };
        }
        SessionInfo {
            authenticated: false,
            principal_id: None,
            csrf_token: None,
            mode: if legacy {
                "explicit_legacy_demo"
            } else {
                "login_required"
            },
        }
    }
    pub fn logout(&self, token: &str) {
        if let Ok(mut e) = self.entries.lock() {
            e.sessions.remove(&digest(token));
        }
    }
}

impl Default for BrowserSessions {
    fn default() -> Self {
        Self {
            entries: Mutex::new(Entries::default()),
            credential_store: None,
        }
    }
}

fn load_credentials(path: &Path) -> io::Result<BTreeMap<String, DeviceCredential>> {
    let before = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(BTreeMap::new()),
        Err(error) => return Err(error),
    };
    validate_store_metadata(&before)?;
    let file = File::open(path)?;
    let after = file.metadata()?;
    validate_store_metadata(&after)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if before.ino() != after.ino() || before.dev() != after.dev() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "credential store changed while opening",
            ));
        }
    }
    let mut bytes = Vec::new();
    file.take(64 * 1024 + 1).read_to_end(&mut bytes)?;
    if bytes.len() > 64 * 1024 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "credential store too large",
        ));
    }
    let stored: PersistedDeviceCredentials = serde_json::from_slice(&bytes)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
    validate_credentials(stored.version, &stored.credentials)?;
    Ok(stored.credentials)
}

fn validate_credentials(
    version: u8,
    credentials: &BTreeMap<String, DeviceCredential>,
) -> io::Result<()> {
    if version != 1
        || credentials.len() > MAX_DEVICE_CREDENTIALS
        || credentials
            .keys()
            .any(|key| key.len() != 64 || !key.bytes().all(|byte| byte.is_ascii_hexdigit()))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid credential store",
        ));
    }
    Ok(())
}

fn persist_credentials(
    path: &Path,
    credentials: &BTreeMap<String, DeviceCredential>,
) -> io::Result<()> {
    validate_credentials(1, credentials)?;
    if let Ok(metadata) = fs::symlink_metadata(path) {
        validate_store_metadata(&metadata)?;
    }
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let filename = path.file_name().ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "invalid credential store path")
    })?;
    let temp_name = format!(
        ".{}.{}.{}.tmp",
        filename.to_string_lossy(),
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let temp = parent.join(temp_name);
    let stored = PersistedDeviceCredentials {
        version: 1,
        credentials: credentials.clone(),
    };
    let bytes = serde_json::to_vec(&stored).map_err(io::Error::other)?;
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = (|| {
        let mut file = options.open(&temp)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        fs::rename(&temp, path)?;
        File::open(parent)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

fn validate_store_metadata(metadata: &fs::Metadata) -> io::Result<()> {
    if !metadata.is_file() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "credential store must be a regular file",
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if metadata.nlink() != 1 || metadata.mode() & 0o077 != 0 {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "credential store must be private",
            ));
        }
        let output = std::process::Command::new("/usr/bin/id")
            .arg("-u")
            .output()?;
        let uid = std::str::from_utf8(&output.stdout)
            .ok()
            .and_then(|text| text.trim().parse::<u32>().ok())
            .filter(|_| output.status.success())
            .ok_or_else(|| io::Error::other("cannot establish Core user"))?;
        if metadata.uid() != uid {
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                "credential store owner mismatch",
            ));
        }
    }
    Ok(())
}
pub fn cookie(headers: &axum::http::HeaderMap) -> Option<&str> {
    headers
        .get(axum::http::header::COOKIE)?
        .to_str()
        .ok()?
        .split(';')
        .filter_map(|p| p.trim().split_once('='))
        .find(|(k, _)| *k == COOKIE)
        .map(|(_, v)| v)
}
pub fn require_origin(headers: &axum::http::HeaderMap) -> Result<(), CapabilityError> {
    let host = headers
        .get(axum::http::header::HOST)
        .and_then(|v| v.to_str().ok())
        .ok_or_else(denied)?;
    let origin = headers
        .get(axum::http::header::ORIGIN)
        .and_then(|v| v.to_str().ok())
        .ok_or_else(denied)?;
    if origin != format!("http://{host}")
        || headers
            .get("sec-fetch-site")
            .and_then(|v| v.to_str().ok())
            .is_some_and(|s| s != "same-origin" && s != "none")
    {
        return Err(denied());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn grant_is_single_use_session_is_bound_and_csrf_required() {
        let sessions = BrowserSessions::default();
        let p = PrincipalId::new("local-principal").unwrap();
        let code = sessions.issue(p.clone()).unwrap();
        let (token, info) = sessions.login(&code).unwrap();
        assert!(sessions.login(&code).is_err());
        assert_eq!(
            sessions.authenticate(&token, None).unwrap().principal,
            Some(p)
        );
        assert!(sessions.authenticate(&token, Some("forged")).is_err());
        assert_ne!(
            sessions.authenticate(&token, None).unwrap().correlation_id,
            sessions.authenticate(&token, None).unwrap().correlation_id
        );
        assert!(sessions
            .authenticate(&token, info.csrf_token.as_deref())
            .is_ok());
        sessions.logout(&token);
        assert!(sessions.authenticate(&token, None).is_err());
    }
    #[test]
    fn foreign_or_missing_origins_denied() {
        let mut h = axum::http::HeaderMap::new();
        h.insert("host", "127.0.0.1:18086".parse().unwrap());
        assert!(require_origin(&h).is_err());
        h.insert("origin", "https://foreign.invalid".parse().unwrap());
        assert!(require_origin(&h).is_err());
        h.insert("origin", "http://127.0.0.1:18086".parse().unwrap());
        assert!(require_origin(&h).is_ok());
    }
    #[test]
    fn rejected_codes_never_block_a_valid_single_use_grant() {
        let sessions = BrowserSessions::default();
        let p = PrincipalId::new("local-principal").unwrap();
        let code = sessions.issue(p.clone()).unwrap();
        let wrong = "b".repeat(64);
        for _ in 0..(MAX_FAILED + 4) {
            assert!(sessions.login(&wrong).is_err());
        }
        // The rejection accounting stays bounded and does not block the operator.
        assert!(sessions.entries.lock().unwrap().failed.len() <= MAX_FAILED);
        let (token, info) = sessions.login(&code).expect("valid grant must survive");
        assert!(sessions.authenticate(&token, None).is_ok());
        assert_eq!(info.principal_id, Some(p));
        // The grant is still single use.
        assert!(sessions.login(&code).is_err());
    }
    #[test]
    fn paired_device_credential_reissues_only_a_bounded_session_for_its_principal() {
        let sessions = BrowserSessions::default();
        let principal = PrincipalId::new("touch-id-principal").unwrap();
        let code = sessions.issue(principal.clone()).unwrap();
        let (initial_token, initial) = sessions.login(&code).unwrap();
        let credential = "ab".repeat(32);
        sessions
            .pair_device(
                &initial_token,
                initial.csrf_token.as_deref().unwrap(),
                &credential,
            )
            .unwrap();
        assert!(sessions
            .pair_device(&initial_token, "forged", &"cd".repeat(32))
            .is_err());
        sessions.logout(&initial_token);
        let (token, info) = sessions.device_login(&credential).unwrap();
        assert_eq!(info.principal_id, Some(principal.clone()));
        assert_eq!(
            sessions
                .authenticate(&token, info.csrf_token.as_deref())
                .unwrap()
                .principal,
            Some(principal)
        );
        assert!(sessions.device_login(&"ef".repeat(32)).is_err());
    }
    #[test]
    fn a_full_session_table_does_not_consume_the_grant_or_evict_other_principals() {
        let sessions = BrowserSessions::default();
        let p = PrincipalId::new("local-principal").unwrap();
        let mut tokens = Vec::new();
        for n in 0..MAX_SESSIONS {
            let other = PrincipalId::new(format!("other-{n}")).unwrap();
            let code = sessions.issue(other).unwrap();
            let (token, _) = sessions.login(&code).unwrap();
            tokens.push(token);
        }
        let spare = sessions.issue(p.clone()).unwrap();
        assert!(sessions.login(&spare).is_err());
        assert!(sessions.authenticate(&tokens[0], None).is_ok());
        sessions.logout(&tokens[0]);
        // The refused attempt did not destroy the single-use code.
        assert!(sessions.login(&spare).is_ok());
    }

    #[test]
    fn sessions_outlive_the_old_timeout_and_their_principal_can_reclaim_capacity() {
        let sessions = BrowserSessions::default();
        let principal = PrincipalId::new("local-principal").unwrap();
        let login = || {
            let code = sessions.issue(principal.clone()).unwrap();
            sessions.login(&code).unwrap().0
        };
        let idle = login();
        let old = Instant::now() - Duration::from_secs(1801);
        let age_session = || {
            sessions
                .entries
                .lock()
                .unwrap()
                .sessions
                .get_mut(&digest(&idle))
                .unwrap()
                .last_used = old;
        };
        age_session();
        assert!(sessions.info(Some(&idle), false).authenticated);
        age_session();
        assert!(sessions.authenticate(&idle, None).is_ok());
        age_session();
        let tokens: Vec<_> = (1..MAX_SESSIONS).map(|_| login()).collect();
        assert!(sessions.login(&"b".repeat(64)).is_err());
        let replacement = login();
        assert!(sessions.authenticate(&idle, None).is_err());
        assert!(sessions.authenticate(&replacement, None).is_ok());
        for token in tokens {
            assert!(sessions.authenticate(&token, None).is_ok());
        }
    }
}

//! Local operator-issued, one-use pairing grants. No IPC credential enters the browser.
use crate::{
    private_state::{load as load_store, replace as persist_store},
    security_audit::{confirm_completion, DeviceAction, DurableAudit},
    state::now_ms,
};
use oip_core::{
    denied, CapabilityError, CapabilityErrorCode, ExecutionContext, PrincipalId, SourceScope,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    io::{self, Read},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
const GRANT_TTL: Duration = Duration::from_secs(120);
const MAX_SESSIONS: usize = 64;
const MAX_SESSIONS_PER_PRINCIPAL: usize = 8;
const SESSION_IDLE_TTL: Duration = Duration::from_secs(30 * 60);
const SESSION_MAX_TTL: Duration = Duration::from_secs(12 * 60 * 60);
const MAX_GRANTS: usize = 32;
const MAX_DEVICE_CREDENTIALS: usize = 32;
const MAX_DEVICES_PER_PRINCIPAL: usize = 8;
const MAX_DEVICE_HISTORY: usize = 4096;
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
    created_at: Instant,
    last_used: Instant,
    device: Option<String>,
    pair_until: Option<Instant>,
}
impl Session {
    fn accepts_csrf(&self, csrf: &str) -> bool {
        csrf.len() == self.csrf.len()
            && csrf
                .bytes()
                .zip(self.csrf.bytes())
                .fold(0u8, |d, (a, b)| d | (a ^ b))
                == 0
    }
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
#[derive(Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct DeviceHistory {
    version: u8,
    revoked: BTreeMap<String, RevokedDevice>,
    labels: BTreeMap<String, String>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct RevokedDevice {
    principal: PrincipalId,
    revoked_at_ms: i64,
}

#[derive(Serialize)]
pub struct PairedDevice {
    id: String,
    label: Option<String>,
    current: bool,
}

#[derive(Serialize)]
pub struct DeviceRevocation {
    revoked: bool,
    pub current_session_revoked: bool,
}

#[derive(Default)]
struct Entries {
    grants: BTreeMap<String, Grant>,
    sessions: BTreeMap<String, Session>,
    device_credentials: BTreeMap<String, DeviceCredential>,
    device_history: DeviceHistory,
    failed: Vec<Instant>,
}
pub struct BrowserSessions {
    entries: Mutex<Entries>,
    credential_store: Option<PathBuf>,
    history_store: Option<PathBuf>,
    audit: Option<Arc<DurableAudit>>,
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
fn device_id(key: &str) -> String {
    digest(&format!("oip-paired-device:{key}"))
}

fn valid_token(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn persistence_error(error: io::Error) -> CapabilityError {
    tracing::warn!(kind = ?error.kind(), "could not persist device sign-in state");
    CapabilityError::new(
        CapabilityErrorCode::PersistenceUnavailable,
        "DEVICE_CREDENTIALS_UNAVAILABLE",
        "Device sign-in state could not be saved",
    )
}

fn device_not_found() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::ResourceNotFound,
        "DEVICE_CREDENTIAL_NOT_FOUND",
        "Device sign-in not found",
    )
}

fn context(p: PrincipalId) -> ExecutionContext {
    static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    ExecutionContext {
        actor: p.to_string(),
        principal: Some(p),
        correlation_id: format!(
            "browser-{}-{}-{}",
            std::process::id(),
            now_ms(),
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
        self.sessions.retain(|_, session| {
            now.duration_since(session.created_at) < SESSION_MAX_TTL
                && now.duration_since(session.last_used) < SESSION_IDLE_TTL
        });
        self.failed
            .retain(|t| now.duration_since(*t) < Duration::from_secs(60));
    }

    fn start_session(
        &mut self,
        principal: PrincipalId,
        device: Option<String>,
        pair_until: Option<Instant>,
    ) -> Result<(String, SessionInfo), CapabilityError> {
        let token = random_token().map_err(|_| denied())?;
        let csrf = random_token().map_err(|_| denied())?;
        let owned = self
            .sessions
            .iter()
            .filter(|(_, session)| session.principal == principal);
        let count = owned.clone().count();
        if count >= MAX_SESSIONS_PER_PRINCIPAL || self.sessions.len() >= MAX_SESSIONS {
            let oldest = owned
                .min_by_key(|(_, session)| session.last_used)
                .map(|(key, _)| key.clone())
                .ok_or_else(denied)?;
            self.sessions.remove(&oldest);
        }
        let now = Instant::now();
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
                created_at: now,
                last_used: now,
                device,
                pair_until,
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
        // The history is independent of the credential snapshot. An older
        // credential backup cannot reactivate a key while this history is retained.
        let mut name = credential_store.as_os_str().to_os_string();
        name.push(".revocations");
        let history_store = PathBuf::from(name);
        let mut device_history = load_history(&history_store)?;
        let mut credentials = load_credentials(&credential_store)?;
        credentials.retain(|key, _| !device_history.revoked.contains_key(key));
        device_history
            .labels
            .retain(|key, _| credentials.contains_key(key));
        Ok(Self {
            entries: Mutex::new(Entries {
                device_credentials: credentials,
                device_history,
                ..Default::default()
            }),
            credential_store: Some(credential_store),
            history_store: Some(history_store),
            audit: None,
        })
    }

    pub(crate) fn with_audit(mut self, audit: Option<Arc<DurableAudit>>) -> Self {
        self.audit = audit;
        self
    }

    fn audit_device(
        &self,
        ctx: &ExecutionContext,
        action: DeviceAction,
        id: &str,
        outcome: &str,
    ) -> Result<(), CapabilityError> {
        if let Some(audit) = &self.audit {
            audit.record_device(
                ctx.principal.as_ref().expect("bound device principal"),
                action,
                id,
                &ctx.correlation_id,
                outcome,
            )?;
        }
        Ok(())
    }

    fn audit_device_result<T>(
        &self,
        ctx: &ExecutionContext,
        action: DeviceAction,
        id: &str,
        result: Result<T, CapabilityError>,
    ) -> Result<T, CapabilityError> {
        let outcome = if result.is_ok() {
            "succeeded"
        } else {
            "failed"
        };
        confirm_completion(result, self.audit_device(ctx, action, id, outcome))
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
        if !valid_token(code) {
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
        let session = e.start_session(principal, None, Some(Instant::now() + GRANT_TTL))?;
        e.grants.remove(&key);
        Ok(session)
    }
    #[cfg(test)]
    fn authenticate(
        &self,
        token: &str,
        csrf: Option<&str>,
    ) -> Result<ExecutionContext, CapabilityError> {
        self.check_session(token, csrf, true)
    }

    pub fn check_session(
        &self,
        token: &str,
        csrf: Option<&str>,
        active: bool,
    ) -> Result<ExecutionContext, CapabilityError> {
        if token.len() != 64 {
            return Err(denied());
        }
        let mut e = self.entries.lock().map_err(|_| denied())?;
        e.prune();
        let s = e.sessions.get_mut(&digest(token)).ok_or_else(denied)?;
        if csrf.is_some_and(|value| !s.accepts_csrf(value)) {
            return Err(denied());
        }
        if active {
            s.last_used = Instant::now();
        }
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
        let mut entries = self.entries.lock().map_err(|_| denied())?;
        entries.prune();
        if !valid_token(credential) {
            return Err(denied());
        }
        let session_key = digest(token);
        let session = entries.sessions.get(&session_key).ok_or_else(denied)?;
        if !session.accepts_csrf(csrf)
            || !session
                .pair_until
                .is_some_and(|expires| expires > Instant::now())
        {
            return Err(denied());
        }
        let principal = session.principal.clone();
        let key = digest(credential);
        if entries.device_credentials.contains_key(&key)
            || entries.device_history.revoked.contains_key(&key)
        {
            return Err(denied());
        }
        if entries.device_credentials.len() >= MAX_DEVICE_CREDENTIALS
            || entries.device_credentials.len() + entries.device_history.revoked.len()
                >= MAX_DEVICE_HISTORY
            || entries
                .device_credentials
                .values()
                .filter(|d| d.principal == principal)
                .count()
                >= MAX_DEVICES_PER_PRINCIPAL
        {
            return Err(CapabilityError::new(
                CapabilityErrorCode::OperationNotSupported,
                "DEVICE_CREDENTIAL_LIMIT",
                "Device sign-in limit reached",
            ));
        }

        let ctx = context(principal.clone());
        let id = device_id(&key);
        self.audit_device(&ctx, DeviceAction::Pair, &id, "started")?;
        let result = (|| {
            let mut credentials = entries.device_credentials.clone();
            credentials.insert(key, DeviceCredential { principal });
            if let Some(path) = &self.credential_store {
                persist_credentials(path, &credentials).map_err(persistence_error)?;
            }
            entries.device_credentials = credentials;
            entries
                .sessions
                .get_mut(&session_key)
                .expect("locked session")
                .pair_until = None;
            Ok(())
        })();
        self.audit_device_result(&ctx, DeviceAction::Pair, &id, result)
    }

    pub fn paired_devices(&self, token: &str) -> Result<Vec<PairedDevice>, CapabilityError> {
        let mut entries = self.entries.lock().map_err(|_| denied())?;
        entries.prune();
        let session = entries.sessions.get(&digest(token)).ok_or_else(denied)?;
        Ok(entries
            .device_credentials
            .iter()
            .filter(|(_, device)| device.principal == session.principal)
            .map(|(key, _)| PairedDevice {
                id: device_id(key),
                label: entries.device_history.labels.get(key).cloned(),
                current: session.device.as_ref() == Some(key),
            })
            .collect())
    }

    pub fn rename_device(
        &self,
        token: &str,
        csrf: &str,
        id: &str,
        label: &str,
    ) -> Result<(), CapabilityError> {
        let mut entries = self.entries.lock().map_err(|_| denied())?;
        entries.prune();
        let session = entries.sessions.get(&digest(token)).ok_or_else(denied)?;
        if !session.accepts_csrf(csrf) {
            return Err(denied());
        }
        let label = label.trim();
        if !valid_label(label) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "DEVICE_CREDENTIAL_LABEL_INVALID",
                "Enter a device name of up to 64 characters",
            ));
        }
        let key = entries
            .device_credentials
            .iter()
            .find(|(key, device)| device.principal == session.principal && device_id(key) == id)
            .map(|(key, _)| key.clone())
            .ok_or_else(device_not_found)?;
        let ctx = context(session.principal.clone());
        self.audit_device(&ctx, DeviceAction::Rename, id, "started")?;
        let result = (|| {
            let history = &mut entries.device_history;
            let previous = history.labels.insert(key.clone(), label.to_owned());
            if let Some(path) = &self.history_store {
                if let Err(error) = persist_store(path, history) {
                    match previous {
                        Some(value) => {
                            history.labels.insert(key, value);
                        }
                        None => {
                            history.labels.remove(&key);
                        }
                    }
                    return Err(persistence_error(error));
                }
            }
            Ok(())
        })();
        self.audit_device_result(&ctx, DeviceAction::Rename, id, result)
    }

    pub fn revoke_device(
        &self,
        token: &str,
        csrf: &str,
        id: &str,
    ) -> Result<DeviceRevocation, CapabilityError> {
        let mut entries = self.entries.lock().map_err(|_| denied())?;
        entries.prune();
        let session = entries.sessions.get(&digest(token)).ok_or_else(denied)?;
        if !session.accepts_csrf(csrf) {
            return Err(denied());
        }
        let principal = session.principal.clone();
        let key = entries
            .device_credentials
            .iter()
            .filter(|(_, device)| device.principal == principal)
            .map(|(key, _)| key)
            .chain(
                entries
                    .device_history
                    .revoked
                    .iter()
                    .filter(|(_, device)| device.principal == principal)
                    .map(|(key, _)| key),
            )
            .find(|key| device_id(key) == id)
            .cloned()
            .ok_or_else(device_not_found)?;
        let current_session_revoked = session.device.as_ref() == Some(&key);
        let ctx = context(principal.clone());
        // A failing audit must never keep a compromised key active. Even in
        // that case the private revocation record captures owner and time.
        let _ = self.audit_device(&ctx, DeviceAction::Revoke, id, "started");
        entries.device_history.labels.remove(&key);
        entries
            .device_history
            .revoked
            .entry(key.clone())
            .or_insert_with(|| RevokedDevice {
                principal,
                revoked_at_ms: now_ms(),
            });
        entries.device_credentials.remove(&key);
        entries
            .sessions
            .retain(|_, session| session.device.as_ref() != Some(&key));

        let result = (|| {
            // Keep the denial in memory even on an I/O error. Confirmation
            // requires a durable tombstone. The same owner may retry.
            if let Some(path) = &self.history_store {
                persist_store(path, &entries.device_history).map_err(persistence_error)?;
            }
            if let Some(path) = &self.credential_store {
                // Remove the key from the older format for binary rollback.
                persist_credentials(path, &entries.device_credentials)
                    .map_err(persistence_error)?;
            }
            Ok(DeviceRevocation {
                revoked: true,
                current_session_revoked,
            })
        })();
        let outcome = if result.is_ok() {
            "succeeded"
        } else {
            "failed"
        };
        let _ = self.audit_device(&ctx, DeviceAction::Revoke, id, outcome);
        result
    }

    /// Redeem a paired credential for a normal local browser session.
    pub fn device_login(&self, credential: &str) -> Result<(String, SessionInfo), CapabilityError> {
        let mut entries = self.entries.lock().map_err(|_| denied())?;
        entries.prune();
        if !valid_token(credential) {
            return Err(denied());
        }
        let key = digest(credential);
        let Some(device) = entries.device_credentials.get(&key) else {
            if entries.failed.len() < MAX_FAILED {
                entries.failed.push(Instant::now());
            }
            return Err(denied());
        };
        let principal = device.principal.clone();
        entries.start_session(principal, Some(key), None)
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
        if let Some(s) = token.and_then(|t| e.sessions.get(&digest(t))) {
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
            history_store: None,
            audit: None,
        }
    }
}

fn load_credentials(path: &Path) -> io::Result<BTreeMap<String, DeviceCredential>> {
    let Some(stored) = load_store::<PersistedDeviceCredentials>(path, 64 * 1024)? else {
        return Ok(BTreeMap::new());
    };
    validate_credentials(stored.version, &stored.credentials)?;
    Ok(stored.credentials)
}

fn valid_label(label: &str) -> bool {
    !label.is_empty()
        && label.chars().count() <= 64
        && !label.chars().any(|c| {
            c.is_control() || matches!(c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
}

fn load_history(path: &Path) -> io::Result<DeviceHistory> {
    let history =
        load_store::<DeviceHistory>(path, 4 * 1024 * 1024)?.unwrap_or_else(|| DeviceHistory {
            version: 1,
            ..Default::default()
        });
    if history.version != 1
        || history.revoked.len() > MAX_DEVICE_HISTORY
        || history.labels.len() > MAX_DEVICE_CREDENTIALS
        || history
            .revoked
            .keys()
            .chain(history.labels.keys())
            .any(|key| !valid_token(key))
        || history.labels.values().any(|label| !valid_label(label))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid device history",
        ));
    }
    Ok(history)
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
    persist_store(
        path,
        &PersistedDeviceCredentials {
            version: 1,
            credentials: credentials.clone(),
        },
    )
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
    fn session_idle_and_absolute_expiry_are_independent_of_background_reads() {
        let sessions = BrowserSessions::default();
        let principal = PrincipalId::new("local-principal").unwrap();
        let login = || {
            let code = sessions.issue(principal.clone()).unwrap();
            sessions.login(&code).unwrap().0
        };

        let idle = login();
        let near_expiry = Instant::now() - SESSION_IDLE_TTL + Duration::from_secs(2);
        let age = |token: &str, created: Option<Instant>, last_use: Instant| {
            let mut entries = sessions.entries.lock().unwrap();
            let session = entries.sessions.get_mut(&digest(token)).unwrap();
            if let Some(created) = created {
                session.created_at = created;
            }
            session.last_used = last_use;
        };
        age(&idle, Some(near_expiry), near_expiry);
        assert!(sessions.info(Some(&idle), false).authenticated);
        assert!(sessions.check_session(&idle, None, false).is_ok());
        assert_eq!(
            sessions.entries.lock().unwrap().sessions[&digest(&idle)].last_used,
            near_expiry
        );
        assert!(sessions.authenticate(&idle, None).is_ok());
        assert!(sessions.entries.lock().unwrap().sessions[&digest(&idle)].last_used > near_expiry);
        age(&idle, None, Instant::now() - SESSION_IDLE_TTL);
        assert!(!sessions.info(Some(&idle), false).authenticated);
        assert!(sessions.authenticate(&idle, None).is_err());

        let active = login();
        age(
            &active,
            Some(Instant::now() - SESSION_MAX_TTL),
            Instant::now(),
        );
        assert!(sessions.authenticate(&active, None).is_err());
    }

    #[test]
    fn per_principal_capacity_protects_other_sign_ins_and_expiry_reclaims_slots() {
        let sessions = BrowserSessions::default();
        let principal = PrincipalId::new("local-principal").unwrap();
        let login = |p: &PrincipalId| {
            sessions
                .login(&sessions.issue(p.clone()).unwrap())
                .unwrap()
                .0
        };
        let oldest = login(&principal);
        let tokens: Vec<_> = (1..MAX_SESSIONS_PER_PRINCIPAL)
            .map(|_| login(&principal))
            .collect();
        let next_user = login(&PrincipalId::new("next-principal").unwrap());
        let replacement = login(&principal);
        assert_eq!(
            sessions.entries.lock().unwrap().sessions.len(),
            MAX_SESSIONS_PER_PRINCIPAL + 1
        );
        assert!(sessions.authenticate(&oldest, None).is_err());
        assert!(sessions.authenticate(&replacement, None).is_ok());
        assert!(sessions.authenticate(&next_user, None).is_ok());
        for token in tokens {
            assert!(sessions.authenticate(&token, None).is_ok());
        }

        sessions
            .entries
            .lock()
            .unwrap()
            .sessions
            .get_mut(&digest(&next_user))
            .unwrap()
            .last_used = Instant::now() - SESSION_IDLE_TTL;
        let third_user = login(&PrincipalId::new("third-principal").unwrap());
        assert!(sessions.authenticate(&next_user, None).is_err());
        assert!(sessions.authenticate(&third_user, None).is_ok());
        assert_eq!(
            sessions.entries.lock().unwrap().sessions.len(),
            MAX_SESSIONS_PER_PRINCIPAL + 1
        );
    }
}

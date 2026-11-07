//! Local operator-issued, one-use pairing grants. No IPC credential enters the browser.
use oip_core::{denied, CapabilityError, ExecutionContext, PrincipalId, SourceScope};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    io::Read,
    sync::Mutex,
    time::{Duration, Instant},
};
const SESSION_TTL: Duration = Duration::from_secs(1800);
const GRANT_TTL: Duration = Duration::from_secs(120);
const MAX_SESSIONS: usize = 64;
const MAX_GRANTS: usize = 32;
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
    expires: Instant,
}
#[derive(Default)]
struct Entries {
    grants: BTreeMap<String, Grant>,
    sessions: BTreeMap<String, Session>,
    failed: Vec<Instant>,
}
#[derive(Default)]
pub struct BrowserSessions {
    entries: Mutex<Entries>,
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
        self.sessions.retain(|_, s| s.expires > now);
        self.failed
            .retain(|t| now.duration_since(*t) < Duration::from_secs(60));
    }
}
impl BrowserSessions {
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
        // A full session table must not destroy a valid single-use grant: the
        // operator can still redeem the code once a session ended.
        if e.sessions.len() >= MAX_SESSIONS {
            return Err(denied());
        }
        let Some(grant) = e.grants.remove(&digest(code)) else {
            // Bounded rejection accounting. Earlier invalid attempts never block
            // a valid grant, and the recorded state stays capped.
            if e.failed.len() < MAX_FAILED {
                e.failed.push(Instant::now());
            }
            return Err(denied());
        };
        let token = random_token().map_err(|_| denied())?;
        let csrf = random_token().map_err(|_| denied())?;
        let info = SessionInfo {
            authenticated: true,
            principal_id: Some(grant.principal.clone()),
            csrf_token: Some(csrf.clone()),
            mode: "local_operator_session",
        };
        e.sessions.insert(
            digest(&token),
            Session {
                principal: grant.principal,
                csrf,
                expires: Instant::now() + SESSION_TTL,
            },
        );
        Ok((token, info))
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
        let s = e.sessions.get(&digest(token)).ok_or_else(denied)?;
        if csrf.is_some_and(|c| {
            c.len() != s.csrf.len()
                || c.bytes()
                    .zip(s.csrf.bytes())
                    .fold(0u8, |d, (a, b)| d | (a ^ b))
                    != 0
        }) {
            return Err(denied());
        }
        Ok(context(s.principal.clone()))
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
                }
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
    fn a_full_session_table_does_not_consume_the_grant() {
        let sessions = BrowserSessions::default();
        let p = PrincipalId::new("local-principal").unwrap();
        let mut tokens = Vec::new();
        for _ in 0..MAX_SESSIONS {
            let code = sessions.issue(p.clone()).unwrap();
            let (token, _) = sessions.login(&code).unwrap();
            tokens.push(token);
        }
        let spare = sessions.issue(p.clone()).unwrap();
        assert!(sessions.login(&spare).is_err());
        sessions.logout(&tokens[0]);
        // The refused attempt did not destroy the single-use code.
        assert!(sessions.login(&spare).is_ok());
    }
}

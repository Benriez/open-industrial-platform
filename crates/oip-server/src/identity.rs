//! Trusted local credential binding; no grants or identity from query/body values.
use oip_core::*;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};
#[derive(Clone, Default)]
pub struct RestIdentities {
    entries: Arc<Vec<([u8; 32], PrincipalId)>>,
}
impl RestIdentities {
    pub(crate) fn new(entries: Vec<([u8; 32], PrincipalId)>) -> Self {
        Self {
            entries: Arc::new(entries),
        }
    }
    pub fn authenticate(&self, header: &str) -> Result<ExecutionContext, CapabilityError> {
        let value = header.strip_prefix("Bearer ").ok_or_else(denied)?;
        if value.len() != 64 || !value.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(denied());
        }
        let mut secret = [0u8; 32];
        for (i, b) in secret.iter_mut().enumerate() {
            *b = u8::from_str_radix(&value[i * 2..i * 2 + 2], 16).map_err(|_| denied())?;
        }
        let p = self
            .entries
            .iter()
            .find(|(token, _)| token.iter().zip(secret).fold(0u8, |d, (a, b)| d | (a ^ b)) == 0)
            .map(|(_, p)| p)
            .ok_or_else(denied)?;
        static NEXT: AtomicU64 = AtomicU64::new(1);
        Ok(ExecutionContext {
            principal: Some(p.clone()),
            actor: p.to_string(),
            correlation_id: format!(
                "http-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ),
            permissions: Default::default(),
            sources: SourceScope::Only(Default::default()),
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_utf8_credentials_and_lookalikes_are_denied_without_panics() {
        let identities = RestIdentities::new(vec![([7; 32], PrincipalId::new("bound").unwrap())]);
        for header in [
            format!("Bearer {}a", "€".repeat(21)),
            "Bearer ".into(),
            format!("Bearer {}", "g".repeat(64)),
            format!("Bearer {}", "0".repeat(64)),
        ] {
            assert!(identities.authenticate(&header).is_err());
        }
        let valid = format!("Bearer {}", "07".repeat(32));
        let ctx = identities.authenticate(&valid).unwrap();
        assert_eq!(ctx.principal.unwrap().as_str(), "bound");
        assert!(ctx.permissions.is_empty());
    }
}

//! Deterministic factual findings, independent of transports and storage.
use oip_core::*;
pub const DOCUMENTED_GAP_RULE_ID: &str = "oip.documented-collection-gap";
pub const DOCUMENTED_GAP_RULE_VERSION: u32 = 1;
/// A documented gap proves that a collection interruption was recorded, not its cause.
pub fn documented_gap(gap: &CollectionGap) -> DiagnosticFinding {
    DiagnosticFinding {
        id: gap.id.clone(),
        rule_id: DOCUMENTED_GAP_RULE_ID.into(),
        rule_version: DOCUMENTED_GAP_RULE_VERSION,
        statement: "A collection gap was documented; its underlying cause is not established"
            .into(),
        evidence: vec![EvidenceReference {
            category: "gap".into(),
            id: gap.id.clone(),
            source: gap.source.clone(),
        }],
        missing_evidence: vec![
            "Independent network/service cause measurements".into(),
            "Exact interruption boundaries are not guaranteed by collection markers".into(),
        ],
        evaluated_start_ms: gap.documented_start_ms,
        evaluated_end_ms: gap.documented_end_ms,
        status: "historical_record_not_current_health".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn zero_duration_and_unknown_cause_never_become_confirmed_root_cause() {
        let g = CollectionGap {
            id: "e".repeat(64),
            source: DataSourceId::new("s").unwrap(),
            origin: OriginClass::Simulation,
            documented_start_ms: 10,
            documented_end_ms: 10,
            reason: "loss marker".into(),
        };
        let f = documented_gap(&g);
        assert_eq!(f.rule_version, 1);
        assert_eq!(f.evidence[0].id, g.id);
        assert!(!f.missing_evidence.is_empty());
        assert!(f.statement.contains("not established"));
        assert_eq!(f.evaluated_start_ms, f.evaluated_end_ms);
    }
}

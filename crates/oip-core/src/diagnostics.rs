//! Historical evidence contracts. Times are Unix milliseconds, never inferred clock alignment.
use crate::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct DiagnosticQuery {
    pub organization: Option<OrganizationId>,
    pub infrastructure: Option<InfrastructureId>,
    pub site: Option<SiteId>,
    pub source: Option<DataSourceId>,
    pub device: Option<DeviceId>,
    pub event_id: Option<String>,
    pub event_type: Option<CollectionEventKind>,
    pub metric: Option<MetricId>,
    /// Inclusive runtime event time; observation queries use receive time.
    pub start_ms: Option<i64>,
    pub end_ms: Option<i64>,
    pub limit: Option<usize>,
    pub cursor: Option<String>,
}
impl DiagnosticQuery {
    pub fn validate(&self) -> Result<usize, CapabilityError> {
        let limit = self.limit.unwrap_or(50);
        if !(1..=100).contains(&limit)
            || self
                .start_ms
                .is_some_and(|t| !(-11644473600000..=253402300799999).contains(&t))
            || self
                .end_ms
                .is_some_and(|t| !(-11644473600000..=253402300799999).contains(&t))
            || matches!((self.start_ms,self.end_ms),(Some(a),Some(b)) if a>b)
            || self.event_id.as_ref().is_some_and(|s| !evidence_key(s))
            || self.cursor.as_ref().is_some_and(|s| !evidence_key(s))
            || self.metric.as_ref().is_some_and(|m| m.as_str().len() > 128)
            || self.source.as_ref().is_some_and(|s| {
                s.as_str().len() > 128
                    || !s
                        .as_str()
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
            })
        {
            return Err(diagnostic_invalid());
        }
        Ok(limit)
    }
}
pub fn evidence_key(s: &str) -> bool {
    s.len() == 64
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
pub fn diagnostic_invalid() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::InvalidInput,
        "INVALID_DIAGNOSTIC_QUERY",
        "Invalid bounded diagnostic query or cursor",
    )
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum CollectionEventKind {
    Observation,
    ConnectionLost,
    Reconnected,
    SubscriptionError,
    DataLoss,
}
impl CollectionEventKind {
    pub fn of(e: &ClientEvent) -> Self {
        match e {
            ClientEvent::Observation(_) => Self::Observation,
            ClientEvent::ConnectionLost { .. } => Self::ConnectionLost,
            ClientEvent::Reconnected { .. } => Self::Reconnected,
            ClientEvent::SubscriptionError { .. } => Self::SubscriptionError,
            ClientEvent::DataLoss { .. } => Self::DataLoss,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct DiagnosticEvent {
    pub id: String,
    pub source: DataSourceId,
    pub origin: OriginClass,
    pub at_ms: i64,
    pub kind: CollectionEventKind,
    pub event: ClientEvent,
    pub observation_id: Option<String>,
    pub gap_id: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct HistoricalObservation {
    pub id: String,
    pub observation: ObservationEnvelope,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct CollectionGap {
    pub id: String,
    pub source: DataSourceId,
    pub origin: OriginClass,
    pub documented_start_ms: i64,
    pub documented_end_ms: i64,
    pub reason: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SourceHealthState {
    pub reachability: Reachability,
    pub connection: ConnectionHealth,
    pub service: ServiceHealth,
    pub freshness: Freshness,
    pub validity: Validity,
}
impl From<&SourceHealth> for SourceHealthState {
    fn from(s: &SourceHealth) -> Self {
        Self {
            reachability: s.reachability,
            connection: s.connection,
            service: s.service,
            freshness: s.freshness,
            validity: s.validity,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SourceHealthTransition {
    pub id: String,
    pub source: DataSourceId,
    pub at_ms: i64,
    pub previous: Option<SourceHealthState>,
    pub current: SourceHealthState,
    pub provenance: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct EvidenceReference {
    pub category: String,
    pub id: String,
    pub source: DataSourceId,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct DiagnosticFinding {
    pub id: String,
    pub rule_id: String,
    pub rule_version: u32,
    pub statement: String,
    pub evidence: Vec<EvidenceReference>,
    pub missing_evidence: Vec<String>,
    pub evaluated_start_ms: i64,
    pub evaluated_end_ms: i64,
    pub status: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "category", content = "record", rename_all = "snake_case")]
pub enum DiagnosticItem {
    Event(Box<DiagnosticEvent>),
    Observation(Box<HistoricalObservation>),
    Gap(CollectionGap),
    Health(SourceHealthTransition),
    Finding(DiagnosticFinding),
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct DiagnosticPage {
    pub items: Vec<DiagnosticItem>,
    pub truncated: bool,
    pub next_cursor: Option<String>,
    pub missing_evidence: Vec<String>,
    pub time_semantics: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct EvidenceSet {
    pub anchor: Option<DiagnosticEvent>,
    pub events: DiagnosticPage,
    pub observations: DiagnosticPage,
    pub gaps: DiagnosticPage,
    pub health: DiagnosticPage,
    pub relation: String,
    pub missing_evidence: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn queries_reject_unknown_authority_and_invalid_time_limits() {
        for json in [
            r#"{"principal":"admin"}"#,
            r#"{"severity":"critical"}"#,
            r#"{"correlation_id":"fabricated"}"#,
            r#"{"limit":"10"}"#,
            r#"{"start_ms":null,"unknown":true}"#,
        ] {
            assert!(serde_json::from_str::<DiagnosticQuery>(json).is_err());
        }
        for q in [
            DiagnosticQuery {
                start_ms: Some(i64::MAX),
                ..Default::default()
            },
            DiagnosticQuery {
                limit: Some(0),
                ..Default::default()
            },
            DiagnosticQuery {
                end_ms: Some(-11644473600001),
                ..Default::default()
            },
        ] {
            assert!(q.validate().is_err());
        }
        assert!(
            serde_json::from_str::<DiagnosticQuery>(r#"{"start_ms":null,"limit":null}"#)
                .unwrap()
                .validate()
                .is_ok()
        );
    }
}

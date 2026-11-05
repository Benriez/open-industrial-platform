use super::*;
use oip_core::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
pub(super) const HIERARCHY_SQL: &str = r#"
CREATE TABLE organizations(id TEXT PRIMARY KEY,name TEXT NOT NULL) STRICT;
CREATE TABLE infrastructures(id TEXT PRIMARY KEY,organization_id TEXT NOT NULL REFERENCES organizations(id),name TEXT NOT NULL) STRICT;
CREATE INDEX infrastructures_parent ON infrastructures(organization_id,id);
CREATE TABLE sites(id TEXT PRIMARY KEY,infrastructure_id TEXT NOT NULL REFERENCES infrastructures(id),name TEXT NOT NULL) STRICT;
CREATE INDEX sites_parent ON sites(infrastructure_id,id);
CREATE TABLE source_placements(source_id TEXT PRIMARY KEY REFERENCES source_identities(data_source_id),site_id TEXT NOT NULL REFERENCES sites(id),device_id TEXT NOT NULL UNIQUE,entity_id TEXT NOT NULL,FOREIGN KEY(source_id) REFERENCES core_sources(source_id)) STRICT;
CREATE INDEX placements_site ON source_placements(site_id,source_id);
CREATE TABLE principals(id TEXT PRIMARY KEY,name TEXT NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN(0,1))) STRICT;
CREATE TABLE read_roles(id TEXT PRIMARY KEY,name TEXT NOT NULL,permissions_json TEXT NOT NULL CHECK(json_valid(permissions_json))) STRICT;
CREATE TABLE role_bindings(principal_id TEXT NOT NULL REFERENCES principals(id),role_id TEXT NOT NULL REFERENCES read_roles(id),scope_kind TEXT NOT NULL CHECK(scope_kind IN('platform','organization','infrastructure','site','source')),scope_id TEXT NOT NULL,PRIMARY KEY(principal_id,role_id,scope_kind,scope_id)) STRICT;
CREATE TABLE provision_meta(id INTEGER PRIMARY KEY CHECK(id=1),legacy_single INTEGER NOT NULL CHECK(legacy_single IN(0,1)),revision INTEGER NOT NULL) STRICT;
CREATE TABLE provisioning_audit(sequence INTEGER PRIMARY KEY,at_ms INTEGER NOT NULL,actor TEXT NOT NULL,operation TEXT NOT NULL,plan_digest TEXT NOT NULL,outcome TEXT NOT NULL) STRICT;
CREATE TRIGGER binding_target BEFORE INSERT ON role_bindings BEGIN
 SELECT CASE WHEN NOT (NEW.scope_kind='platform' AND NEW.scope_id='' OR NEW.scope_kind='organization' AND EXISTS(SELECT 1 FROM organizations WHERE id=NEW.scope_id) OR NEW.scope_kind='infrastructure' AND EXISTS(SELECT 1 FROM infrastructures WHERE id=NEW.scope_id) OR NEW.scope_kind='site' AND EXISTS(SELECT 1 FROM sites WHERE id=NEW.scope_id) OR NEW.scope_kind='source' AND EXISTS(SELECT 1 FROM source_placements WHERE source_id=NEW.scope_id)) THEN RAISE(ABORT,'invalid scope target') END;
END;
CREATE TRIGGER immutable_infra BEFORE UPDATE OF organization_id ON infrastructures BEGIN SELECT RAISE(ABORT,'immutable hierarchy parent');END;
CREATE TRIGGER immutable_site BEFORE UPDATE OF infrastructure_id ON sites BEGIN SELECT RAISE(ABORT,'immutable hierarchy parent');END;
CREATE TRIGGER immutable_placement BEFORE UPDATE ON source_placements BEGIN SELECT RAISE(ABORT,'immutable source/device placement');END;
CREATE TRIGGER assigned_source BEFORE INSERT ON source_identities WHEN EXISTS(SELECT 1 FROM provision_meta) BEGIN SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM source_placements WHERE source_id=NEW.data_source_id) THEN RAISE(ABORT,'unassigned source') END;END;
CREATE TRIGGER assigned_device BEFORE INSERT ON device_identities WHEN EXISTS(SELECT 1 FROM provision_meta) BEGIN SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM source_placements WHERE source_id=NEW.data_source_id AND entity_id=NEW.entity_id) THEN RAISE(ABORT,'unassigned device entity') END;END;
CREATE TRIGGER immutable_source_identity BEFORE UPDATE ON source_identities BEGIN SELECT RAISE(ABORT,'immutable source identity');END;
CREATE TRIGGER immutable_device_identity BEFORE UPDATE ON device_identities BEGIN SELECT RAISE(ABORT,'immutable device identity');END;
CREATE TRIGGER immutable_binding BEFORE UPDATE ON role_bindings BEGIN SELECT RAISE(ABORT,'immutable policy binding');END;
CREATE UNIQUE INDEX events_key_source ON collection_events(event_key,data_source_id);
CREATE TABLE control_event_heads(source_id TEXT PRIMARY KEY REFERENCES source_identities(data_source_id),sequence INTEGER NOT NULL) STRICT;
CREATE TABLE control_event_index(event_key TEXT PRIMARY KEY,source_id TEXT NOT NULL,sequence INTEGER NOT NULL,UNIQUE(source_id,sequence),FOREIGN KEY(event_key,source_id) REFERENCES collection_events(event_key,data_source_id)) STRICT;
INSERT INTO control_event_index SELECT event_key,data_source_id,row_number() OVER(PARTITION BY data_source_id ORDER BY rowid) FROM collection_events WHERE kind!='observation';
INSERT INTO control_event_heads SELECT source_id,max(sequence) FROM control_event_index GROUP BY source_id;
"#;
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct LegacyAdoption {
    pub sources: BTreeSet<DataSourceId>,
    pub observations: u64,
    pub events: u64,
    pub gaps: u64,
    pub evidence_digest: String,
    /// Explicit operator attestation; schema alone cannot prove historical ownership.
    pub confirms_single_infrastructure: bool,
}
#[derive(Debug, Serialize)]
pub struct ProvisioningResult {
    pub schema_version: u32,
    pub organizations: usize,
    pub sources: usize,
    pub idempotent: bool,
    pub legacy_migrated: bool,
}
fn bad() -> StorageError {
    StorageError::Hierarchy("hierarchy/provisioning validation failed")
}
fn scope_parts(s: &AccessScope) -> (&'static str, &str) {
    match s {
        AccessScope::Platform => ("platform", ""),
        AccessScope::Organization(v) => ("organization", v.as_str()),
        AccessScope::Infrastructure(v) => ("infrastructure", v.as_str()),
        AccessScope::Site(v) => ("site", v.as_str()),
        AccessScope::Source(v) => ("source", v.as_str()),
    }
}
fn decode_scope(kind: String, id: String) -> Result<AccessScope, StorageError> {
    Ok(match kind.as_str() {
        "platform" if id.is_empty() => AccessScope::Platform,
        "organization" => AccessScope::Organization(OrganizationId::new(id).map_err(|_| bad())?),
        "infrastructure" => {
            AccessScope::Infrastructure(InfrastructureId::new(id).map_err(|_| bad())?)
        }
        "site" => AccessScope::Site(SiteId::new(id).map_err(|_| bad())?),
        "source" => AccessScope::Source(DataSourceId::new(id).map_err(|_| bad())?),
        _ => return Err(bad()),
    })
}
impl SqliteStore {
    pub fn inspect_legacy(path: &Path) -> Result<LegacyAdoption, StorageError> {
        let c = Connection::open_with_flags(path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        legacy_evidence(&c)
    }
    pub fn provision_file(
        path: &Path,
        plan: ProvisioningPlan,
        definitions: &[SourceDefinition],
        adoption: Option<&LegacyAdoption>,
    ) -> Result<ProvisioningResult, StorageError> {
        let _owner = DatabaseOwnership::acquire(path)?;
        HierarchyRegistry::new(plan.clone()).map_err(|_| bad())?;
        let c = Connection::open(path)?;
        let version: i64 = c.query_row("PRAGMA user_version", [], |r| r.get(0))?;
        if version == 1 {
            return Err(StorageError::Hierarchy(
                "schema1 requires separately verified OIP-007 upgrade before hierarchy adoption",
            ));
        }
        c.execute_batch("PRAGMA foreign_keys=ON;PRAGMA busy_timeout=5000;PRAGMA journal_mode=WAL;PRAGMA synchronous=FULL;")?;
        let mut s = Self { connection: c };
        s.migrate_to(2)?;
        s.provision(plan, definitions, adoption)
    }
    pub fn hierarchy(&self) -> Result<Option<HierarchyRegistry>, StorageError> {
        load(&self.connection)
    }
    pub fn provision(
        &mut self,
        plan: ProvisioningPlan,
        definitions: &[SourceDefinition],
        adoption: Option<&LegacyAdoption>,
    ) -> Result<ProvisioningResult, StorageError> {
        let registry = HierarchyRegistry::new(plan).map_err(|_| bad())?;
        let plan = registry.plan.clone();
        let ids: BTreeSet<_> = definitions.iter().map(|d| d.id.clone()).collect();
        if ids.len() != definitions.len()
            || ids != plan.sources.iter().map(|p| p.source_id.clone()).collect()
        {
            return Err(bad());
        }
        for s in &plan.sources {
            if !definitions.iter().any(|d| {
                d.id == s.source_id
                    && d.entity_id == s.entity_id
                    && d.origin_class == OriginClass::Simulation
            }) {
                return Err(bad());
            }
        }
        let old_version = self.schema_version()?;
        let old = if old_version >= 3 {
            self.hierarchy()?
        } else {
            None
        };
        if let Some(old) = &old {
            // Re-provision is idempotent. Existing identity/parents/roles cannot be silently changed.
            for o in &old.plan.organizations {
                if !plan.organizations.contains(o) {
                    return Err(bad());
                }
            }
            for o in &old.plan.infrastructures {
                if !plan.infrastructures.contains(o) {
                    return Err(bad());
                }
            }
            for o in &old.plan.sites {
                if !plan.sites.contains(o) {
                    return Err(bad());
                }
            }
            for o in &old.plan.sources {
                if !plan.sources.contains(o) {
                    return Err(bad());
                }
            }
            // Identities remain stable; offline operator can revoke policies/disable principals.
            for o in &old.plan.principals {
                if !plan.principals.iter().any(|p| p.id == o.id) {
                    return Err(bad());
                }
            }
            for o in &old.plan.roles {
                if !plan.roles.iter().any(|p| p.id == o.id) {
                    return Err(bad());
                }
            }
            if !old.plan.legacy_single_infrastructure && plan.legacy_single_infrastructure {
                return Err(bad());
            }
        }
        let evidence = legacy_evidence(&self.connection)?;
        let has_history =
            evidence.observations > 0 || evidence.events > 0 || !evidence.sources.is_empty();
        let legacy_migrated = old.is_none() && has_history;
        if legacy_migrated {
            let supplied = adoption.ok_or(StorageError::Hierarchy(
                "explicit legacy adoption manifest required",
            ))?;
            if !supplied.confirms_single_infrastructure
                || !plan.legacy_single_infrastructure
                || plan.organizations.len() != 1
                || plan.infrastructures.len() != 1
                || plan.sites.len() != 1
                || supplied.sources != evidence.sources
                || supplied.observations != evidence.observations
                || supplied.events != evidence.events
                || supplied.gaps != evidence.gaps
                || supplied.evidence_digest != evidence.evidence_digest
                || evidence.sources != ids
            {
                return Err(StorageError::Hierarchy(
                    "ambiguous or changed legacy evidence; adoption refused",
                ));
            }
        }
        // Validate persisted checkpoint identities as well as history before migration.
        let mut checkpoints = self
            .connection
            .prepare("SELECT source_id,entity_id,metric_id,payload_json FROM core_latest")?;
        for row in checkpoints.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
            ))
        })? {
            let (source, entity, metric, payload) = row?;
            let o: ObservationEnvelope = serde_json::from_str(&payload)?;
            oip_core::validate_observation(
                definitions
                    .iter()
                    .find(|d| d.id == o.data_source_id)
                    .ok_or_else(bad)?,
                &o,
            )
            .map_err(|_| bad())?;
            if o.data_source_id.as_str() != source
                || o.entity_id.as_str() != entity
                || o.metric_id.as_str() != metric
                || !definitions.iter().any(|d| {
                    d.id == o.data_source_id
                        && o.simulation_origin
                            .as_ref()
                            .is_some_and(|v| v.origin_id == d.simulation_origin_id)
                })
                || !plan
                    .sources
                    .iter()
                    .any(|s| s.source_id.as_str() == source && s.entity_id.as_str() == entity)
            {
                return Err(bad());
            }
        }
        drop(checkpoints);
        let mut devices = self
            .connection
            .prepare("SELECT data_source_id,entity_id FROM device_identities")?;
        for row in
            devices.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
        {
            let (source, entity) = row?;
            if !plan
                .sources
                .iter()
                .any(|s| s.source_id.as_str() == source && s.entity_id.as_str() == entity)
            {
                return Err(bad());
            }
        }
        drop(devices);
        let mut events = self
            .connection
            .prepare("SELECT data_source_id,payload_json FROM collection_events")?;
        for row in events.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
            let (source, payload) = row?;
            let event: ClientEvent = serde_json::from_str(&payload)?;
            if let ClientEvent::Observation(o) = event {
                oip_core::validate_observation(
                    definitions
                        .iter()
                        .find(|d| d.id == o.data_source_id)
                        .ok_or_else(bad)?,
                    &o,
                )
                .map_err(|_| bad())?;
                if o.data_source_id.as_str() != source
                    || !definitions.iter().any(|d| {
                        d.id == o.data_source_id
                            && o.simulation_origin
                                .as_ref()
                                .is_some_and(|v| v.origin_id == d.simulation_origin_id)
                    })
                    || !plan
                        .sources
                        .iter()
                        .any(|s| s.source_id.as_str() == source && s.entity_id == o.entity_id)
                {
                    return Err(bad());
                }
            }
        }
        drop(events);
        let invalid:i64=self.connection.query_row("SELECT (SELECT count(*) FROM collection_events e LEFT JOIN observations o ON e.observation_key=o.observation_key LEFT JOIN data_gaps g ON e.gap_key=g.gap_key WHERE e.origin_class!='simulation' OR (e.observation_key IS NOT NULL AND (o.data_source_id!=e.data_source_id OR o.origin_class!=e.origin_class)) OR (e.gap_key IS NOT NULL AND (g.data_source_id!=e.data_source_id OR g.origin_class!=e.origin_class))) + (SELECT count(*) FROM data_gaps WHERE origin_class!='simulation' OR started_at_ms<0 OR ended_at_ms<started_at_ms)",[],|r|r.get(0))?;
        if invalid != 0 {
            return Err(bad());
        }

        // Never rebind existing persisted definitions or foreign source/entity payloads.
        let saved = <Self as CoreRepository>::definitions(self).map_err(|_| bad())?;
        for d in &saved {
            if !definitions.contains(d) {
                return Err(bad());
            }
        }
        for s in &evidence.sources {
            if !ids.contains(s) {
                return Err(bad());
            }
        }
        let mut q = self.connection.prepare(
            "SELECT entity_id,data_source_id,payload_json,origin_class FROM observations",
        )?;
        for row in q.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
            ))
        })? {
            let (entity, source, payload, origin) = row?;
            let o: ObservationEnvelope = serde_json::from_str(&payload)?;
            oip_core::validate_observation(
                definitions
                    .iter()
                    .find(|d| d.id == o.data_source_id)
                    .ok_or_else(bad)?,
                &o,
            )
            .map_err(|_| bad())?;
            if origin != "simulation"
                || o.entity_id.as_str() != entity
                || o.data_source_id.as_str() != source
                || !definitions.iter().any(|d| {
                    d.id == o.data_source_id
                        && o.simulation_origin
                            .as_ref()
                            .is_some_and(|v| v.origin_id == d.simulation_origin_id)
                })
                || !plan
                    .sources
                    .iter()
                    .any(|p| p.source_id.as_str() == source && p.entity_id.as_str() == entity)
            {
                return Err(bad());
            }
        }
        drop(q);
        let idempotent = old.as_ref().is_some_and(|x| x.plan == plan);
        let digest = content_hash(&serde_json::to_vec(&plan)?);
        let tx = self.write_transaction()?;
        tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
        if old_version < 3 {
            tx.execute_batch(HIERARCHY_SQL)?;
            tx.execute(
                "INSERT INTO schema_migrations VALUES(3,?1,?2)",
                params![
                    "hierarchy_identity_control_sequences",
                    content_hash(HIERARCHY_SQL.as_bytes())
                ],
            )?;
            tx.execute_batch("PRAGMA user_version=3;")?;
        }
        for o in &plan.organizations {
            tx.execute(
                "INSERT INTO organizations VALUES(?1,?2) ON CONFLICT DO NOTHING",
                params![o.id.as_str(), o.name],
            )?;
        }
        for o in &plan.infrastructures {
            tx.execute(
                "INSERT INTO infrastructures VALUES(?1,?2,?3) ON CONFLICT DO NOTHING",
                params![o.id.as_str(), o.organization_id.as_str(), o.name],
            )?;
        }
        for o in &plan.sites {
            tx.execute(
                "INSERT INTO sites VALUES(?1,?2,?3) ON CONFLICT DO NOTHING",
                params![o.id.as_str(), o.infrastructure_id.as_str(), o.name],
            )?;
        }
        for def in definitions {
            tx.execute(
                "INSERT INTO core_sources VALUES(?1,?2) ON CONFLICT DO NOTHING",
                params![def.id.as_str(), serde_json::to_string(def)?],
            )?;
            // Existing assignments stay immutable. New-source placement must be inserted
            // before source identity guard is active; deferred checking is transactional.
        }
        for s in &plan.sources {
            tx.execute(
                "INSERT INTO source_placements VALUES(?1,?2,?3,?4) ON CONFLICT DO NOTHING",
                params![
                    s.source_id.as_str(),
                    s.site_id.as_str(),
                    s.device_id.as_str(),
                    s.entity_id.as_str()
                ],
            )?;
        }
        for def in definitions {
            tx.execute(
                "INSERT INTO source_identities VALUES(?1,'simulation') ON CONFLICT DO NOTHING",
                [def.id.as_str()],
            )?;
        }
        for p in &plan.principals {
            tx.execute(
                "INSERT INTO principals VALUES(?1,?2,?3) ON CONFLICT(id) DO UPDATE SET name=excluded.name,enabled=excluded.enabled",
                params![p.id.as_str(), p.name, p.enabled],
            )?;
        }
        for p in &plan.roles {
            tx.execute(
                "INSERT INTO read_roles VALUES(?1,?2,?3) ON CONFLICT(id) DO UPDATE SET name=excluded.name,permissions_json=excluded.permissions_json",
                params![
                    p.id.as_str(),
                    p.name,
                    serde_json::to_string(&p.permissions)?
                ],
            )?;
        }
        tx.execute("DELETE FROM role_bindings", [])?;
        for b in &plan.bindings {
            let (k, id) = scope_parts(&b.scope);
            tx.execute(
                "INSERT INTO role_bindings VALUES(?1,?2,?3,?4) ON CONFLICT DO NOTHING",
                params![b.principal_id.as_str(), b.role_id.as_str(), k, id],
            )?;
        }
        tx.execute("INSERT INTO provision_meta VALUES(1,?1,1) ON CONFLICT(id) DO UPDATE SET legacy_single=excluded.legacy_single,revision=revision+?2",params![plan.legacy_single_infrastructure,!idempotent])?;
        if tx
            .prepare("PRAGMA foreign_key_check")?
            .query([])?
            .next()?
            .is_some()
        {
            return Err(bad());
        }
        if load(&tx)?.ok_or_else(bad)?.plan != registry.plan {
            return Err(bad());
        }
        let after = legacy_evidence(&tx)?;
        if evidence.observations != after.observations
            || evidence.events != after.events
            || evidence.gaps != after.gaps
            || evidence.evidence_digest != after.evidence_digest
        {
            return Err(bad());
        }
        tx.execute("INSERT INTO provisioning_audit(at_ms,actor,operation,plan_digest,outcome) VALUES(?1,'local-offline-operator','provision_read_hierarchy',?2,?3)",params![Timestamp::now().map_err(|_|bad())?.as_unix_millis(),digest,if idempotent{"idempotent"}else{"committed"}])?;
        tx.commit()?;
        Ok(ProvisioningResult {
            schema_version: 3,
            organizations: plan.organizations.len(),
            sources: ids.len(),
            idempotent,
            legacy_migrated,
        })
    }
    pub fn query_plans(&self) -> Result<Vec<String>, StorageError> {
        let mut result = Vec::new();
        for sql in ["EXPLAIN QUERY PLAN SELECT id FROM infrastructures WHERE organization_id='x' ORDER BY id LIMIT 100","EXPLAIN QUERY PLAN SELECT source_id FROM source_placements WHERE site_id='x'","EXPLAIN QUERY PLAN SELECT payload_json FROM observations WHERE entity_id='x' AND data_source_id='y' AND metric_id='z' ORDER BY source_ts_ms DESC LIMIT 1","EXPLAIN QUERY PLAN SELECT event_key FROM control_event_index WHERE source_id='x' AND sequence>10 LIMIT 100","EXPLAIN QUERY PLAN SELECT source_id FROM source_placements WHERE device_id='x'"] {
   let mut q=self.connection.prepare(sql)?;for r in q.query_map([],|r|r.get::<_,String>(3))?{result.push(r?);}
  }
        Ok(result)
    }
}
fn legacy_evidence(c: &Connection) -> Result<LegacyAdoption, StorageError> {
    let mut sources = BTreeSet::new();
    let mut q = c.prepare(
        "SELECT data_source_id FROM source_identities UNION SELECT source_id FROM core_sources",
    )?;
    for r in q.query_map([], |r| r.get::<_, String>(0))? {
        sources.insert(DataSourceId::new(r?).map_err(|_| bad())?);
    }
    let mut hash = Sha256::new();
    for sql in ["SELECT observation_key||payload_json||duplicate_count FROM observations ORDER BY observation_key","SELECT event_key||payload_json||duplicate_count FROM collection_events ORDER BY event_key","SELECT gap_key||data_source_id||started_at_ms||ended_at_ms||reason||duplicate_count FROM data_gaps ORDER BY gap_key","SELECT source_id||entity_id||metric_id||payload_json FROM core_latest ORDER BY source_id,entity_id,metric_id"] {
  let mut q=c.prepare(sql)?;for row in q.query_map([],|r|r.get::<_,String>(0))?{let b=row?;hash.update((b.len()as u64).to_be_bytes());hash.update(b.as_bytes());}
 }
    if c.prepare("PRAGMA foreign_key_check")?
        .query([])?
        .next()?
        .is_some()
    {
        return Err(bad());
    }
    let mut q =
        c.prepare("SELECT origin_class FROM source_identities WHERE origin_class!='simulation'")?;
    if q.query([])?.next()?.is_some() {
        return Err(bad());
    }
    let count = |table: &str| -> Result<u64, StorageError> {
        Ok(
            c.query_row(&format!("SELECT count(*) FROM {table}"), [], |r| {
                r.get::<_, i64>(0)
            })? as u64,
        )
    };
    Ok(LegacyAdoption {
        sources,
        observations: count("observations")?,
        events: count("collection_events")?,
        gaps: count("data_gaps")?,
        evidence_digest: format!("{:x}", hash.finalize()),
        confirms_single_infrastructure: false,
    })
}
fn load(c: &Connection) -> Result<Option<HierarchyRegistry>, StorageError> {
    let exists: bool = c.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='provision_meta')",
        [],
        |r| r.get(0),
    )?;
    if !exists {
        return Ok(None);
    }
    let legacy: Option<bool> = c
        .query_row(
            "SELECT legacy_single FROM provision_meta WHERE id=1",
            [],
            |r| r.get(0),
        )
        .optional()?;
    let Some(legacy) = legacy else {
        return Ok(None);
    };
    fn rows<T>(
        c: &Connection,
        sql: &str,
        limit: usize,
        mut map: impl FnMut(&rusqlite::Row<'_>) -> Result<T, StorageError>,
    ) -> Result<Vec<T>, StorageError> {
        let mut q = c.prepare(sql)?;
        let mut rows = q.query([])?;
        let mut result = Vec::new();
        while let Some(r) = rows.next()? {
            if result.len() >= limit {
                return Err(bad());
            }
            result.push(map(r)?);
        }
        Ok(result)
    }
    let organizations = rows(
        c,
        "SELECT id,name FROM organizations ORDER BY id",
        64,
        |r| {
            Ok(Organization {
                id: OrganizationId::new(r.get::<_, String>(0)?).map_err(|_| bad())?,
                name: r.get(1)?,
            })
        },
    )?;
    let infrastructures = rows(
        c,
        "SELECT id,organization_id,name FROM infrastructures ORDER BY id",
        128,
        |r| {
            Ok(Infrastructure {
                id: InfrastructureId::new(r.get::<_, String>(0)?).map_err(|_| bad())?,
                organization_id: OrganizationId::new(r.get::<_, String>(1)?).map_err(|_| bad())?,
                name: r.get(2)?,
            })
        },
    )?;
    let sites = rows(
        c,
        "SELECT id,infrastructure_id,name FROM sites ORDER BY id",
        256,
        |r| {
            Ok(Site {
                id: SiteId::new(r.get::<_, String>(0)?).map_err(|_| bad())?,
                infrastructure_id: InfrastructureId::new(r.get::<_, String>(1)?)
                    .map_err(|_| bad())?,
                name: r.get(2)?,
            })
        },
    )?;
    let sources = rows(
        c,
        "SELECT source_id,site_id,device_id,entity_id FROM source_placements ORDER BY source_id",
        32,
        |r| {
            Ok(SourcePlacement {
                source_id: DataSourceId::new(r.get::<_, String>(0)?).map_err(|_| bad())?,
                site_id: SiteId::new(r.get::<_, String>(1)?).map_err(|_| bad())?,
                device_id: DeviceId::new(r.get::<_, String>(2)?).map_err(|_| bad())?,
                entity_id: EntityId::new(r.get::<_, String>(3)?).map_err(|_| bad())?,
            })
        },
    )?;
    let principals = rows(
        c,
        "SELECT id,name,enabled FROM principals ORDER BY id",
        64,
        |r| {
            Ok(Principal {
                id: PrincipalId::new(r.get::<_, String>(0)?).map_err(|_| bad())?,
                name: r.get(1)?,
                enabled: r.get(2)?,
            })
        },
    )?;
    let roles = rows(
        c,
        "SELECT id,name,permissions_json FROM read_roles ORDER BY id",
        64,
        |r| {
            Ok(ReadRole {
                id: RoleId::new(r.get::<_, String>(0)?).map_err(|_| bad())?,
                name: r.get(1)?,
                permissions: serde_json::from_str(&r.get::<_, String>(2)?)?,
            })
        },
    )?;
    let bindings=rows(c,"SELECT principal_id,role_id,scope_kind,scope_id FROM role_bindings ORDER BY principal_id,role_id,scope_kind,scope_id",512,|r|Ok(RoleBinding{principal_id:PrincipalId::new(r.get::<_,String>(0)?).map_err(|_|bad())?,role_id:RoleId::new(r.get::<_,String>(1)?).map_err(|_|bad())?,scope:decode_scope(r.get(2)?,r.get(3)?)?}))?;
    Ok(Some(
        HierarchyRegistry::new(ProvisioningPlan {
            organizations,
            infrastructures,
            sites,
            sources,
            principals,
            roles,
            bindings,
            legacy_single_infrastructure: legacy,
        })
        .map_err(|_| bad())?,
    ))
}
#[cfg(test)]
mod tests {
    use super::*;
    fn plan() -> ProvisioningPlan {
        serde_json::from_str(include_str!(
            "../../../examples/multi-infrastructure-plan.json"
        ))
        .unwrap()
    }
    fn definitions() -> Vec<SourceDefinition> {
        plan()
            .sources
            .iter()
            .map(|s| SourceDefinition {
                id: s.source_id.clone(),
                name: s.source_id.to_string(),
                entity_id: s.entity_id.clone(),
                binding: format!("local:{}", s.source_id),
                origin_class: OriginClass::Simulation,
                simulation_origin_id: "oip-local-simulation-v1".into(),
                metrics: [(MetricId::new("temperature").unwrap(), ValueKind::Float)].into(),
                required_metrics: [MetricId::new("temperature").unwrap()].into(),
            })
            .collect()
    }
    fn legacy() -> SqliteStore {
        let mut s = SqliteStore {
            connection: Connection::open_in_memory().unwrap(),
        };
        s.connection
            .execute_batch("PRAGMA foreign_keys=ON")
            .unwrap();
        s.migrate_to(2).unwrap();
        s
    }
    fn legacy_plan() -> ProvisioningPlan {
        let mut p = plan();
        p.organizations.truncate(1);
        p.infrastructures.truncate(1);
        p.sites.truncate(1);
        p.sources.retain(|s| s.source_id.as_str() == "source-a");
        p.principals.truncate(1);
        p.roles.truncate(1);
        p.bindings.retain(|b| b.principal_id == p.principals[0].id);
        p.legacy_single_infrastructure = true;
        p
    }
    fn single_definition() -> SourceDefinition {
        definitions().remove(0)
    }
    #[test]
    fn provisioning_is_atomic_idempotent_additive_and_parent_immutable() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        let result = db.provision(plan(), &definitions(), None).unwrap();
        assert!(!result.idempotent);
        assert!(
            db.provision(plan(), &definitions(), None)
                .unwrap()
                .idempotent
        );
        let mut bad_plan = plan();
        bad_plan.sites[0].infrastructure_id = InfrastructureId::new("infra-b1").unwrap();
        assert!(db.provision(bad_plan, &definitions(), None).is_err());
        assert_eq!(
            db.hierarchy().unwrap().unwrap().plan,
            HierarchyRegistry::new(plan()).unwrap().plan
        );
        assert!(db
            .connection
            .execute(
                "UPDATE sites SET infrastructure_id='infra-b1' WHERE id='site-a1'",
                []
            )
            .is_err());
        assert!(db
            .connection
            .execute(
                "INSERT INTO role_bindings VALUES('reader-org-a','reader','source','absent')",
                []
            )
            .is_err());
        let plans = db.query_plans().unwrap();
        assert!(plans.iter().all(|p| p.contains("INDEX")), "{plans:?}");
        assert_eq!(
            db.connection
                .query_row("PRAGMA integrity_check", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "ok"
        );
    }
    #[test]
    fn legacy_adoption_requires_evidence_and_preserves_history_and_keys() {
        let mut db = legacy();
        let def = single_definition();
        CoreRepository::register(&mut db, &def).unwrap();
        let o = ObservationEnvelope {
            data_source_id: def.id.clone(),
            ..crate::tests::observation(1000)
        };
        db.ingest_observation(&o).unwrap();
        let before = legacy_evidence(&db.connection).unwrap();
        assert!(db
            .provision(legacy_plan(), std::slice::from_ref(&def), None)
            .is_err());
        assert_eq!(db.schema_version().unwrap(), 2);
        let mut adoption = before.clone();
        adoption.confirms_single_infrastructure = true;
        assert!(
            db.provision(legacy_plan(), std::slice::from_ref(&def), Some(&adoption))
                .unwrap()
                .legacy_migrated
        );
        let after = legacy_evidence(&db.connection).unwrap();
        assert_eq!(before.evidence_digest, after.evidence_digest);
        assert_eq!(after.observations, 1);
        assert_eq!(db.schema_version().unwrap(), 3);
        // Explicit one-way expansion keeps old history/parents. No fallback back to legacy.
        db.provision(plan(), &definitions(), None).unwrap();
        assert!(
            !db.hierarchy()
                .unwrap()
                .unwrap()
                .plan
                .legacy_single_infrastructure
        );
        assert_eq!(db.observation_count().unwrap(), 1);
        assert!(db
            .provision(legacy_plan(), std::slice::from_ref(&def), None)
            .is_err());
    }
    #[test]
    fn corrupt_legacy_entities_or_foreign_references_do_not_activate_schema3() {
        let mut db = legacy();
        let def = single_definition();
        CoreRepository::register(&mut db, &def).unwrap();
        db.connection
            .execute(
                "INSERT INTO source_identities VALUES('source-a','simulation')",
                [],
            )
            .unwrap();
        db.connection
            .execute(
                "INSERT INTO device_identities VALUES('foreign-entity','source-a')",
                [],
            )
            .unwrap();
        let mut evidence = legacy_evidence(&db.connection).unwrap();
        evidence.confirms_single_infrastructure = true;
        assert!(db
            .provision(legacy_plan(), &[def], Some(&evidence))
            .is_err());
        assert_eq!(db.schema_version().unwrap(), 2);
        assert!(!db
            .connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='organizations')",
                [],
                |r| r.get::<_, bool>(0)
            )
            .unwrap());
    }
    #[test]
    fn event_only_legacy_cannot_be_automatically_adopted() {
        let mut db = legacy();
        db.connection
            .execute(
                "INSERT INTO source_identities VALUES('source-a','simulation')",
                [],
            )
            .unwrap();
        assert!(db.migrate().is_err());
        assert_eq!(db.schema_version().unwrap(), 2);
    }
    #[test]
    fn forced_schema3_failure_rolls_back_all_ddl_and_rows() {
        let mut db = legacy();
        db.connection
            .execute_batch("CREATE TABLE organizations(id TEXT PRIMARY KEY)")
            .unwrap();
        assert!(db.provision(plan(), &definitions(), None).is_err());
        assert_eq!(db.schema_version().unwrap(), 2);
        assert!(!db
            .connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='source_placements')",
                [],
                |r| r.get::<_, bool>(0)
            )
            .unwrap());
    }
    #[test]
    fn legacy_corruption_of_origins_source_keys_and_event_links_is_rejected_atomically() {
        for case in 0..4 {
            let mut db = legacy();
            let defs = definitions();
            for d in &defs {
                CoreRepository::register(&mut db, d).unwrap();
            }
            for id in ["source-a", "source-b"] {
                let mut o = crate::tests::observation(1000);
                o.data_source_id = DataSourceId::new(id).unwrap();
                db.ingest_event(
                    &EventContext::for_observation(&o),
                    &ClientEvent::Observation(Box::new(o)),
                )
                .unwrap();
            }
            match case {
                0 => {
                    db.connection.execute("UPDATE observations SET origin_class='external' WHERE data_source_id='source-a'",[]).unwrap();
                }
                1 => {
                    db.connection.execute("UPDATE core_sources SET payload_json=(SELECT payload_json FROM core_sources WHERE source_id='source-b') WHERE source_id='source-a'",[]).unwrap();
                }
                2 => {
                    db.connection.execute("UPDATE collection_events SET observation_key=(SELECT observation_key FROM observations WHERE data_source_id='source-b') WHERE data_source_id='source-a'",[]).unwrap();
                }
                _ => {
                    let mut o = crate::tests::observation(1000);
                    o.data_source_id = DataSourceId::new("source-a").unwrap();
                    o.simulation_origin = None;
                    db.connection
                        .execute(
                            "INSERT INTO core_latest VALUES('source-a','M-01','temperature',?1)",
                            [serde_json::to_string(&o).unwrap()],
                        )
                        .unwrap();
                }
            }
            let mut evidence = legacy_evidence(&db.connection).unwrap();
            evidence.confirms_single_infrastructure = true;
            let mut p = plan();
            p.organizations.truncate(1);
            p.infrastructures.truncate(1);
            p.sites.truncate(1);
            for s in &mut p.sources {
                s.site_id = SiteId::new("site-a1").unwrap();
            }
            p.principals.truncate(1);
            p.bindings.truncate(1);
            p.legacy_single_infrastructure = true;
            assert!(
                db.provision(p, &defs, Some(&evidence)).is_err(),
                "case {case}"
            );
            assert_eq!(db.schema_version().unwrap(), 2);
            assert!(!db
                .connection
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='source_placements')",
                    [],
                    |r| r.get::<_, bool>(0)
                )
                .unwrap());
        }
    }
    #[test]
    fn offline_policy_replacement_revokes_access_without_rebinding_data() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        db.provision(plan(), &definitions(), None).unwrap();
        let principal = PrincipalId::new("reader-org-a").unwrap();
        let mut updated = plan();
        updated.bindings.retain(|b| b.principal_id != principal);
        db.provision(updated, &definitions(), None).unwrap();
        let h = db.hierarchy().unwrap().unwrap();
        assert!(h
            .allowed_sources(&principal, CapabilityId::SourcesRead)
            .is_empty());
        assert_eq!(h.plan.sources.len(), 4);
    }
    #[test]
    fn foreign_source_event_volume_does_not_change_local_sequence_or_evict_own_cache() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        let b = EventContext {
            data_source_id: DataSourceId::new("b").unwrap(),
            origin_class: OriginClass::Simulation,
        };
        db.commit(
            &b,
            &ClientEvent::SubscriptionError {
                at: Timestamp::from_unix_millis(1000),
                reason: "own".into(),
            },
            None,
        )
        .unwrap();
        let a = EventContext {
            data_source_id: DataSourceId::new("a").unwrap(),
            origin_class: OriginClass::Simulation,
        };
        for n in 0..150 {
            db.commit(
                &a,
                &ClientEvent::SubscriptionError {
                    at: Timestamp::from_unix_millis(2000 + n),
                    reason: "foreign".into(),
                },
                None,
            )
            .unwrap();
        }
        let events = db.recent_events(100).unwrap();
        let own = events
            .iter()
            .filter(|e| e.context.data_source_id == b.data_source_id)
            .collect::<Vec<_>>();
        assert_eq!(own.len(), 1);
        assert_eq!(own[0].sequence, 1);
        assert_eq!(
            events
                .iter()
                .filter(|e| e.context.data_source_id == a.data_source_id)
                .count(),
            100
        );
    }
    #[test]
    fn missing_migration_ledger_is_never_repaired_over_an_existing_database() {
        for replacement in [None, Some(0), Some(-1)] {
            let mut db = legacy();
            match replacement {
                None => {
                    db.connection
                        .execute("DELETE FROM schema_migrations WHERE version=1", [])
                        .unwrap();
                }
                Some(v) => {
                    db.connection
                        .execute(
                            "UPDATE schema_migrations SET version=?1 WHERE version=1",
                            [v],
                        )
                        .unwrap();
                }
            }
            let schema_before: Vec<String> = db
                .connection
                .prepare("SELECT sql FROM sqlite_master ORDER BY name")
                .unwrap()
                .query_map([], |r| r.get::<_, Option<String>>(0))
                .unwrap()
                .map(|r| r.unwrap().unwrap_or_default())
                .collect();
            let count_before = db
                .connection
                .query_row("SELECT count(*) FROM schema_migrations", [], |r| {
                    r.get::<_, i64>(0)
                })
                .unwrap();
            assert!(db.migrate_to(2).is_err(), "replacement {replacement:?}");
            assert_eq!(db.pragma_version().unwrap(), 2);
            assert_eq!(
                db.connection
                    .query_row("SELECT count(*) FROM schema_migrations", [], |r| r
                        .get::<_, i64>(0))
                    .unwrap(),
                count_before
            );
            let schema_after: Vec<String> = db
                .connection
                .prepare("SELECT sql FROM sqlite_master ORDER BY name")
                .unwrap()
                .query_map([], |r| r.get::<_, Option<String>>(0))
                .unwrap()
                .map(|r| r.unwrap().unwrap_or_default())
                .collect();
            assert_eq!(schema_before, schema_after);
        }
    }
}

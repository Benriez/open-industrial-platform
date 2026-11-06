//! Exclusive local configuration administration. Runtime never opens a second writer.
use super::*;
use oip_core::*;
pub(super) const SETTINGS_SQL: &str = r#"
CREATE TABLE setting_scopes(
 scope_key TEXT PRIMARY KEY,
 organization_id TEXT REFERENCES organizations(id),
 infrastructure_id TEXT REFERENCES infrastructures(id),
 site_id TEXT REFERENCES sites(id),
 source_id TEXT REFERENCES source_placements(source_id),
 CHECK((organization_id IS NOT NULL)+(infrastructure_id IS NOT NULL)+(site_id IS NOT NULL)+(source_id IS NOT NULL)<=1),
 CHECK(scope_key=CASE
 WHEN organization_id IS NOT NULL THEN json_object('kind','organization','id',organization_id)
 WHEN infrastructure_id IS NOT NULL THEN json_object('kind','infrastructure','id',infrastructure_id)
 WHEN site_id IS NOT NULL THEN json_object('kind','site','id',site_id)
 WHEN source_id IS NOT NULL THEN json_object('kind','source','id',source_id)
 ELSE json_object('kind','platform') END)
) STRICT;
CREATE TRIGGER immutable_setting_scope BEFORE UPDATE ON setting_scopes BEGIN SELECT RAISE(ABORT,'immutable settings target'); END;
CREATE TABLE settings(
 scope_key TEXT NOT NULL REFERENCES setting_scopes(scope_key),
 setting_key TEXT NOT NULL CHECK(setting_key IN('instance_name','instance_description','history_page_size')),
 value_json TEXT NOT NULL CHECK(json_valid(value_json) AND length(value_json)<=1024),
 revision INTEGER NOT NULL CHECK(revision>0),
 created_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL,
 actor TEXT NOT NULL REFERENCES principals(id),
 PRIMARY KEY(scope_key,setting_key)
) STRICT;
CREATE TABLE settings_audit(
 sequence INTEGER PRIMARY KEY, at_ms INTEGER NOT NULL,
 principal_id TEXT NOT NULL REFERENCES principals(id),
 operator_authority TEXT NOT NULL,
 scope_key TEXT NOT NULL REFERENCES setting_scopes(scope_key),
 setting_key TEXT NOT NULL, revision INTEGER NOT NULL,
 outcome TEXT NOT NULL CHECK(outcome='persisted_requires_restart')
) STRICT;
"#;
fn bad() -> StorageError {
    StorageError::Hierarchy("invalid typed settings or authorization")
}
fn scope_key(scope: &AccessScope) -> Result<String, StorageError> {
    Ok(serde_json::to_string(scope)?)
}
impl SqliteStore {
    pub fn settings_records(&self) -> Result<Vec<SettingRecord>, StorageError> {
        // At most three keys per validated, bounded hierarchy target. Never load arbitrary payloads.
        let count: i64 = self
            .connection
            .query_row("SELECT count(*) FROM settings", [], |r| r.get(0))?;
        if count > 2048 {
            return Err(bad());
        }
        let mut stmt=self.connection.prepare("SELECT scope_key,setting_key,value_json,revision,updated_ms,actor FROM settings ORDER BY scope_key,setting_key LIMIT 2048")?;
        let raw = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, i64>(3)?,
                    r.get::<_, i64>(4)?,
                    r.get::<_, String>(5)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        let h = self.hierarchy()?;
        raw.into_iter()
            .map(|(s, k, v, revision, updated_ms, actor)| {
                if s.len() > 300 || v.len() > 1024 {
                    return Err(bad());
                }
                let scope: AccessScope = serde_json::from_str(&s)?;
                let key: SettingKey = serde_json::from_str(&format!("\"{k}\""))?;
                let value: SettingValue = serde_json::from_str(&v)?;
                key.validate(&scope, &value).map_err(|_| bad())?;
                if !h.as_ref().is_some_and(|h| h.scope_exists(&scope)) {
                    return Err(bad());
                }
                Ok(SettingRecord {
                    scope,
                    key,
                    value,
                    revision: u64::try_from(revision).map_err(|_| bad())?,
                    updated_ms,
                    actor: Some(PrincipalId::new(actor).map_err(|_| bad())?),
                })
            })
            .collect()
    }
    /// Host authority: local OS operator + exclusive DB lock; the claimed principal must ALSO have a persisted grant.
    /// Not a remotely authenticated identity, not callable through MCP/HTTP.
    pub fn change_settings_file(
        path: &Path,
        change: SettingsChange,
        at_ms: i64,
    ) -> Result<SettingsChangeResult, StorageError> {
        let _owner = DatabaseOwnership::acquire(path)?;
        let mut store = Self::open(path)?;
        #[cfg(unix)]
        let authority = {
            use std::os::unix::fs::MetadataExt;
            format!("local_os_operator_uid:{}", std::fs::metadata(path)?.uid())
        };
        #[cfg(not(unix))]
        let authority = "local_os_operator; unverified_platform".to_string();
        store.change_settings(change, at_ms, &authority)
    }
    fn change_settings(
        &mut self,
        c: SettingsChange,
        at_ms: i64,
        authority: &str,
    ) -> Result<SettingsChangeResult, StorageError> {
        c.key.validate(&c.scope, &c.value).map_err(|_| bad())?;
        let h = self.hierarchy()?.ok_or_else(bad)?;
        if !h.permits(&c.principal, CapabilityId::SettingsChange, &c.scope, false) {
            return Err(bad());
        }
        let scope = scope_key(&c.scope)?;
        let key = serde_json::to_string(&c.key)?.trim_matches('"').to_string();
        let value = serde_json::to_string(&c.value)?;
        let tx = self.write_transaction()?;
        let old: Option<i64> = tx
            .query_row(
                "SELECT revision FROM settings WHERE scope_key=?1 AND setting_key=?2",
                params![scope, key],
                |r| r.get(0),
            )
            .optional()?;
        if old.unwrap_or(0) < 0 || old.unwrap_or(0) as u64 != c.expected_revision {
            return Err(StorageError::Hierarchy("SETTINGS_REVISION_CONFLICT"));
        }
        let revision = old.unwrap_or(0).checked_add(1).ok_or_else(bad)?;
        let (o, i, s, src) = match &c.scope {
            AccessScope::Organization(v) => (Some(v.as_str()), None, None, None),
            AccessScope::Infrastructure(v) => (None, Some(v.as_str()), None, None),
            AccessScope::Site(v) => (None, None, Some(v.as_str()), None),
            AccessScope::Source(v) => (None, None, None, Some(v.as_str())),
            AccessScope::Platform => (None, None, None, None),
        };
        tx.execute("INSERT INTO setting_scopes(scope_key,organization_id,infrastructure_id,site_id,source_id) VALUES(?1,?2,?3,?4,?5) ON CONFLICT(scope_key) DO NOTHING",params![scope,o,i,s,src])?;
        tx.execute("INSERT INTO settings(scope_key,setting_key,value_json,revision,created_ms,updated_ms,actor) VALUES(?1,?2,?3,?4,?5,?5,?6) ON CONFLICT(scope_key,setting_key) DO UPDATE SET value_json=excluded.value_json,revision=excluded.revision,updated_ms=excluded.updated_ms,actor=excluded.actor",params![scope,key,value,revision,at_ms,c.principal.as_str()])?;
        tx.execute("INSERT INTO settings_audit(at_ms,principal_id,scope_key,setting_key,revision,outcome,operator_authority) VALUES(?1,?2,?3,?4,?5,'persisted_requires_restart',?6)",params![at_ms,c.principal.as_str(),scope,key,revision,authority])?;
        tx.commit()?;
        Ok(SettingsChangeResult {
            record: SettingRecord {
                scope: c.scope,
                key: c.key,
                value: c.value,
                revision: revision as u64,
                updated_ms: at_ms,
                actor: Some(c.principal),
            },
            apply_status: SettingsApplyStatus::PersistedRequiresRestart,
            effective_runtime_value: None,
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> SqliteStore {
        let mut p: ProvisioningPlan = serde_json::from_str(include_str!(
            "../../../examples/multi-infrastructure-plan.json"
        ))
        .unwrap();
        p.roles.push(ReadRole {
            id: RoleId::new("settings-operator").unwrap(),
            name: "Explicit local settings operator".into(),
            permissions: [Permission::SettingsRead, Permission::SettingsWrite].into(),
        });
        p.bindings.push(RoleBinding {
            principal_id: PrincipalId::new("platform-reader").unwrap(),
            role_id: RoleId::new("settings-operator").unwrap(),
            scope: AccessScope::Platform,
        });
        let definitions = p
            .sources
            .iter()
            .map(|s| SourceDefinition {
                id: s.source_id.clone(),
                name: s.source_id.to_string(),
                entity_id: s.entity_id.clone(),
                binding: format!("local:{}", s.source_id),
                origin_class: OriginClass::Simulation,
                simulation_origin_id: "simulation".into(),
                metrics: [(MetricId::new("temperature").unwrap(), ValueKind::Float)].into(),
                required_metrics: [MetricId::new("temperature").unwrap()].into(),
            })
            .collect::<Vec<_>>();
        let mut db = SqliteStore::open_in_memory().unwrap();
        db.provision(p, &definitions, None).unwrap();
        db
    }
    fn change(scope: AccessScope, revision: u64, value: u16) -> SettingsChange {
        SettingsChange {
            principal: PrincipalId::new("platform-reader").unwrap(),
            scope,
            key: SettingKey::HistoryPageSize,
            value: SettingValue::Integer(value),
            expected_revision: revision,
        }
    }
    #[test]
    fn revisions_atomic_audit_and_no_implicit_admin() {
        let mut db = fixture();
        let c = change(AccessScope::Platform, 0, 12);
        let r = db.change_settings(c.clone(), 123, "unit_operator").unwrap();
        assert_eq!(r.record.revision, 1);
        assert!(r.effective_runtime_value.is_none());
        assert!(db
            .change_settings(c, 124, "unit_operator")
            .unwrap_err()
            .to_string()
            .contains("REVISION_CONFLICT"));
        let mut denied = change(AccessScope::Platform, 1, 15);
        denied.principal = PrincipalId::new("reader-org-a").unwrap();
        assert!(db.change_settings(denied, 125, "unit_operator").is_err());
        assert_eq!(db.settings_records().unwrap().len(), 1);
        assert_eq!(
            db.connection
                .query_row("SELECT count(*) FROM settings_audit", [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            1
        );
    }
    #[test]
    fn rollback_after_value_write_before_audit() {
        let mut db = fixture();
        db.change_settings(change(AccessScope::Platform, 0, 12), 1, "unit_operator")
            .unwrap();
        db.connection.execute_batch("CREATE TRIGGER fail_audit BEFORE INSERT ON settings_audit BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
        assert!(db
            .change_settings(change(AccessScope::Platform, 1, 16), 2, "unit_operator")
            .is_err());
        let rows = db.settings_records().unwrap();
        assert_eq!(rows[0].revision, 1);
        assert_eq!(rows[0].value, SettingValue::Integer(12));
    }
    #[test]
    fn scoped_foreign_keys_and_canonical_json_prevent_aliases() {
        let mut db = fixture();
        db.change_settings(
            change(
                AccessScope::Source(DataSourceId::new("source-a").unwrap()),
                0,
                12,
            ),
            1,
            "unit_operator",
        )
        .unwrap();
        assert!(db
            .connection
            .execute(
                "INSERT INTO setting_scopes(scope_key,source_id) VALUES(?1,'source-b')",
                ["{\"kind\":\"source\",\"id\":\"source-c\"}"]
            )
            .is_err());
        assert!(db
            .connection
            .execute(
                "INSERT INTO setting_scopes(scope_key,source_id) VALUES(?1,'missing')",
                ["{\"kind\":\"source\",\"id\":\"missing\"}"]
            )
            .is_err());
        assert!(db
            .connection
            .execute("UPDATE setting_scopes SET source_id='source-b'", [])
            .is_err());
        assert!(db
            .connection
            .execute(
                "DELETE FROM source_placements WHERE source_id='source-a'",
                []
            )
            .is_err());
    }
    #[test]
    fn schema4_to5_failure_is_atomic_and_idempotent() {
        let mut db = SqliteStore {
            connection: Connection::open_in_memory().unwrap(),
        };
        db.connection
            .execute_batch("PRAGMA foreign_keys=ON")
            .unwrap();
        db.migrate_to(4).unwrap();
        db.connection
            .execute_batch("CREATE TABLE settings (conflict TEXT)")
            .unwrap();
        assert!(db.migrate().is_err());
        assert_eq!(db.schema_version().unwrap(), 4);
        assert_eq!(
            db.connection
                .query_row(
                    "SELECT count(*) FROM sqlite_master WHERE name='setting_scopes'",
                    [],
                    |r| r.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        db.connection.execute_batch("DROP TABLE settings").unwrap();
        assert_eq!(db.migrate().unwrap(), 5);
        assert_eq!(db.migrate().unwrap(), 5);
    }
    #[test]
    fn type_limits_and_unprovisioned_scope_rejected() {
        let mut db = fixture();
        for n in [0, 3, 101, u16::MAX] {
            assert!(db
                .change_settings(change(AccessScope::Platform, 0, n), 1, "unit_operator")
                .is_err())
        }
        let mut c = change(AccessScope::Platform, 0, 5);
        c.value = SettingValue::Text("not numeric".into());
        assert!(db.change_settings(c, 1, "unit_operator").is_err());
        assert!(db
            .change_settings(
                change(
                    AccessScope::Organization(OrganizationId::new("missing").unwrap()),
                    0,
                    5
                ),
                1,
                "unit_operator"
            )
            .is_err());
        assert!(db.settings_records().unwrap().is_empty());
    }
}

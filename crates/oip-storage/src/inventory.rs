//! Inventory is separate from telemetry identities. No source is synthesized for manual devices.
use super::*;
use oip_core::*;
pub(super) const INVENTORY_SQL: &str = r#"
CREATE TABLE inventory_devices(
 id TEXT PRIMARY KEY,site_id TEXT NOT NULL REFERENCES sites(id),display_name TEXT NOT NULL CHECK(octet_length(display_name) BETWEEN 1 AND 16384),
 device_type TEXT NOT NULL CHECK(device_type IN('server','desktop','laptop','single_board_computer','network_device','industrial_device','sensor','other')),
 metadata_json TEXT NOT NULL CHECK(json_valid(metadata_json) AND octet_length(metadata_json)<=16384),
 registration TEXT NOT NULL CHECK(registration IN('registered','archived')),
 origin TEXT NOT NULL CHECK(origin IN('manual_operator','existing_simulation_source','existing_external_source')),
 created_ms INTEGER,updated_ms INTEGER,registered_by TEXT REFERENCES principals(id),revision INTEGER NOT NULL CHECK(revision>0),
 CHECK(origin!='manual_operator' OR (created_ms IS NOT NULL AND updated_ms IS NOT NULL AND registered_by IS NOT NULL))
) STRICT;
CREATE TRIGGER inventory_protect_source BEFORE DELETE ON inventory_devices WHEN EXISTS(SELECT 1 FROM source_placements WHERE device_id=OLD.id) BEGIN SELECT RAISE(ABORT,'inventory referenced by source'); END;
CREATE INDEX inventory_by_site_id ON inventory_devices(site_id,id);
CREATE TRIGGER inventory_immutable_placement BEFORE UPDATE OF id,site_id,origin,created_ms,registered_by ON inventory_devices BEGIN SELECT RAISE(ABORT,'immutable inventory ownership/provenance'); END;
CREATE TABLE inventory_audit(sequence INTEGER PRIMARY KEY,at_ms INTEGER NOT NULL,operator_authority TEXT NOT NULL,principal_id TEXT NOT NULL REFERENCES principals(id),device_id TEXT NOT NULL REFERENCES inventory_devices(id),operation TEXT NOT NULL,revision INTEGER NOT NULL) STRICT;
INSERT INTO inventory_devices SELECT p.device_id,p.site_id,json_extract(c.payload_json,'$.name'),'other','{}','registered',CASE WHEN s.origin_class='simulation' THEN 'existing_simulation_source' ELSE 'existing_external_source' END,NULL,NULL,NULL,1 FROM source_placements p JOIN core_sources c ON c.source_id=p.source_id JOIN source_identities s ON s.data_source_id=p.source_id;
"#;
fn bad() -> StorageError {
    StorageError::Hierarchy("invalid inventory or authorization; no changes applied")
}
fn encoded<T: Serialize>(v: &T) -> Result<String, StorageError> {
    Ok(serde_json::to_string(v)?.trim_matches('"').to_string())
}
pub(super) fn sync_sources(c: &Connection) -> Result<(), StorageError> {
    let exists: bool = c.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='inventory_devices')",
        [],
        |r| r.get(0),
    )?;
    if !exists {
        return Ok(());
    }
    let bad_count:i64=c.query_row("SELECT count(*) FROM source_placements p JOIN inventory_devices d ON p.device_id=d.id WHERE p.site_id!=d.site_id",[],|r|r.get(0))?;
    if bad_count != 0 {
        return Err(bad());
    }
    let projected:i64=c.query_row("SELECT (SELECT count(*) FROM inventory_devices)+(SELECT count(*) FROM source_placements p WHERE NOT EXISTS(SELECT 1 FROM inventory_devices d WHERE d.id=p.device_id))",[],|r|r.get(0))?;
    if projected > 2048 {
        return Err(bad());
    }
    c.execute_batch("INSERT INTO inventory_devices SELECT p.device_id,p.site_id,json_extract(c.payload_json,'$.name'),'other','{}','registered',CASE WHEN s.origin_class='simulation' THEN 'existing_simulation_source' ELSE 'existing_external_source' END,NULL,NULL,NULL,1 FROM source_placements p JOIN core_sources c ON c.source_id=p.source_id JOIN source_identities s ON s.data_source_id=p.source_id WHERE true ON CONFLICT(id) DO NOTHING;")?;
    Ok(())
}
impl SqliteStore {
    pub fn inventory_records(&self) -> Result<Vec<InventoryRecord>, StorageError> {
        let count: i64 =
            self.connection
                .query_row("SELECT count(*) FROM inventory_devices", [], |r| r.get(0))?;
        if count > 2048 {
            return Err(bad());
        }
        let mut stmt=self.connection.prepare("SELECT id,site_id,display_name,device_type,metadata_json,registration,origin,created_ms,updated_ms,registered_by,revision FROM inventory_devices ORDER BY id LIMIT 2048")?;
        let rows = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                    r.get::<_, String>(4)?,
                    r.get::<_, String>(5)?,
                    r.get::<_, String>(6)?,
                    r.get::<_, Option<i64>>(7)?,
                    r.get::<_, Option<i64>>(8)?,
                    r.get::<_, Option<String>>(9)?,
                    r.get::<_, i64>(10)?,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        rows.into_iter()
            .map(
                |(
                    id,
                    site_id,
                    display_name,
                    kind,
                    metadata,
                    registration,
                    origin,
                    created_ms,
                    updated_ms,
                    actor,
                    revision,
                )| {
                    if metadata.len() > 16384 {
                        return Err(bad());
                    }
                    let device = DeviceRegistration {
                        id: DeviceId::new(id).map_err(|_| bad())?,
                        site_id: SiteId::new(site_id).map_err(|_| bad())?,
                        display_name,
                        device_type: serde_json::from_str(&format!("\"{kind}\""))?,
                        metadata: serde_json::from_str(&metadata)?,
                    };
                    let origin: InventoryOrigin = serde_json::from_str(&format!("\"{origin}\""))?;
                    if origin == InventoryOrigin::ManualOperator {
                        device.validate()
                    } else {
                        device.validate_existing_source()
                    }
                    .map_err(|_| bad())?;
                    Ok(InventoryRecord {
                        device,
                        registration: serde_json::from_str(&format!("\"{registration}\""))?,
                        origin,
                        created_ms,
                        updated_ms,
                        registered_by: actor
                            .map(|p| PrincipalId::new(p).map_err(|_| bad()))
                            .transpose()?,
                        revision: u64::try_from(revision).map_err(|_| bad())?,
                    })
                },
            )
            .collect()
    }
    pub fn inventory_admin_file(
        path: &Path,
        request: InventoryAdministration,
        apply: bool,
        at_ms: i64,
    ) -> Result<InventoryPlan, StorageError> {
        if !path.is_file() {
            return Err(bad());
        }
        let _owner = DatabaseOwnership::acquire(path)?;
        let canonical = std::fs::canonicalize(path)?;
        let path = canonical.as_path();
        let mut db = Self {
            connection: Connection::open_with_flags(
                path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )?,
        };
        if db.schema_version()? != 6 {
            return Err(StorageError::Hierarchy(
                "INVENTORY_MIGRATION_REQUIRED; run controlled runtime migration separately",
            ));
        }
        if !apply {
            return db.inventory_admin(request, false, at_ms, "dry_run_readonly");
        }
        drop(db);
        let mut db = Self::open(path)?;
        #[cfg(unix)]
        let authority = {
            use std::os::unix::fs::MetadataExt;
            format!("local_os_operator_uid:{}", std::fs::metadata(path)?.uid())
        };
        #[cfg(not(unix))]
        let authority = "local_os_operator_unverified_platform".to_string();
        db.inventory_admin(request, apply, at_ms, &authority)
    }
    fn inventory_admin(
        &mut self,
        request: InventoryAdministration,
        apply: bool,
        at_ms: i64,
        authority: &str,
    ) -> Result<InventoryPlan, StorageError> {
        let h = self.hierarchy()?.ok_or_else(bad)?;
        let rows = self.inventory_records()?;
        let mut plan = validate_inventory_plan(&h, &request.principal, &rows, &request.changes)
            .map_err(|_| bad())?;
        if !apply {
            return Ok(plan);
        }
        let tx = self.write_transaction()?;
        for (change, action) in request.changes.iter().zip(&plan.actions) {
            if action.outcome == "idempotent" {
                continue;
            }
            match change {
                InventoryChange::Register { device } => {
                    tx.execute("INSERT INTO inventory_devices VALUES(?1,?2,?3,?4,?5,'registered','manual_operator',?6,?6,?7,1)",params![device.id.as_str(),device.site_id.as_str(),device.display_name,encoded(&device.device_type)?,serde_json::to_string(&device.metadata)?,at_ms,request.principal.as_str()])?;
                }
                InventoryChange::Update {
                    device,
                    expected_revision,
                } => {
                    let n=tx.execute("UPDATE inventory_devices SET display_name=?1,device_type=?2,metadata_json=?3,updated_ms=?4,revision=revision+1 WHERE id=?5 AND revision=?6",params![device.display_name,encoded(&device.device_type)?,serde_json::to_string(&device.metadata)?,at_ms,device.id.as_str(),i64::try_from(*expected_revision).map_err(|_|bad())?])?;
                    if n != 1 {
                        return Err(bad());
                    }
                }
                InventoryChange::Archive {
                    id,
                    expected_revision,
                } => {
                    let n=tx.execute("UPDATE inventory_devices SET registration='archived',updated_ms=?1,revision=revision+1 WHERE id=?2 AND revision=?3",params![at_ms,id.as_str(),i64::try_from(*expected_revision).map_err(|_|bad())?])?;
                    if n != 1 {
                        return Err(bad());
                    }
                }
            }
            let revision = if action.outcome == "create" {
                1
            } else {
                action.expected_revision.checked_add(1).ok_or_else(bad)?
            };
            tx.execute("INSERT INTO inventory_audit(at_ms,operator_authority,principal_id,device_id,operation,revision) VALUES(?1,?2,?3,?4,?5,?6)",params![at_ms,authority,request.principal.as_str(),action.id.as_str(),action.outcome,i64::try_from(revision).map_err(|_|bad())?])?;
        }
        tx.commit()?;
        plan.applied = true;
        Ok(plan)
    }
    /// Evidence-only classification. No delete/apply operation exists.
    pub fn inventory_cleanup_dry_run(&self) -> Result<serde_json::Value, StorageError> {
        let count = || -> Result<(i64, i64, i64, i64), StorageError> {
            Ok(self.connection.query_row("SELECT (SELECT count(*) FROM observations),(SELECT count(*) FROM collection_events),(SELECT count(*) FROM data_gaps),(SELECT count(*) FROM inventory_devices)",[],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?)))?)
        };
        let before = count()?;
        let rows = self.inventory_records()?;
        let h = self.hierarchy()?.ok_or_else(bad)?;
        let classes=rows.iter().map(|r|serde_json::json!({"device_id":r.device.id,"classification":r.origin,"source_references":h.plan.sources.iter().filter(|s|s.device_id==r.device.id).map(|s|s.source_id.clone()).collect::<Vec<_>>(),"decision":"PRESERVE; no deletion implementation and never classify by display name","revision":r.revision})).collect::<Vec<_>>();
        let fk: i64 = self.connection.query_row(
            "SELECT count(*) FROM pragma_foreign_key_check",
            [],
            |r| r.get(0),
        )?;
        let after = count()?;
        Ok(
            serde_json::json!({"dry_run":true,"deletion_supported":false,"devices":classes,"before_counts":{"observations":before.0,"events":before.1,"gaps":before.2,"inventory":before.3},"after_counts":{"observations":after.0,"events":after.1,"gaps":after.2,"inventory":after.3},"before_after_counts_equal":before==after,"foreign_key_violations":fk,"backup_performed":false,"backup_required_before_any_future_cleanup":true,"rollback_plan":"restore an independently verified offline SQLite backup; no cleanup applied"}),
        )
    }
}
impl SqliteStore {
    pub fn inventory_inspect_file(
        path: &Path,
        principal: &PrincipalId,
    ) -> Result<serde_json::Value, StorageError> {
        if !path.is_file() {
            return Err(bad());
        }
        let _owner = DatabaseOwnership::acquire(path)?;
        let canonical = std::fs::canonicalize(path)?;
        let path = canonical.as_path();
        let db = Self {
            connection: Connection::open_with_flags(
                path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )?,
        };
        let h = db.hierarchy()?.ok_or_else(bad)?;
        if !h.platform(principal, CapabilityId::InventoryChange) {
            return Err(bad());
        }
        if db.schema_version()? < 6 {
            return Ok(
                serde_json::json!({"dry_run":true,"deletion_supported":false,"classification":"unavailable before schema6; all records preserved","migration_applied":false}),
            );
        }
        db.inventory_cleanup_dry_run()
    }
}

impl SqliteStore {
    pub fn inventory_snapshot_file(
        path: &Path,
    ) -> Result<(HierarchyRegistry, Vec<InventoryRecord>), StorageError> {
        if !path.is_file() {
            return Err(bad());
        }
        let _owner = DatabaseOwnership::acquire(path)?;
        let canonical = std::fs::canonicalize(path)?;
        let path = canonical.as_path();
        let db = Self {
            connection: Connection::open_with_flags(
                path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )?,
        };
        if db.schema_version()? != 6 {
            return Err(StorageError::Hierarchy("INVENTORY_MIGRATION_REQUIRED"));
        }
        Ok((db.hierarchy()?.ok_or_else(bad)?, db.inventory_records()?))
    }
}

impl SqliteStore {
    pub fn inventory_initialize_file(
        path: &Path,
        principal: &PrincipalId,
    ) -> Result<u32, StorageError> {
        if !path.is_file() {
            return Err(bad());
        }
        let _owner = DatabaseOwnership::acquire(path)?;
        let canonical = std::fs::canonicalize(path)?;
        let path = canonical.as_path();
        let old = Self {
            connection: Connection::open_with_flags(
                path,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )?,
        };
        let h = old.hierarchy()?.ok_or_else(bad)?;
        if !h
            .plan
            .bindings
            .iter()
            .filter(|b| &b.principal_id == principal)
            .any(|b| h.permits(principal, CapabilityId::InventoryChange, &b.scope, false))
        {
            return Err(bad());
        }
        drop(old);
        Self::open(path)?.schema_version()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    pub(super) fn plan() -> ProvisioningPlan {
        let mut p: ProvisioningPlan = serde_json::from_str(include_str!(
            "../../../examples/multi-infrastructure-plan.json"
        ))
        .unwrap();
        p.sources.clear();
        p.bindings
            .retain(|b| !matches!(b.scope, AccessScope::Source(_)));
        p.roles.push(ReadRole {
            id: RoleId::new("inventory-admin").unwrap(),
            name: "Explicit test admin".into(),
            permissions: [Permission::InventoryManage, Permission::DevicesRead].into(),
        });
        p.bindings.push(RoleBinding {
            principal_id: PrincipalId::new("platform-reader").unwrap(),
            role_id: RoleId::new("inventory-admin").unwrap(),
            scope: AccessScope::Platform,
        });
        p
    }
    fn db() -> SqliteStore {
        let mut d = SqliteStore::open_in_memory().unwrap();
        d.provision(plan(), &[], None).unwrap();
        d
    }
    pub(super) fn device(id: &str, site: &str) -> DeviceRegistration {
        DeviceRegistration {
            id: DeviceId::new(id).unwrap(),
            display_name: "AMD EVO-X2".into(),
            device_type: DeviceType::Server,
            site_id: SiteId::new(site).unwrap(),
            metadata: DeviceMetadata::default(),
        }
    }
    pub(super) fn request(changes: Vec<InventoryChange>) -> InventoryAdministration {
        InventoryAdministration {
            principal: PrincipalId::new("platform-reader").unwrap(),
            changes,
        }
    }
    #[test]
    fn register_update_archive_preserve_identity_and_idempotency() {
        let mut d = db();
        let v = device("actual-manual", "site-a1");
        let r = request(vec![InventoryChange::Register { device: v.clone() }]);
        assert!(
            !d.inventory_admin(r.clone(), false, 1, "unit")
                .unwrap()
                .applied
        );
        assert!(d.inventory_records().unwrap().is_empty());
        d.inventory_admin(r.clone(), true, 1, "unit").unwrap();
        assert_eq!(
            d.inventory_admin(r, true, 2, "unit").unwrap().actions[0].outcome,
            "idempotent"
        );
        let row = d.inventory_records().unwrap().remove(0);
        assert_eq!(row.origin, InventoryOrigin::ManualOperator);
        assert_eq!(row.revision, 1);
        assert_eq!(
            d.connection
                .query_row("SELECT count(*) FROM core_sources", [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            0
        );
        let mut changed = v;
        changed.display_name = "Renamed real host".into();
        d.inventory_admin(
            request(vec![InventoryChange::Update {
                device: changed,
                expected_revision: 1,
            }]),
            true,
            3,
            "unit",
        )
        .unwrap();
        assert!(d
            .inventory_admin(
                request(vec![InventoryChange::Archive {
                    id: row.device.id.clone(),
                    expected_revision: 1
                }]),
                true,
                4,
                "unit"
            )
            .is_err());
        d.inventory_admin(
            request(vec![InventoryChange::Archive {
                id: row.device.id,
                expected_revision: 2,
            }]),
            true,
            4,
            "unit",
        )
        .unwrap();
        let row = d.inventory_records().unwrap().remove(0);
        assert_eq!(row.revision, 3);
        assert_eq!(row.registration, RegistrationStatus::Archived);
        assert_eq!(row.created_ms, Some(1));
    }
    #[test]
    fn import_rollback_audit_failure_and_duplicate_ids() {
        let mut d = db();
        let r = request(vec![
            InventoryChange::Register {
                device: device("a", "site-a1"),
            },
            InventoryChange::Register {
                device: device("b", "site-b1"),
            },
        ]);
        d.connection.execute_batch("CREATE TRIGGER fail_second BEFORE INSERT ON inventory_audit WHEN NEW.device_id='b' BEGIN SELECT RAISE(ABORT,'failure injection'); END").unwrap();
        assert!(d.inventory_admin(r, true, 1, "unit").is_err());
        assert!(d.inventory_records().unwrap().is_empty());
        assert_eq!(
            d.connection
                .query_row("SELECT count(*) FROM inventory_audit", [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            0
        );
        let same = InventoryChange::Register {
            device: device("a", "site-a1"),
        };
        assert!(d
            .inventory_admin(request(vec![same.clone(), same]), true, 1, "unit")
            .is_err());
    }
    #[test]
    fn no_implicit_admin_cross_site_move_or_foreign_registration() {
        let mut d = db();
        let mut r = request(vec![InventoryChange::Register {
            device: device("a", "site-a1"),
        }]);
        r.principal = PrincipalId::new("reader-org-a").unwrap();
        assert!(d.inventory_admin(r, true, 1, "unit").is_err());
        let mut p = plan();
        p.bindings.push(RoleBinding {
            principal_id: PrincipalId::new("reader-org-a").unwrap(),
            role_id: RoleId::new("inventory-admin").unwrap(),
            scope: AccessScope::Organization(OrganizationId::new("org-a").unwrap()),
        });
        d.provision(p, &[], None).unwrap();
        let mut r = request(vec![InventoryChange::Register {
            device: device("b", "site-b1"),
        }]);
        r.principal = PrincipalId::new("reader-org-a").unwrap();
        assert!(d.inventory_admin(r, true, 1, "unit").is_err());
        d.inventory_admin(
            request(vec![InventoryChange::Register {
                device: device("a", "site-a1"),
            }]),
            true,
            1,
            "unit",
        )
        .unwrap();
        assert!(d
            .inventory_admin(
                request(vec![InventoryChange::Update {
                    device: device("a", "site-b1"),
                    expected_revision: 1
                }]),
                true,
                2,
                "unit"
            )
            .is_err());
    }
    #[test]
    fn migration5_to6_fail_atomic_idempotent_no_settings_loss() {
        let mut d = SqliteStore {
            connection: Connection::open_in_memory().unwrap(),
        };
        d.connection
            .execute_batch("PRAGMA foreign_keys=ON")
            .unwrap();
        d.migrate_to(5).unwrap();
        d.provision(plan(), &[], None).unwrap();
        d.connection.execute_batch(r#"INSERT INTO setting_scopes(scope_key) VALUES('{"kind":"platform"}');INSERT INTO settings VALUES('{"kind":"platform"}','history_page_size','{"type":"integer","value":7}',1,1,1,'platform-reader');"#).unwrap();
        d.connection
            .execute_batch("CREATE TABLE inventory_devices(conflict TEXT)")
            .unwrap();
        assert!(d.migrate().is_err());
        assert_eq!(d.schema_version().unwrap(), 5);
        assert_eq!(
            d.connection
                .query_row(
                    "SELECT count(*) FROM sqlite_master WHERE name='inventory_audit'",
                    [],
                    |r| r.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        d.connection
            .execute_batch("DROP TABLE inventory_devices")
            .unwrap();
        assert_eq!(d.migrate().unwrap(), 6);
        assert_eq!(
            d.settings_records().unwrap()[0].value,
            SettingValue::Integer(7)
        );
        assert_eq!(d.migrate().unwrap(), 6);
        assert_eq!(
            d.hierarchy().unwrap().unwrap().plan,
            HierarchyRegistry::new(plan()).unwrap().plan
        );
    }
}

#[cfg(test)]
mod integrity_tests {
    use super::tests::{device, plan, request};
    use super::*;
    #[test]
    fn dry_run_is_readonly_and_never_creates_or_migrates() {
        let dir = std::env::temp_dir().join(format!(
            "oip85-dry-{}-{}",
            std::process::id(),
            Timestamp::now().unwrap().as_unix_millis()
        ));
        std::fs::create_dir(&dir).unwrap();
        let path = dir.join("db.sqlite");
        let req = request(vec![InventoryChange::Register {
            device: device("a", "site-a1"),
        }]);
        assert!(SqliteStore::inventory_admin_file(&path, req.clone(), false, 1).is_err());
        assert!(!path.exists());
        assert!(SqliteStore::inventory_inspect_file(
            &path,
            &PrincipalId::new("platform-reader").unwrap()
        )
        .is_err());
        assert!(SqliteStore::inventory_snapshot_file(&path).is_err());
        assert!(!path.exists());
        {
            let _o = DatabaseOwnership::acquire(&path).unwrap();
            let mut d = SqliteStore {
                connection: Connection::open(&path).unwrap(),
            };
            d.connection
                .execute_batch("PRAGMA foreign_keys=ON")
                .unwrap();
            d.migrate_to(5).unwrap();
            d.provision(plan(), &[], None).unwrap();
        }
        let before = std::fs::read(&path).unwrap();
        assert!(SqliteStore::inventory_admin_file(&path, req.clone(), false, 1).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), before);
        SqliteStore::inventory_initialize_file(
            &path,
            &PrincipalId::new("platform-reader").unwrap(),
        )
        .unwrap();
        let before = std::fs::read(&path).unwrap();
        assert!(
            !SqliteStore::inventory_admin_file(&path, req, false, 1)
                .unwrap()
                .applied
        );
        assert_eq!(std::fs::read(&path).unwrap(), before);
    }
    fn legacy(name: String) -> (SqliteStore, SourceDefinition) {
        let c = Connection::open_in_memory().unwrap();
        c.execute_batch("PRAGMA foreign_keys=ON").unwrap();
        let mut d = SqliteStore { connection: c };
        d.migrate_to(5).unwrap();
        let mut p = plan();
        let source = DataSourceId::new("source-a").unwrap();
        p.sources.push(SourcePlacement {
            source_id: source.clone(),
            site_id: SiteId::new("site-a1").unwrap(),
            device_id: DeviceId::new("old-id").unwrap(),
            entity_id: EntityId::new("M-01").unwrap(),
        });
        let def = SourceDefinition {
            id: source,
            name,
            entity_id: EntityId::new("M-01").unwrap(),
            binding: "local:simulation".into(),
            origin_class: OriginClass::Simulation,
            simulation_origin_id: "test".into(),
            metrics: [(MetricId::new("temperature").unwrap(), ValueKind::Float)].into(),
            required_metrics: [MetricId::new("temperature").unwrap()].into(),
        };
        d.provision(p, std::slice::from_ref(&def), None).unwrap();
        (d, def)
    }
    #[test]
    fn legacy_unicode_name_and_source_origin_survive_without_type_inference() {
        let name = "Ä".repeat(200);
        let (mut d, _) = legacy(name.clone());
        d.migrate().unwrap();
        let row = d.inventory_records().unwrap().remove(0);
        assert_eq!(row.device.display_name, name);
        assert_eq!(row.device.id.as_str(), "old-id");
        assert_eq!(row.device.device_type, DeviceType::Other);
        assert_eq!(row.origin, InventoryOrigin::ExistingSimulationSource);
        assert!(row.created_ms.is_none() && row.registered_by.is_none());
    }
    #[test]
    fn oversized_legacy_name_fails_before_committing_schema6() {
        let (mut d, _) = legacy("x".repeat(16385));
        assert!(d.migrate().is_err());
        assert_eq!(d.schema_version().unwrap(), 5);
        assert_eq!(
            d.connection
                .query_row(
                    "SELECT count(*) FROM sqlite_master WHERE name='inventory_devices'",
                    [],
                    |r| r.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        assert_eq!(
            d.connection
                .query_row("SELECT count(*) FROM source_placements", [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            1
        );
    }
    #[test]
    fn invalid_source_projection_rolls_back_provisioning_instead_of_ignoring() {
        let mut d = SqliteStore::open_in_memory().unwrap();
        d.provision(plan(), &[], None).unwrap();
        let (_, def) = legacy("x".repeat(16385));
        let mut p = plan();
        p.sources.push(SourcePlacement {
            source_id: def.id.clone(),
            site_id: SiteId::new("site-a1").unwrap(),
            device_id: DeviceId::new("old-id").unwrap(),
            entity_id: def.entity_id.clone(),
        });
        assert!(d.provision(p, &[def], None).is_err());
        assert!(d.hierarchy().unwrap().unwrap().plan.sources.is_empty());
        assert!(d.inventory_records().unwrap().is_empty());
    }
}

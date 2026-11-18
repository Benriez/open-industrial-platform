//! All mutations run on the existing owned writer connection, never a second writer.
use super::*;
use oip_core::*;
pub(super) const CONNECTION_SQL: &str = r#"
CREATE TABLE device_connections(device_id TEXT PRIMARY KEY REFERENCES inventory_devices(id),source_id TEXT NOT NULL UNIQUE REFERENCES source_placements(source_id),payload_json TEXT NOT NULL CHECK(json_valid(payload_json) AND octet_length(payload_json)<=131072)) STRICT;
CREATE TABLE device_connection_attempts(device_id TEXT PRIMARY KEY REFERENCES inventory_devices(id),payload_json TEXT NOT NULL CHECK(json_valid(payload_json) AND octet_length(payload_json)<=16384)) STRICT;
CREATE TABLE device_connection_audit(sequence INTEGER PRIMARY KEY,at_ms INTEGER NOT NULL,principal_id TEXT NOT NULL REFERENCES principals(id),device_id TEXT NOT NULL REFERENCES inventory_devices(id),operation TEXT NOT NULL,revision INTEGER NOT NULL) STRICT;
"#;
fn invalid() -> StorageError {
    StorageError::Hierarchy("connection authorization/revision validation failed")
}
impl SqliteStore {
    pub fn connection_records(&self) -> Result<Vec<DeviceConnectionRecord>, StorageError> {
        let mut q = self
            .connection
            .prepare("SELECT payload_json FROM device_connections ORDER BY device_id LIMIT 129")?;
        let rows = q
            .query_map([], |r| r.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        if rows.len() > 128 {
            return Err(invalid());
        }
        rows.into_iter()
            .map(|s| Ok(serde_json::from_str(&s)?))
            .collect()
    }
    /// Add metrics introduced by a newer SSH collector while preserving any
    /// source metrics already registered for this verified device connection.
    pub fn merge_connection_source_definition(
        &mut self,
        definition: &SourceDefinition,
    ) -> Result<(), StorageError> {
        if definition.origin_class != OriginClass::External
            || !self
                .connection_records()?
                .iter()
                .any(|connection| connection.source_id == definition.id)
        {
            return Err(invalid());
        }
        let Some(mut current) = self
            .definitions()
            .map_err(|_| invalid())?
            .into_iter()
            .find(|source| source.id == definition.id)
        else {
            return Err(invalid());
        };
        if current.origin_class != OriginClass::External
            || current.entity_id != definition.entity_id
        {
            return Err(invalid());
        }
        current.metrics.extend(definition.metrics.clone());
        current
            .required_metrics
            .extend(definition.required_metrics.clone());
        self.connection.execute(
            "UPDATE core_sources SET payload_json=?1 WHERE source_id=?2",
            params![serde_json::to_string(&current)?, definition.id.as_str()],
        )?;
        Ok(())
    }
    pub fn connection_attempts(&self) -> Result<Vec<ConnectionAttempt>, StorageError> {
        let mut q = self.connection.prepare(
            "SELECT payload_json FROM device_connection_attempts ORDER BY device_id LIMIT 2049",
        )?;
        let rows = q
            .query_map([], |r| r.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        if rows.len() > 2048 {
            return Err(invalid());
        }
        rows.into_iter()
            .map(|s| Ok(serde_json::from_str(&s)?))
            .collect()
    }
    pub fn connection_commit(
        &mut self,
        request: &VerifiedConnectionCommit,
        definition: &SourceDefinition,
        at: i64,
    ) -> Result<(), StorageError> {
        let h = self.hierarchy()?.ok_or_else(invalid)?;
        let rows = self.inventory_records()?;
        let c = &request.connection;
        c.endpoint.validate().map_err(|_| invalid())?;
        validate_poll_seconds(c.poll_seconds).map_err(|_| invalid())?;
        if !h.permits(
            &request.principal,
            CapabilityId::DeviceConnectionConfigure,
            &AccessScope::Site(request.device.site_id.clone()),
            false,
        ) || c.authorized_principal != request.principal
            || c.device_id != request.device.id
            || definition.id != c.source_id
            || definition.origin_class != OriginClass::External
            || definition.entity_id.as_str() != request.device.id.as_str()
            || self.connection_records()?.len() >= 128
            || h.source_for_device(request.device.id.as_str()).is_some()
        {
            return Err(invalid());
        }
        let change = match request.expected_revision {
            Some(rev) => InventoryChange::Update {
                device: request.device.clone(),
                expected_revision: rev,
            },
            None => InventoryChange::Register {
                device: request.device.clone(),
            },
        };
        let plan = validate_inventory_plan(&h, &request.principal, &rows, &[change])
            .map_err(|_| invalid())?;
        if request.expected_revision.is_none() && plan.actions[0].outcome != "create" {
            return Err(invalid());
        }
        // Validate the complete prospective registry before any SQL writes.
        // In particular, the existing shared 32-source bound also applies to SSH.
        let mut prospective = h.plan.clone();
        prospective.sources.push(SourcePlacement {
            source_id: c.source_id.clone(),
            site_id: request.device.site_id.clone(),
            device_id: request.device.id.clone(),
            entity_id: definition.entity_id.clone(),
        });
        HierarchyRegistry::new(prospective).map_err(|_| invalid())?;
        let tx = self.write_transaction()?;
        tx.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
        match request.expected_revision {
            Some(rev) => {
                let n=tx.execute("UPDATE inventory_devices SET revision=revision+1,updated_ms=?1 WHERE id=?2 AND revision=?3 AND registration='registered'",params![at,request.device.id.as_str(),i64::try_from(rev).map_err(|_|invalid())?])?;
                if n != 1 {
                    return Err(invalid());
                }
            }
            None => {
                tx.execute("INSERT INTO inventory_devices VALUES(?1,?2,?3,?4,?5,'registered','manual_operator',?6,?6,?7,1)",params![request.device.id.as_str(),request.device.site_id.as_str(),request.device.display_name,serde_json::to_string(&request.device.device_type)?.trim_matches('"'),serde_json::to_string(&request.device.metadata)?,at,request.principal.as_str()])?;
            }
        }
        tx.execute(
            "INSERT INTO core_sources VALUES(?1,?2)",
            params![definition.id.as_str(), serde_json::to_string(definition)?],
        )?;
        tx.execute(
            "INSERT INTO source_placements VALUES(?1,?2,?3,?4)",
            params![
                c.source_id.as_str(),
                request.device.site_id.as_str(),
                request.device.id.as_str(),
                definition.entity_id.as_str()
            ],
        )?;
        tx.execute(
            "INSERT INTO source_identities VALUES(?1,'external')",
            [c.source_id.as_str()],
        )?;
        tx.execute(
            "INSERT INTO device_connections VALUES(?1,?2,?3)",
            params![
                c.device_id.as_str(),
                c.source_id.as_str(),
                serde_json::to_string(c)?
            ],
        )?;
        tx.execute("INSERT INTO device_connection_audit(at_ms,principal_id,device_id,operation,revision) VALUES(?1,?2,?3,'verified_identity_bind',?4)",params![at,request.principal.as_str(),c.device_id.as_str(),i64::try_from(c.revision).map_err(|_|invalid())?])?;
        tx.commit()?;
        Ok(())
    }
    pub fn connection_control(
        &mut self,
        p: &PrincipalId,
        id: &DeviceId,
        expected: u64,
        enabled: bool,
        seconds: u64,
        at: i64,
    ) -> Result<DeviceConnectionRecord, StorageError> {
        validate_poll_seconds(seconds).map_err(|_| invalid())?;
        let h = self.hierarchy()?.ok_or_else(invalid)?;
        let records = self.inventory_records()?;
        let row = records
            .iter()
            .find(|r| r.device.id == *id)
            .ok_or_else(invalid)?;
        if row.registration != RegistrationStatus::Registered {
            return Err(invalid());
        }
        let mut c = self
            .connection_records()?
            .into_iter()
            .find(|c| c.device_id == *id && c.revision == expected)
            .ok_or_else(invalid)?;
        if (!h.permits(
            p,
            CapabilityId::DeviceConnectionConfigure,
            &AccessScope::Site(row.device.site_id.clone()),
            false,
        ) && !h.permits(
            p,
            CapabilityId::DeviceConnectionConfigure,
            &AccessScope::Source(c.source_id.clone()),
            false,
        )) || (enabled && &c.authorized_principal != p)
        {
            return Err(invalid());
        }
        c.enabled = enabled;
        c.poll_seconds = seconds;
        c.revision = c.revision.checked_add(1).ok_or_else(invalid)?;
        let tx = self.write_transaction()?;
        tx.execute(
            "UPDATE device_connections SET payload_json=?1 WHERE device_id=?2",
            params![serde_json::to_string(&c)?, id.as_str()],
        )?;
        tx.execute("INSERT INTO device_connection_audit(at_ms,principal_id,device_id,operation,revision) VALUES(?1,?2,?3,'monitoring_configuration',?4)",params![at,p.as_str(),id.as_str(),i64::try_from(c.revision).map_err(|_|invalid())?])?;
        tx.commit()?;
        Ok(c)
    }
    pub fn connection_attempt(
        &mut self,
        attempt: &ConnectionAttempt,
        success: bool,
    ) -> Result<(), StorageError> {
        let tx = self.write_transaction()?;
        tx.execute("INSERT INTO device_connection_attempts VALUES(?1,?2) ON CONFLICT(device_id) DO UPDATE SET payload_json=excluded.payload_json",params![attempt.device_id.as_str(),serde_json::to_string(attempt)?])?;
        let previous: Option<String> = tx
            .query_row(
                "SELECT payload_json FROM device_connections WHERE device_id=?1",
                [attempt.device_id.as_str()],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(previous) = previous {
            let mut c: DeviceConnectionRecord = serde_json::from_str(&previous)?;
            c.last_attempt_ms = Some(attempt.at_ms);
            c.last_error = attempt.error.clone();
            if success {
                c.last_success_ms = Some(attempt.at_ms);
                if let Some(neighbors) = &attempt.neighbors {
                    c.identity.neighbors = neighbors.clone();
                }
            }
            tx.execute(
                "UPDATE device_connections SET payload_json=?1 WHERE device_id=?2",
                params![serde_json::to_string(&c)?, attempt.device_id.as_str()],
            )?;
        }
        tx.commit()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stored_payload_bound_matches_the_shared_domain_constant() {
        // The schema limit and the server side guard must be the same value, so
        // a verified host report is either storable or rejected explicitly.
        assert!(
            CONNECTION_SQL.contains(&format!(
                "octet_length(payload_json)<={CONNECTION_PAYLOAD_MAX_BYTES}"
            )),
            "the device_connections CHECK must use the shared bound"
        );
        assert!(CONNECTION_SQL.contains(&format!(
            "octet_length(payload_json)<={}",
            CONNECTION_ATTEMPT_PAYLOAD_MAX_BYTES
        )));
    }
    #[test]
    fn shared_source_limit_rejects_binding_before_inventory_or_source_writes() {
        let mut plan: ProvisioningPlan = serde_json::from_str(include_str!(
            "../../../examples/multi-infrastructure-plan.json"
        ))
        .unwrap();
        plan.roles[0]
            .permissions
            .insert(Permission::InventoryManage);
        plan.bindings
            .retain(|b| !matches!(b.scope, AccessScope::Source(_)));
        let base = plan.sources[0].clone();
        plan.sources = (0..32)
            .map(|n| SourcePlacement {
                source_id: DataSourceId::new(format!("fixture-source-{n}")).unwrap(),
                device_id: DeviceId::new(format!("fixture-device-{n}")).unwrap(),
                ..base.clone()
            })
            .collect();
        let definition = |id: DataSourceId, entity: EntityId| SourceDefinition {
            id,
            name: "Storage unit fixture; no network".into(),
            entity_id: entity,
            binding: "unit-fixture://no-network".into(),
            origin_class: OriginClass::Simulation,
            simulation_origin_id: "oip-local-simulation-v1".into(),
            metrics: [(MetricId::new("host.os").unwrap(), ValueKind::Text)].into(),
            required_metrics: [MetricId::new("host.os").unwrap()].into(),
        };
        let definitions = plan
            .sources
            .iter()
            .map(|s| definition(s.source_id.clone(), s.entity_id.clone()))
            .collect::<Vec<_>>();
        let mut db = SqliteStore::open_in_memory().unwrap();
        db.provision(plan.clone(), &definitions, None).unwrap();
        let before = db.inventory_records().unwrap().len();
        let record: DeviceConnectionRecord = serde_json::from_value(serde_json::json!({
            "device_id":"new-unit-device","source_id":"new-unit-source","authorized_principal":"reader-org-a",
            "endpoint":{"host":"127.0.0.1","port":22,"user":"unit-user","identity_profile":"unit-fixture"},
            "host_key":"ssh-ed25519 unit-fixture", "fingerprint":"SHA256:unit-fixture",
            "identity":{"hostname":"fixture","operating_system":"Linux","architecture":"aarch64","cpu_info":null,"model":null,"stable_host_id_sha256":null,"memory_total_bytes":null,"memory_used_bytes":null,"uptime_seconds":null,"disks":[],"interfaces":[],"captured_at_ms":1,"unavailable":[],"provenance":"storage unit fixture; no SSH claim"},
            "verified_at_ms":1,"enabled":false,"poll_seconds":30,"revision":1,"last_attempt_ms":null,"last_success_ms":null,"last_error":null
        })).unwrap();
        let request = VerifiedConnectionCommit {
            principal: PrincipalId::new("reader-org-a").unwrap(),
            device: DeviceRegistration {
                id: record.device_id.clone(),
                display_name: "Unit fixture".into(),
                device_type: DeviceType::Server,
                site_id: SiteId::new("site-a1").unwrap(),
                metadata: DeviceMetadata::default(),
            },
            expected_revision: None,
            connection: record,
        };
        let mut def = definition(
            request.connection.source_id.clone(),
            EntityId::new("new-unit-device").unwrap(),
        );
        def.origin_class = OriginClass::External;
        def.simulation_origin_id.clear();
        assert!(db.connection_commit(&request, &def, 2).is_err());
        assert_eq!(db.inventory_records().unwrap().len(), before);
        assert_eq!(db.hierarchy().unwrap().unwrap().plan.sources.len(), 32);
        assert!(db.connection_records().unwrap().is_empty());
        assert!(db
            .connection
            .prepare("PRAGMA foreign_key_check")
            .unwrap()
            .query([])
            .unwrap()
            .next()
            .unwrap()
            .is_none());
        // Identical verified unit request must commit when one source slot is free.
        // This control proves the negative case did not merely fail another precondition.
        let mut available = plan;
        available.sources.pop();
        let mut fewer_definitions = definitions;
        fewer_definitions.pop();
        let mut room = SqliteStore::open_in_memory().unwrap();
        room.provision(available, &fewer_definitions, None).unwrap();
        room.connection_commit(&request, &def, 2).unwrap();
        assert_eq!(room.hierarchy().unwrap().unwrap().plan.sources.len(), 32);
        assert_eq!(room.connection_records().unwrap().len(), 1);
        assert!(room
            .connection_control(
                &PrincipalId::new("platform-reader").unwrap(),
                &request.device.id,
                1,
                true,
                30,
                3
            )
            .is_err());
        assert_eq!(room.connection_records().unwrap()[0].revision, 1);
        assert_eq!(
            room.connection_control(&request.principal, &request.device.id, 1, true, 30, 3)
                .unwrap()
                .revision,
            2
        );
    }
}

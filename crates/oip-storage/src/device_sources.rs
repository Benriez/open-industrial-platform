//! The registration of a verified collector for a device that the operator has
//! already registered in the inventory. The configuration of the instance names
//! the collector (for example the read-only Hue bridge whose identity is pinned
//! to its own certificate); the placement of the source stays bound to the
//! registered device and its site.
use super::*;
use oip_core::*;

fn invalid() -> StorageError {
    StorageError::Hierarchy("device source registration validation failed")
}

impl SqliteStore {
    /// Register (or refresh) the source of a verified read-only collector. The
    /// identity of the device, its site and the origin class are never changed:
    /// only the declared metrics of the source are extended.
    pub fn register_device_source(
        &mut self,
        device_id: &DeviceId,
        definition: &SourceDefinition,
    ) -> Result<(), StorageError> {
        let hierarchy = self.hierarchy()?.ok_or_else(invalid)?;
        let bounded = definition.id.as_str().len() <= 128
            && definition
                .id
                .as_str()
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b));
        if !bounded
            || definition.origin_class != OriginClass::External
            || definition.entity_id.as_str() != device_id.as_str()
            || definition.metrics.is_empty()
        {
            return Err(invalid());
        }
        let inventory = self.inventory_records()?;
        let device = inventory
            .iter()
            .find(|row| &row.device.id == device_id)
            .ok_or_else(invalid)?;
        if device.registration != RegistrationStatus::Registered {
            return Err(invalid());
        }
        // One collector per device: a second source for the same device would
        // silently replace the verified identity of the first one.
        if let Some(existing) = hierarchy.source_for_device(device_id.as_str()) {
            if existing != &definition.id {
                return Err(invalid());
            }
        } else {
            let mut prospective = hierarchy.plan.clone();
            prospective.sources.push(SourcePlacement {
                source_id: definition.id.clone(),
                site_id: device.device.site_id.clone(),
                device_id: device.device.id.clone(),
                entity_id: definition.entity_id.clone(),
            });
            HierarchyRegistry::new(prospective).map_err(|_| invalid())?;
        }
        let saved = self
            .definitions()
            .map_err(|_| invalid())?
            .into_iter()
            .find(|source| source.id == definition.id);
        let stored = match saved {
            Some(mut current) => {
                if current.origin_class != OriginClass::External
                    || current.entity_id != definition.entity_id
                {
                    return Err(invalid());
                }
                current.metrics.extend(definition.metrics.clone());
                current
                    .required_metrics
                    .extend(definition.required_metrics.clone());
                current
            }
            None => definition.clone(),
        };
        let transaction = self.write_transaction()?;
        transaction.execute_batch("PRAGMA defer_foreign_keys=ON;")?;
        transaction.execute(
            "INSERT INTO core_sources VALUES(?1,?2) ON CONFLICT(source_id) DO UPDATE SET payload_json=excluded.payload_json",
            params![stored.id.as_str(), serde_json::to_string(&stored)?],
        )?;
        transaction.execute(
            "INSERT INTO source_placements VALUES(?1,?2,?3,?4) ON CONFLICT(source_id) DO NOTHING",
            params![
                stored.id.as_str(),
                device.device.site_id.as_str(),
                device.device.id.as_str(),
                stored.entity_id.as_str()
            ],
        )?;
        let origin = transaction
            .query_row(
                "SELECT origin_class FROM source_identities WHERE data_source_id=?1",
                [stored.id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        if origin.is_some_and(|origin| origin != "external") {
            return Err(invalid());
        }
        transaction.execute(
            "INSERT INTO source_identities VALUES(?1,'external') ON CONFLICT(data_source_id) DO NOTHING",
            [stored.id.as_str()],
        )?;
        transaction.commit()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn site() -> SiteId {
        SiteId::new("site-a").unwrap()
    }

    fn store() -> SqliteStore {
        let mut store = SqliteStore::open(":memory:").expect("store");
        let plan = ProvisioningPlan {
            organizations: vec![Organization {
                id: OrganizationId::new("org-a").unwrap(),
                name: "A".into(),
            }],
            infrastructures: vec![Infrastructure {
                id: InfrastructureId::new("infra-a").unwrap(),
                organization_id: OrganizationId::new("org-a").unwrap(),
                name: "Infra".into(),
            }],
            sites: vec![Site {
                id: site(),
                infrastructure_id: InfrastructureId::new("infra-a").unwrap(),
                name: "Site".into(),
            }],
            sources: vec![],
            principals: vec![Principal {
                id: PrincipalId::new("operator").unwrap(),
                name: "operator".into(),
                enabled: true,
            }],
            roles: vec![ReadRole {
                id: RoleId::new("operator").unwrap(),
                name: "operator".into(),
                permissions: [Permission::InventoryManage, Permission::DevicesRead]
                    .into_iter()
                    .collect(),
            }],
            bindings: vec![RoleBinding {
                principal_id: PrincipalId::new("operator").unwrap(),
                role_id: RoleId::new("operator").unwrap(),
                scope: AccessScope::Site(site()),
            }],
            services: vec![],
            legacy_single_infrastructure: false,
        };
        store.provision(plan, &[], None).expect("provisioned");
        for name in ["bridge-1", "bridge-2"] {
            store
                .inventory_admin(
                    InventoryAdministration {
                        principal: PrincipalId::new("operator").unwrap(),
                        changes: vec![InventoryChange::Register {
                            device: DeviceRegistration {
                                id: DeviceId::new(name).unwrap(),
                                display_name: "Hue Bridge".into(),
                                device_type: DeviceType::NetworkDevice,
                                site_id: site(),
                                metadata: DeviceMetadata::default(),
                            },
                        }],
                    },
                    true,
                    1_700_000_000_000,
                    "local_os_operator_uid:1",
                )
                .expect("registered device");
        }
        store
    }

    fn definition(id: &str, entity: &str) -> SourceDefinition {
        SourceDefinition {
            id: DataSourceId::new(id).unwrap(),
            name: "Hue bridge lan".into(),
            entity_id: EntityId::new(entity).unwrap(),
            binding: "https://192.168.1.131:443/api/config".into(),
            simulation_origin_id: String::new(),
            origin_class: OriginClass::External,
            metrics: [(MetricId::new("bridge.name").unwrap(), ValueKind::Text)]
                .into_iter()
                .collect(),
            required_metrics: [MetricId::new("bridge.name").unwrap()]
                .into_iter()
                .collect(),
        }
    }

    #[test]
    fn a_verified_collector_is_placed_on_the_device_it_reads() {
        let mut store = store();
        let device = DeviceId::new("bridge-1").unwrap();
        store
            .register_device_source(&device, &definition("hue-lan", "bridge-1"))
            .expect("the collector is registered");
        // Registering twice keeps the placement and adds the newer metrics.
        let mut extended = definition("hue-lan", "bridge-1");
        extended.metrics.insert(
            MetricId::new("lights.total").unwrap(),
            ValueKind::UnsignedInteger,
        );
        store
            .register_device_source(&device, &extended)
            .expect("the collector is refreshed");
        let hierarchy = store.hierarchy().expect("hierarchy").expect("hierarchy");
        assert_eq!(hierarchy.plan.sources.len(), 1);
        assert_eq!(hierarchy.plan.sources[0].source_id.as_str(), "hue-lan");
        assert_eq!(
            hierarchy.plan.sources[0].device_id.as_str(),
            "bridge-1",
            "the source stays on the registered device"
        );
        let stored = store
            .definitions()
            .expect("definitions")
            .into_iter()
            .find(|source| source.id.as_str() == "hue-lan")
            .expect("the source");
        assert_eq!(stored.origin_class, OriginClass::External);
        assert_eq!(stored.metrics.len(), 2);
    }

    #[test]
    fn a_source_never_moves_onto_another_device_or_another_origin_class() {
        let mut store = store();
        store
            .register_device_source(
                &DeviceId::new("bridge-2").unwrap(),
                &definition("hue-other", "bridge-2"),
            )
            .expect("the second bridge is a device of its own");
        // The same source may not be re-attached to a different device.
        assert!(store
            .register_device_source(
                &DeviceId::new("bridge-1").unwrap(),
                &definition("hue-other", "bridge-1")
            )
            .is_err());
        // A simulation source is not a verified collector of a device.
        let mut simulation = definition("hue-lan", "bridge-1");
        simulation.origin_class = OriginClass::Simulation;
        simulation.simulation_origin_id = "origin".into();
        assert!(store
            .register_device_source(&DeviceId::new("bridge-1").unwrap(), &simulation)
            .is_err());
    }
}

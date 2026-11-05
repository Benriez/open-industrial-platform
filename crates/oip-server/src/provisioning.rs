//! Local operator composition. The typed plan and policy rules live in oip-core.
use crate::config::CoreConfig;
use oip_core::*;
pub fn legacy_plan(c: &CoreConfig) -> Result<ProvisioningPlan, String> {
    let org = OrganizationId::new("legacy-local").map_err(str::to_owned)?;
    let infra = InfrastructureId::new("legacy-installation").map_err(str::to_owned)?;
    let site = SiteId::new("legacy-site").map_err(str::to_owned)?;
    Ok(ProvisioningPlan {
        organizations: vec![Organization {
            id: org.clone(),
            name: "Explicit legacy local organization".into(),
        }],
        infrastructures: vec![Infrastructure {
            id: infra.clone(),
            organization_id: org,
            name: "Legacy single infrastructure".into(),
        }],
        sites: vec![Site {
            id: site.clone(),
            infrastructure_id: infra,
            name: "Legacy local site".into(),
        }],
        sources: c
            .sources
            .iter()
            .enumerate()
            .map(|(i, s)| {
                Ok(SourcePlacement {
                    source_id: DataSourceId::new(&s.id).map_err(|_| "source")?,
                    site_id: site.clone(),
                    device_id: DeviceId::new(if i == 0 {
                        "M-01".into()
                    } else {
                        format!("{}:M-01", s.id)
                    })
                    .map_err(|_| "device")?,
                    entity_id: EntityId::new("M-01").map_err(|_| "entity")?,
                })
            })
            .collect::<Result<Vec<_>, &str>>()
            .map_err(str::to_owned)?,
        principals: vec![Principal {
            id: PrincipalId::new("legacy-local-reader").unwrap(),
            name: "Explicit local development operator".into(),
            enabled: true,
        }],
        roles: vec![ReadRole {
            id: RoleId::new("legacy-read").unwrap(),
            name: "Local read".into(),
            permissions: [
                Permission::HierarchyRead,
                Permission::CoreRead,
                Permission::SourcesRead,
                Permission::DevicesRead,
                Permission::TelemetryRead,
                Permission::EventsRead,
                Permission::OpcuaRead,
            ]
            .into(),
        }],
        bindings: vec![RoleBinding {
            principal_id: PrincipalId::new("legacy-local-reader").unwrap(),
            role_id: RoleId::new("legacy-read").unwrap(),
            scope: AccessScope::Platform,
        }],
        legacy_single_infrastructure: true,
    })
}

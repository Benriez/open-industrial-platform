//! Shared authorized inventory reads. No SQL, network discovery or metadata-derived reachability.
use crate::application_services::ApplicationServices;
use oip_core::*;
impl ApplicationServices {
    pub(crate) fn inventory_read(
        &self,
        ctx: &ExecutionContext,
        q: InventoryQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let output = inventory_projection(
            self.state.hierarchy().as_deref(),
            &self.state.inventory(),
            &self.state.view().sources,
            ctx,
            q,
        )?;
        let CapabilityOutput::Inventory(mut page) = output else {
            return Err(inventory_invalid());
        };
        let registry = self.state.registry();
        let view = self.state.view();
        for item in &mut page.items {
            if let Some(c) = registry
                .connections
                .iter()
                .find(|c| c.device_id == item.record.device.id)
            {
                let source = view.sources.iter().find(|s| s.id == c.source_id);
                item.monitoring_simulated = Some(false);
                item.connectivity = ssh_inventory_connectivity(c, source);
                item.telemetry = if !c.enabled {
                    MonitoringAvailability::CollectorConfigured
                } else {
                    match source.map(|s| s.freshness) {
                        Some(Freshness::Fresh) => MonitoringAvailability::Receiving,
                        Some(Freshness::Stale) => MonitoringAvailability::Stale,
                        _ => MonitoringAvailability::CollectorConfigured,
                    }
                };
            }
        }
        Ok(CapabilityOutput::Inventory(page))
    }
    pub(crate) fn inventory_plan_read(
        &self,
        ctx: &ExecutionContext,
        q: InventoryPlanQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let h = self.state.hierarchy().ok_or_else(denied)?;
        let p = ctx.principal.as_ref().ok_or_else(denied)?;
        validate_inventory_plan(&h, p, &self.state.inventory(), &q.changes)
            .map(CapabilityOutput::InventoryPlan)
    }
}

pub fn inventory_projection(
    hierarchy: Option<&HierarchyRegistry>,
    records: &[InventoryRecord],
    source_health: &[SourceHealth],
    ctx: &ExecutionContext,
    q: InventoryQuery,
) -> Result<CapabilityOutput, CapabilityError> {
    let (offset, limit) = HierarchyQuery {
        offset: q.offset,
        limit: q.limit,
        ..Default::default()
    }
    .bounds()?;
    if q.q.as_ref().is_some_and(|s| s.len() > 256) {
        return Err(inventory_invalid());
    }
    let Some(h) = hierarchy else {
        if q.organization.is_some()
            || q.infrastructure.is_some()
            || q.site.is_some()
            || q.source.is_some()
            || q.id.is_some()
            || q.q.is_some()
            || offset != 0
            || q.include_archived
        {
            return Err(denied());
        }
        return Ok(CapabilityOutput::Inventory(InventoryPage {
            items: vec![],
            offset,
            limit,
            has_more: false,
            status: "No infrastructure configured".into(),
            management_channel: "exclusive_local_operator".into(),
        }));
    };
    let p = ctx.principal.as_ref().ok_or_else(denied)?;
    let id = CapabilityId::InventoryRead;
    if !h
        .plan
        .bindings
        .iter()
        .filter(|b| &b.principal_id == p)
        .any(|b| h.permits(p, id, &b.scope, false))
    {
        return Err(denied());
    }
    for target in [
        q.organization.clone().map(AccessScope::Organization),
        q.infrastructure.clone().map(AccessScope::Infrastructure),
        q.site.clone().map(AccessScope::Site),
        q.source.clone().map(AccessScope::Source),
    ]
    .iter()
    .flatten()
    {
        if !h.permits(p, id, target, true) {
            return Err(inaccessible());
        }
    }
    // Filter consistency is independent of whether any devices exist.
    if let Some(site) = &q.site {
        let (o, i) = device_site_scope(h, site)?;
        if q.organization.as_ref().is_some_and(|v| v != &o)
            || q.infrastructure.as_ref().is_some_and(|v| v != &i)
        {
            return Err(inaccessible());
        }
    }
    if let Some(i) = &q.infrastructure {
        let i = h
            .plan
            .infrastructures
            .iter()
            .find(|v| &v.id == i)
            .ok_or_else(inaccessible)?;
        if q.organization
            .as_ref()
            .is_some_and(|v| v != &i.organization_id)
        {
            return Err(inaccessible());
        }
    }

    let search = q.q.clone().unwrap_or_default().to_lowercase();
    let mut items = Vec::new();
    for row in records.iter() {
        let (organization_id, infrastructure_id) = device_site_scope(h, &row.device.site_id)?;
        let sources = h
            .plan
            .sources
            .iter()
            .filter(|s| s.device_id == row.device.id)
            .map(|s| s.source_id.clone())
            .collect::<Vec<_>>();
        if !h.permits(p, id, &AccessScope::Site(row.device.site_id.clone()), false)
            && !sources
                .iter()
                .any(|s| h.permits(p, id, &AccessScope::Source(s.clone()), false))
        {
            continue;
        }
        if q.organization
            .as_ref()
            .is_some_and(|v| v != &organization_id)
            || q.infrastructure
                .as_ref()
                .is_some_and(|v| v != &infrastructure_id)
            || q.site.as_ref().is_some_and(|v| v != &row.device.site_id)
            || q.source.as_ref().is_some_and(|v| !sources.contains(v))
            || q.id.as_ref().is_some_and(|v| v != &row.device.id)
            || (!q.include_archived && row.registration == RegistrationStatus::Archived)
            || !format!("{} {}", row.device.id, row.device.display_name)
                .to_lowercase()
                .contains(&search)
        {
            continue;
        }
        let health = sources
            .iter()
            .find_map(|id| source_health.iter().find(|s| &s.id == id));
        let connectivity = match health.map(|s| s.reachability) {
            Some(Reachability::Reachable) => InventoryConnectivity::Unknown,
            Some(Reachability::Unreachable) => InventoryConnectivity::Unknown,
            _ => InventoryConnectivity::Unknown,
        };
        let telemetry = match health {
            Some(s) if s.freshness == Freshness::Fresh => MonitoringAvailability::Receiving,
            Some(s) if s.freshness == Freshness::Stale => MonitoringAvailability::Stale,
            Some(_) => MonitoringAvailability::CollectorConfigured,
            None if sources.is_empty() => MonitoringAvailability::NoCollector,
            None => MonitoringAvailability::CollectorConfigured,
        };
        let mut record = row.clone();
        if !h.platform(p, CapabilityId::McpManagementRead) {
            record.registered_by = None
        }
        let monitoring_simulated = if sources.is_empty() {
            Some(false)
        } else {
            health.map(|s| s.simulated)
        };
        items.push(InventoryDevice {
            record,
            organization_id,
            infrastructure_id,
            sources,
            connectivity,
            telemetry,
            health: InventoryHealth::NotEvaluated,
            monitoring_simulated,
        });
    }
    if q.id.is_some() && items.is_empty() {
        return Err(inaccessible());
    }
    let status = if items.is_empty() {
        if q.q.is_some() {
            "No matching devices"
        } else {
            "No devices registered"
        }
    } else if items
        .iter()
        .all(|d| matches!(d.telemetry, MonitoringAvailability::NoCollector))
    {
        "Devices registered · Telemetry unavailable"
    } else {
        "Devices registered · Monitoring configured"
    };
    let has_more = items.len() > offset.saturating_add(limit);
    let items = items.into_iter().skip(offset).take(limit).collect();
    Ok(CapabilityOutput::Inventory(InventoryPage {
        items,
        offset,
        limit,
        has_more,
        status: status.into(),
        management_channel:
            "authenticated_local_operator; online_atomic_writer; offline_cli_exclusive".into(),
    }))
}

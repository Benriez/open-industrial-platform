//! Shared authorized reads of the declared service registry.
//!
//! The registry holds what the **operator declared** in the plan of the instance. The Core
//! measures no service: every record carries the provenance `declared`, and the device of a
//! record is resolved against the inventory — a device that the inventory does not hold leaves
//! the relation **unknown** instead of naming a device that does not exist.
use crate::application_services::ApplicationServices;
use oip_core::*;

impl ApplicationServices {
    pub(crate) fn service_registry_read(
        &self,
        ctx: &ExecutionContext,
        q: ServiceQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        service_projection(
            self.state.hierarchy().as_deref(),
            &self.state.inventory(),
            ctx,
            q,
        )
    }
}

/// The authorized projection of the registry.
pub fn service_projection(
    hierarchy: Option<&HierarchyRegistry>,
    inventory: &[InventoryRecord],
    ctx: &ExecutionContext,
    q: ServiceQuery,
) -> Result<CapabilityOutput, CapabilityError> {
    let (offset, limit) = HierarchyQuery {
        offset: q.offset,
        limit: q.limit,
        ..Default::default()
    }
    .bounds()?;
    if q.q.as_ref().is_some_and(|s| s.len() > 256) {
        return Err(service_invalid());
    }
    let Some(h) = hierarchy else {
        if q.organization.is_some()
            || q.infrastructure.is_some()
            || q.site.is_some()
            || q.id.is_some()
            || q.device.is_some()
            || q.q.is_some()
            || offset != 0
        {
            return Err(denied());
        }
        return Ok(CapabilityOutput::ServiceRegistry(ServicePage {
            items: vec![],
            offset,
            limit,
            has_more: false,
            status: "No infrastructure configured".into(),
            management_channel: "exclusive_local_operator".into(),
        }));
    };
    let p = ctx.principal.as_ref().ok_or_else(denied)?;
    let id = CapabilityId::ServiceRegistryRead;
    if !h
        .plan
        .bindings
        .iter()
        .filter(|b| &b.principal_id == p)
        .any(|b| h.permits(p, id, &b.scope, false))
    {
        return Err(denied());
    }
    // A foreign target is refused identically to a target that does not exist: the
    // answer names neither.
    for target in [
        q.organization.clone().map(AccessScope::Organization),
        q.infrastructure.clone().map(AccessScope::Infrastructure),
        q.site.clone().map(AccessScope::Site),
    ]
    .iter()
    .flatten()
    {
        if !h.permits(p, id, target, true) {
            return Err(inaccessible());
        }
    }
    let search = q.q.clone().unwrap_or_default().to_lowercase();
    let mut items = Vec::new();
    for declaration in h.plan.services.iter() {
        let site = h
            .plan
            .sites
            .iter()
            .find(|s| s.id == declaration.site_id)
            .ok_or_else(inaccessible)?;
        let infrastructure = h
            .plan
            .infrastructures
            .iter()
            .find(|i| i.id == site.infrastructure_id)
            .ok_or_else(inaccessible)?;
        if !h.permits(p, id, &AccessScope::Site(site.id.clone()), false) {
            continue;
        }
        if q.organization
            .as_ref()
            .is_some_and(|v| v != &infrastructure.organization_id)
            || q.infrastructure
                .as_ref()
                .is_some_and(|v| v != &infrastructure.id)
            || q.site.as_ref().is_some_and(|v| v != &site.id)
            || q.id.as_ref().is_some_and(|v| v != &declaration.id)
            || q.device
                .as_ref()
                .is_some_and(|v| declaration.device_id.as_ref() != Some(v))
            || !format!(
                "{} {} {}",
                declaration.id, declaration.name, declaration.kind
            )
            .to_lowercase()
            .contains(&search)
        {
            continue;
        }
        // The relation to a device is resolved against the inventory: a device that the
        // Core does not hold leaves the relation unknown.
        let device = declaration.device_id.as_ref().filter(|d| {
            inventory
                .iter()
                .any(|record| &record.device.id == *d && record.device.site_id == site.id)
        });
        items.push(ServiceRecord {
            service: declaration.clone(),
            organization_id: infrastructure.organization_id.clone(),
            infrastructure_id: infrastructure.id.clone(),
            device_id: device.cloned(),
            origin: ServiceOrigin::Declared,
        });
    }
    if q.id.is_some() && items.is_empty() {
        return Err(inaccessible());
    }
    let status = if items.is_empty() {
        if q.q.is_some() {
            "No matching services"
        } else {
            "No services declared"
        }
    } else {
        "Services declared · Measured by the operator"
    };
    let has_more = items.len() > offset.saturating_add(limit);
    let items = items.into_iter().skip(offset).take(limit).collect();
    Ok(CapabilityOutput::ServiceRegistry(ServicePage {
        items,
        offset,
        limit,
        has_more,
        status: status.into(),
        management_channel:
            "authenticated_local_operator; declared_by_the_operator; read_only".into(),
    }))
}

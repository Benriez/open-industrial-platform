//! Central multi-infrastructure application authorization and read projection.
use super::*;
use std::collections::BTreeSet;
impl ApplicationServices {
    fn tenant_filter(
        &self,
        h: &HierarchyRegistry,
        p: &PrincipalId,
        id: CapabilityId,
        q: &HierarchyQuery,
    ) -> Result<(), CapabilityError> {
        q.bounds()?;
        let scopes = [
            q.organization.clone().map(AccessScope::Organization),
            q.infrastructure.clone().map(AccessScope::Infrastructure),
            q.site.clone().map(AccessScope::Site),
        ];
        for target in scopes.iter().flatten() {
            if !h.permits(p, id, target, true) {
                return Err(inaccessible());
            }
        }
        if let (Some(org), Some(infra)) = (&q.organization, &q.infrastructure) {
            if !h
                .plan
                .infrastructures
                .iter()
                .any(|i| &i.id == infra && &i.organization_id == org)
            {
                return Err(inaccessible());
            }
        }
        if let Some(site) = &q.site {
            let s = h
                .plan
                .sites
                .iter()
                .find(|s| &s.id == site)
                .ok_or_else(inaccessible)?;
            let i = h
                .plan
                .infrastructures
                .iter()
                .find(|i| i.id == s.infrastructure_id)
                .ok_or_else(inaccessible)?;
            if q.infrastructure.as_ref().is_some_and(|x| x != &i.id)
                || q.organization
                    .as_ref()
                    .is_some_and(|x| x != &i.organization_id)
            {
                return Err(inaccessible());
            }
        }
        Ok(())
    }
    pub(crate) fn tenant_sources(
        &self,
        h: &HierarchyRegistry,
        p: &PrincipalId,
        id: CapabilityId,
        q: &SourceQuery,
    ) -> Result<BTreeSet<DataSourceId>, CapabilityError> {
        let filter = HierarchyQuery {
            organization: q.organization.clone(),
            infrastructure: q.infrastructure.clone(),
            site: q.site.clone(),
            offset: q.offset,
            limit: q.limit,
        };
        self.tenant_filter(h, p, id, &filter)?;
        let mut ids = h.allowed_sources(p, id);
        if let Some(source) = &q.source {
            if !ids.contains(source) {
                return Err(inaccessible());
            }
        }
        ids.retain(|s| {
            let l = h.location(s).expect("validated registry");
            q.source.as_ref().is_none_or(|v| v == s)
                && q.organization
                    .as_ref()
                    .is_none_or(|v| v == &l.organization_id)
                && q.infrastructure
                    .as_ref()
                    .is_none_or(|v| v == &l.infrastructure_id)
                && q.site.as_ref().is_none_or(|v| v == &l.site_id)
        });
        Ok(ids)
    }
    pub(super) async fn execute_tenant(
        &self,
        context: &ExecutionContext,
        request: CapabilityRequest,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let id = request.id();
        let principal = context.principal.as_ref().ok_or_else(denied)?;
        let h = self.state.hierarchy().ok_or_else(denied)?;
        if context.actor != principal.as_str()
            || !h
                .plan
                .principals
                .iter()
                .any(|p| &p.id == principal && p.enabled)
        {
            self.audit
                .record(&self.audit_event(context, id, None, false, "denied_identity"))?;
            return Err(denied());
        }
        let source = match &request {
            CapabilityRequest::OpcuaNodesRead(q) if q.source.is_none() => {
                let ids = h.allowed_sources(principal, id);
                if ids.len() == 1 {
                    ids.into_iter().next()
                } else {
                    None
                }
            }
            _ => self.source_for(&request),
        };
        let mut scope = match &request {
            CapabilityRequest::InventoryRead(q) => q
                .source
                .clone()
                .map(AccessScope::Source)
                .or_else(|| q.site.clone().map(AccessScope::Site))
                .or_else(|| q.infrastructure.clone().map(AccessScope::Infrastructure))
                .or_else(|| q.organization.clone().map(AccessScope::Organization)),
            CapabilityRequest::SettingsRead(q) => q.target().ok(),
            CapabilityRequest::McpManagementRead(_) => Some(AccessScope::Platform),
            CapabilityRequest::OrganizationsRead(q)
            | CapabilityRequest::InfrastructuresRead(q)
            | CapabilityRequest::SitesRead(q) => q
                .site
                .clone()
                .map(AccessScope::Site)
                .or_else(|| q.infrastructure.clone().map(AccessScope::Infrastructure))
                .or_else(|| q.organization.clone().map(AccessScope::Organization)),
            CapabilityRequest::SourcesRead(q)
            | CapabilityRequest::EventsRead(q)
            | CapabilityRequest::ObservationsRead(q) => q
                .source
                .clone()
                .map(AccessScope::Source)
                .or_else(|| q.site.clone().map(AccessScope::Site))
                .or_else(|| q.infrastructure.clone().map(AccessScope::Infrastructure))
                .or_else(|| q.organization.clone().map(AccessScope::Organization)),
            _ => source.clone().map(AccessScope::Source),
        };
        if let Some(q) = crate::diagnostic_services::query(&request) {
            scope = q
                .source
                .clone()
                .map(AccessScope::Source)
                .or_else(|| q.site.clone().map(AccessScope::Site))
                .or_else(|| q.infrastructure.clone().map(AccessScope::Infrastructure))
                .or_else(|| q.organization.clone().map(AccessScope::Organization));
        }
        let mut event = self.audit_event(context, id, None, false, "denied");
        let mut interrupted = InterruptedExecution {
            sink: self.audit.clone(),
            event: Some(self.audit_event(
                context,
                id,
                None,
                false,
                "interrupted_before_completion",
            )),
        };
        let inventory_detail_requested =
            matches!(&request,CapabilityRequest::InventoryRead(q) if q.id.is_some());
        let inventory_plan_site = if let CapabilityRequest::InventoryPlanRead(q) = &request {
            q.changes
                .iter()
                .filter_map(|c| match c {
                    InventoryChange::Register { device }
                    | InventoryChange::Update { device, .. } => Some(device.site_id.clone()),
                    InventoryChange::Archive { id, .. } => self
                        .state
                        .inventory()
                        .iter()
                        .find(|r| &r.device.id == id)
                        .map(|r| r.device.site_id.clone()),
                })
                .collect::<std::collections::BTreeSet<_>>()
        } else {
            std::collections::BTreeSet::new()
        };
        let inventory_plan_site = if inventory_plan_site.len() == 1 {
            inventory_plan_site.into_iter().next()
        } else {
            None
        };
        let result = self.run_tenant(&h, principal, context, request).await;
        interrupted.event = None;
        event.authorized = result.is_ok()
            || result.as_ref().is_err_and(|e| {
                matches!(
                    e.kind,
                    CapabilityErrorCode::SourceUnavailable
                        | CapabilityErrorCode::PersistenceUnavailable
                )
            });
        event.outcome = if result.is_ok() {
            "succeeded"
        } else {
            "denied_or_failed"
        }
        .into();
        // Foreign/missing IDs never enter the audit target fields.
        if event.authorized {
            event.scope = scope;
            event.target = event
                .scope
                .as_ref()
                .map_or_else(|| "authorized-projection".into(), |s| format!("{s:?}"));
            if let Ok(CapabilityOutput::Inventory(page)) = &result {
                if inventory_detail_requested {
                    {
                        if let Some(row) = page.items.first() {
                            event.target = row.record.device.id.to_string();
                            event.scope = if h.permits(
                                principal,
                                id,
                                &AccessScope::Site(row.record.device.site_id.clone()),
                                false,
                            ) {
                                Some(AccessScope::Site(row.record.device.site_id.clone()))
                            } else {
                                row.sources
                                    .iter()
                                    .find(|s| {
                                        h.permits(
                                            principal,
                                            id,
                                            &AccessScope::Source((*s).clone()),
                                            false,
                                        )
                                    })
                                    .cloned()
                                    .map(AccessScope::Source)
                            };
                        }
                    }
                }
            }
            if let Ok(CapabilityOutput::Connection(output)) = &result {
                if let Some(plan) = &output.plan {
                    event.target = plan.device_id.to_string();
                    event.scope = Some(AccessScope::Site(plan.site_id.clone()));
                } else if let Some(connection) = &output.connection {
                    event.target = connection.device_id.to_string();
                    event.scope = Some(AccessScope::Source(connection.source_id.clone()));
                }
            }
            if let Ok(CapabilityOutput::InventoryPlan(plan)) = &result {
                event.target = format!("authorized-inventory-plan:{}", plan.actions.len());
                event.scope = inventory_plan_site.map(AccessScope::Site);
            }

            let resolved = if let Ok(CapabilityOutput::Evidence(e)) = &result {
                e.anchor.as_ref().map(|a| a.source.clone())
            } else if id == CapabilityId::EventDetailRead {
                if let Ok(CapabilityOutput::DiagnosticPage(p)) = &result {
                    p.items.first().and_then(|i| match i {
                        DiagnosticItem::Event(e) => Some(e.source.clone()),
                        _ => None,
                    })
                } else {
                    None
                }
            } else {
                None
            };
            if let Some(source) = source.or(resolved) {
                event.hierarchy = h.location(&source).cloned();
                event.target = source.to_string();
            }
        }
        crate::security_audit::confirm_completion(result, self.audit.record(&event))
    }
    async fn run_tenant(
        &self,
        h: &HierarchyRegistry,
        p: &PrincipalId,
        context: &ExecutionContext,
        request: CapabilityRequest,
    ) -> Result<CapabilityOutput, CapabilityError> {
        use CapabilityRequest::*;
        let id = request.id();
        if let HueLightsRead(q) = &request {
            let profile = crate::hue::visible_profile(&self.state, h, p, &q.source)?;
            let can_control = crate::hue::can_control(profile, h, p, &q.source);
            let can_setup = crate::hue::can_setup(profile, h, p, &q.source);
            let lights = crate::hue::list(&self.state, profile).await.map_err(|error| {
                if can_setup && error.code == "HUE_TOKEN_REQUIRED" {
                    CapabilityError::new(error.kind, "HUE_PAIRING_AVAILABLE", "Connect the Hue Bridge in OIP to see its lights")
                } else {
                    error
                }
            })?;
            return Ok(CapabilityOutput::HueLights(HueLights {
                source: q.source.clone(),
                can_control,
                can_setup: can_setup && profile.control_enabled,
                lights,
            }));
        }
        if let HueLightControl(q) = &request {
            let profile = crate::hue::visible_profile(&self.state, h, p, &q.source)?;
            if !crate::hue::can_control(profile, h, p, &q.source) {
                return Err(denied());
            }
            let mut started = self.audit_event(context,id,Some(&q.source),true,"started");
            started.target = format!("{}/lights/{}", q.source, q.light_id);
            self.audit.record(&started)?;
            crate::hue::command(&self.state, profile, q).await?;
            return Ok(CapabilityOutput::HueCommandAccepted {light_id:q.light_id});
        }
        if let HueSetup(q) = &request {
            let profile = crate::hue::visible_profile(&self.state, h, p, &q.source)?;
            if !crate::hue::can_setup(profile, h, p, &q.source)
                || (matches!(q.action, HueSetupAction::SearchLights) && !profile.control_enabled)
            {
                return Err(denied());
            }
            self.audit.record(&self.audit_event(context, id, Some(&q.source), true, "started"))?;
            crate::hue::setup(&self.state, profile, q.action).await?;
            return Ok(CapabilityOutput::HueSetupAccepted { action: q.action });
        }
        if let DeviceConnectionRead(q) = &request {
            return self.connection_read(context, q.clone());
        }
        if let DeviceConnectionConfigure(q) = &request {
            self.audit.record(&self.audit_event(context, id, None, true, "started"))?;
            return self.connection_configure(context, q.clone()).await;
        }
        if let InventoryChange(q) = &request {
            if &q.principal != p {
                return Err(denied());
            }
            if q.changes
                .iter()
                .any(|c| matches!(c, oip_core::InventoryChange::Archive { .. }))
            {
                return Err(CapabilityError::new(
                    CapabilityErrorCode::OperationNotSupported,
                    "OFFLINE_ARCHIVE_REQUIRED",
                    "Archive remains an explicit offline operation",
                ));
            }
            self.audit.record(&self.audit_event(context, id, None, true, "started"))?;
            return self
                .state
                .inventory_online(q.clone())
                .await
                .map(CapabilityOutput::InventoryPlan);
        }
        if let OpcuaNodeWrite(body) = &request {
            let target = AccessScope::Source(body.source.clone());
            if !h.allowed_sources(p, id).contains(&body.source) || !h.permits(p, id, &target, false)
            {
                return Err(inaccessible());
            }
            self.audit.record(&self.audit_event(context, id, Some(&body.source), true, "started"))?;
            return self.run(request).await;
        }
        if id.descriptor().mutating {
            return Err(denied());
        }
        if let InventoryRead(q) = &request {
            return self.inventory_read(context, q.clone());
        }
        if let ServiceRegistryRead(q) = &request {
            return self.service_registry_read(context, q.clone());
        }
        if let InventoryPlanRead(q) = &request {
            return self.inventory_plan_read(context, q.clone());
        }
        if let SettingsRead(q) = &request {
            return self.settings_read(context, q.clone());
        }
        if let McpManagementRead(q) = &request {
            return self.management_read(context, q.clone());
        }
        if matches!(
            request,
            CoreHealthRead
                | CoreLivenessRead
                | CoreReadinessRead
                | QueueRead
                | SystemStatusRead
                | SnapshotRead
        ) {
            if !h.platform(p, id) {
                return Err(denied());
            }
            return self.run(request).await;
        }
        // Check a real target binding before returning any bounded list, including empty lists.
        if !h
            .plan
            .bindings
            .iter()
            .filter(|b| &b.principal_id == p)
            .any(|b| h.permits(p, id, &b.scope, false))
        {
            return Err(denied());
        }
        if let Some(q) = crate::diagnostic_services::query(&request) {
            return self.diagnostic_read(context, id, q.clone()).await;
        }
        match request {
            OrganizationsRead(q) => {
                self.tenant_filter(h, p, id, &q)?;
                let items = h
                    .plan
                    .organizations
                    .iter()
                    .filter(|o| {
                        q.organization.as_ref().is_none_or(|v| v == &o.id)
                            && h.permits(p, id, &AccessScope::Organization(o.id.clone()), true)
                    })
                    .cloned()
                    .collect();
                Ok(CapabilityOutput::Organizations(Page::bounded(items, &q)?))
            }
            InfrastructuresRead(q) => {
                self.tenant_filter(h, p, id, &q)?;
                let items = h
                    .plan
                    .infrastructures
                    .iter()
                    .filter(|i| {
                        q.organization
                            .as_ref()
                            .is_none_or(|v| v == &i.organization_id)
                            && q.infrastructure.as_ref().is_none_or(|v| v == &i.id)
                            && h.permits(p, id, &AccessScope::Infrastructure(i.id.clone()), true)
                    })
                    .cloned()
                    .collect();
                Ok(CapabilityOutput::Infrastructures(Page::bounded(items, &q)?))
            }
            SitesRead(q) => {
                self.tenant_filter(h, p, id, &q)?;
                let items =
                    h.plan
                        .sites
                        .iter()
                        .filter(|s| {
                            q.site.as_ref().is_none_or(|v| v == &s.id)
                                && q.infrastructure
                                    .as_ref()
                                    .is_none_or(|v| v == &s.infrastructure_id)
                                && q.organization.as_ref().is_none_or(|v| {
                                    h.plan.infrastructures.iter().any(|i| {
                                        i.id == s.infrastructure_id && &i.organization_id == v
                                    })
                                })
                                && h.permits(p, id, &AccessScope::Site(s.id.clone()), true)
                        })
                        .cloned()
                        .collect();
                Ok(CapabilityOutput::Sites(Page::bounded(items, &q)?))
            }
            DeviceRead(q) => {
                let Some(source) = h.source_for_device(&q.id) else {
                    let row = self
                        .state
                        .inventory()
                        .iter()
                        .find(|r| r.device.id.as_str() == q.id)
                        .cloned()
                        .ok_or_else(inaccessible)?;
                    if !h.permits(p, id, &AccessScope::Site(row.device.site_id.clone()), false) {
                        return Err(inaccessible());
                    }
                    return self.run(DeviceRead(q)).await;
                };
                if !h.permits(p, id, &AccessScope::Source(source.clone()), false) {
                    return Err(inaccessible());
                }
                self.run(DeviceRead(q)).await
            }
            OpcuaNodesRead(mut q) => {
                let allowed = h.allowed_sources(p, id);
                let source = match q.source.clone() {
                    Some(s) if allowed.contains(&s) => s,
                    Some(_) => return Err(inaccessible()),
                    None if allowed.len() == 1 => allowed.iter().next().unwrap().clone(),
                    _ => {
                        return Err(CapabilityError::new(
                            CapabilityErrorCode::InvalidInput,
                            "SOURCE_REQUIRED",
                            "Select an authorized source",
                        ));
                    }
                };
                HierarchyQuery {
                    offset: q.offset,
                    limit: q.limit,
                    ..Default::default()
                }
                .bounds()?;
                if q.folder.as_ref().is_some_and(|v| v.len() > 256) {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::InvalidInput,
                        "INVALID_QUERY",
                        "Query exceeds limit",
                    ));
                }
                q.source = Some(source);
                self.nodes(q).await.map(CapabilityOutput::Nodes)
            }
            OpcuaNodeWrite(_) => Err(inaccessible()),
            SourcesRead(q) => {
                let allowed = self.tenant_sources(h, p, id, &q)?;
                let (o, l) = source_bounds(&q)?;
                let items = self
                    .state
                    .view()
                    .sources
                    .into_iter()
                    .filter(|s| allowed.contains(&s.id))
                    .skip(o)
                    .take(l)
                    .collect();
                Ok(CapabilityOutput::Sources(items))
            }
            ObservationsRead(q) => {
                let allowed = self.tenant_sources(h, p, id, &q)?;
                let (o, l) = source_bounds(&q)?;
                let items = self
                    .state
                    .snapshot()
                    .map_err(storage)?
                    .metrics
                    .into_iter()
                    .filter(|v| allowed.contains(&v.data_source_id))
                    .skip(o)
                    .take(l)
                    .collect();
                Ok(CapabilityOutput::Observations(items))
            }
            DevicesRead(q) => {
                let allowed = h.allowed_sources(p, id);
                if q.source.as_ref().is_some_and(|s| !allowed.contains(s)) {
                    return Err(inaccessible());
                }
                let CapabilityOutput::Devices(mut items) = self.run(DevicesRead(q)).await? else {
                    return Err(denied());
                };
                items.retain(|d| {
                    d.data_source_id
                        .as_ref()
                        .is_some_and(|s| allowed.contains(s))
                        || self
                            .state
                            .inventory()
                            .iter()
                            .find(|r| r.device.id.as_str() == d.id)
                            .is_some_and(|r| {
                                h.permits(
                                    p,
                                    id,
                                    &AccessScope::Site(r.device.site_id.clone()),
                                    false,
                                )
                            })
                });
                Ok(CapabilityOutput::Devices(items))
            }
            EventsRead(q) => {
                let allowed = self.tenant_sources(h, p, id, &q)?;
                let (o, l) = source_bounds(&q)?;
                let records: Vec<_> = self
                    .state
                    .view()
                    .events
                    .into_iter()
                    .filter(|e| allowed.contains(&e.context.data_source_id))
                    .skip(o)
                    .take(l)
                    .collect();
                Ok(CapabilityOutput::Events(EventsResponse {
                    collection_events: records.iter().map(|r| r.event.clone()).collect(),
                    records,
                    incidents: Vec::new(),
                    diagnosis_history_status: "not_implemented".into(),
                    replay_supported: false,
                    resync_required: true,
                }))
            }
            ScopedSnapshotRead => {
                let allowed = h.allowed_sources(p, id);
                let s = self.state.snapshot().map_err(storage)?;
                let inventory = self.state.inventory();
                let connections = self.state.connections();
                let topology = observed_network_links(&inventory, &connections, &allowed, now_ms());
                Ok(CapabilityOutput::ScopedSnapshot(ScopedSnapshot {
                    sources: s
                        .sources
                        .into_iter()
                        .filter(|v| allowed.contains(&v.id))
                        .collect(),
                    devices: s
                        .devices
                        .into_iter()
                        .filter(|v| {
                            v.data_source_id
                                .as_ref()
                                .is_some_and(|s| allowed.contains(s))
                                || self
                                    .state
                                    .inventory()
                                    .iter()
                                    .find(|r| r.device.id.as_str() == v.id)
                                    .is_some_and(|r| {
                                        h.permits(
                                            p,
                                            id,
                                            &AccessScope::Site(r.device.site_id.clone()),
                                            false,
                                        )
                                    })
                        })
                        .collect(),
                    observations: s
                        .metrics
                        .into_iter()
                        .filter(|v| allowed.contains(&v.data_source_id))
                        .collect(),
                    events: self
                        .state
                        .view()
                        .events
                        .into_iter()
                        .filter(|v| allowed.contains(&v.context.data_source_id))
                        .take(100)
                        .collect(),
                    locations: allowed
                        .iter()
                        .filter_map(|s| h.location(s).cloned())
                        .collect(),
                    topology,
                    resync_required: true,
                    replay_supported: false,
                }))
            }
            _ => Err(denied()),
        }
    }
}

fn observed_network_links(
    inventory: &[InventoryRecord],
    connections: &[DeviceConnectionRecord],
    allowed_sources: &BTreeSet<DataSourceId>,
    now: i64,
) -> Vec<Link> {
    let mut links = Vec::new();
    let mut seen = BTreeSet::new();
    for observer in connections.iter().filter(|connection| {
        allowed_sources.contains(&connection.source_id)
            && connection.enabled
            && connection
                .last_success_ms
                .is_some_and(|at| now.saturating_sub(at) <= 300_000)
    }) {
        for neighbor in observer.identity.neighbors.iter().filter(|neighbor| {
            matches!(
                neighbor.state.as_str(),
                "reachable" | "stale" | "delay" | "probe"
            )
        }) {
            for target in connections.iter().filter(|candidate| {
                candidate.device_id != observer.device_id
                    && allowed_sources.contains(&candidate.source_id)
                    && candidate.enabled
                    && candidate
                        .last_success_ms
                        .is_some_and(|at| now.saturating_sub(at) <= 300_000)
                    && candidate.identity.interfaces.iter().any(|interface| {
                        interface.addresses.iter().any(|address| {
                            address.split('/').next() == Some(neighbor.address.as_str())
                        })
                    })
            }) {
                let observer_site = inventory
                    .iter()
                    .find(|record| record.device.id == observer.device_id)
                    .map(|r| &r.device.site_id);
                let target_site = inventory
                    .iter()
                    .find(|record| record.device.id == target.device_id)
                    .map(|r| &r.device.site_id);
                if observer_site != target_site || observer_site.is_none() {
                    continue;
                }
                let (from, to) = if observer.device_id < target.device_id {
                    (observer.device_id.to_string(), target.device_id.to_string())
                } else {
                    (target.device_id.to_string(), observer.device_id.to_string())
                };
                if !seen.insert((from.clone(), to.clone())) {
                    continue;
                }
                links.push(Link {
                    from,
                    to,
                    transport: "LAN kernel neighbor".into(),
                    latency_ms: None,
                    packet_loss_percent: None,
                    status: if neighbor.state == "reachable" {
                        "reachable"
                    } else {
                        "observed"
                    }
                    .into(),
                    simulated: false,
                });
            }
        }
    }
    links
}

fn source_bounds(q: &SourceQuery) -> Result<(usize, usize), CapabilityError> {
    HierarchyQuery {
        offset: q.offset,
        limit: Some(q.limit.unwrap_or(100)),
        ..Default::default()
    }
    .bounds()
}

#[cfg(test)]
mod topology_tests {
    use super::observed_network_links;
    use oip_core::*;
    use std::collections::BTreeSet;

    fn host(addresses: &[&str], neighbors: &[(&str, &str)]) -> HostInformation {
        HostInformation {
            hostname: "fixture".into(),
            operating_system: "Linux".into(),
            architecture: "x86_64".into(),
            cpu_info: None,
            model: None,
            stable_host_id_sha256: None,
            memory_total_bytes: None,
            memory_used_bytes: None,
            gpu_model: None,
            gpu_utilization_percent: None,
            gpu_temperature_c: None,
            cpu_temperature_c: None,
            soc_temperature_c: None,
            memory_used_percent: None,
            uptime_seconds: None,
            disks: vec![],
            interfaces: vec![NetworkInterfaceInformation {
                name: "eth0".into(),
                addresses: addresses.iter().map(|address| (*address).into()).collect(),
            }],
            neighbors: neighbors
                .iter()
                .map(|(address, state)| NetworkNeighborInformation {
                    address: (*address).into(),
                    link_address: None,
                    state: (*state).into(),
                })
                .collect(),
            captured_at_ms: 10_000,
            unavailable: vec![],
            provenance: "ssh_verified_host_report".into(),
        }
    }

    fn connection(
        device: &str,
        source: &str,
        identity: HostInformation,
        last_success_ms: i64,
    ) -> DeviceConnectionRecord {
        DeviceConnectionRecord {
            device_id: DeviceId::new(device).unwrap(),
            source_id: DataSourceId::new(source).unwrap(),
            authorized_principal: PrincipalId::new("operator").unwrap(),
            endpoint: SshEndpoint {
                host: "192.168.1.10".into(),
                port: 22,
                user: "operator".into(),
                identity_profile: "fixture".into(),
                alias: None,
            },
            host_key: "fixture-key".into(),
            fingerprint: "SHA256:fixture".into(),
            identity,
            verified_at_ms: 10_000,
            enabled: true,
            poll_seconds: 30,
            revision: 1,
            last_attempt_ms: Some(last_success_ms),
            last_success_ms: Some(last_success_ms),
            last_error: None,
        }
    }

    fn inventory(device: &str, site: &str) -> InventoryRecord {
        InventoryRecord {
            device: DeviceRegistration {
                id: DeviceId::new(device).unwrap(),
                display_name: device.into(),
                device_type: DeviceType::Server,
                site_id: SiteId::new(site).unwrap(),
                metadata: DeviceMetadata::default(),
            },
            registration: RegistrationStatus::Registered,
            origin: InventoryOrigin::ManualOperator,
            created_ms: None,
            updated_ms: None,
            registered_by: None,
            revision: 1,
        }
    }

    #[test]
    fn projects_only_fresh_authorized_same_site_exact_ip_neighbors() {
        let inventory = vec![
            inventory("router", "home"),
            inventory("pc", "home"),
            inventory("remote", "other"),
        ];
        let router = connection(
            "router",
            "router-source",
            host(
                &["192.168.1.1/24"],
                &[
                    ("192.168.1.20", "reachable"),
                    ("192.168.1.30", "stale"),
                    ("192.168.1.99", "FAILED"),
                ],
            ),
            9_900,
        );
        let pc = connection("pc", "pc-source", host(&["192.168.1.20/24"], &[]), 9_950);
        let remote = connection(
            "remote",
            "remote-source",
            host(&["192.168.1.30/24"], &[]),
            9_950,
        );
        let connections = vec![router, pc, remote];
        let allowed = ["router-source", "pc-source", "remote-source"]
            .into_iter()
            .map(|source| DataSourceId::new(source).unwrap())
            .collect::<BTreeSet<_>>();

        let links = observed_network_links(&inventory, &connections, &allowed, 10_000);
        assert_eq!(
            links.len(),
            1,
            "cross-site and FAILED neighbor evidence must not become links"
        );
        assert_eq!(links[0].from, "pc");
        assert_eq!(links[0].to, "router");
        assert_eq!(links[0].transport, "LAN kernel neighbor");
        assert_eq!(links[0].status, "reachable");
        assert!(!links[0].simulated);
        assert_eq!(links[0].latency_ms, None);
        assert_eq!(links[0].packet_loss_percent, None);

        let only_router = [DataSourceId::new("router-source").unwrap()]
            .into_iter()
            .collect();
        assert!(
            observed_network_links(&inventory, &connections, &only_router, 10_000).is_empty(),
            "a neighbor does not reveal a target whose source is unauthorized"
        );

        let stale = connections
            .iter()
            .cloned()
            .map(|mut connection| {
                connection.last_success_ms = Some(1);
                connection
            })
            .collect::<Vec<_>>();
        assert!(
            observed_network_links(&inventory, &stale, &allowed, 400_000).is_empty(),
            "stale host reports must not contribute topology"
        );
    }
}

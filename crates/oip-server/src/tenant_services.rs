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
    fn tenant_sources(
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
        let h = self.state.hierarchy.as_ref().ok_or_else(denied)?;
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
        let scope = match &request {
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
        let result = self.run_tenant(h, principal, request).await;
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
            if let Some(source) = source {
                event.hierarchy = h.location(&source).cloned();
                event.target = source.to_string();
            }
        }
        self.audit.record(&event)?;
        result
    }
    async fn run_tenant(
        &self,
        h: &HierarchyRegistry,
        p: &PrincipalId,
        request: CapabilityRequest,
    ) -> Result<CapabilityOutput, CapabilityError> {
        use CapabilityRequest::*;
        let id = request.id();
        if id.descriptor().mutating {
            return Err(denied());
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
                let source = h.source_for_device(&q.id).ok_or_else(inaccessible)?;
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
                        ))
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
                    resync_required: true,
                    replay_supported: false,
                }))
            }
            _ => Err(denied()),
        }
    }
}
fn source_bounds(q: &SourceQuery) -> Result<(usize, usize), CapabilityError> {
    HierarchyQuery {
        offset: q.offset,
        limit: Some(q.limit.unwrap_or(100)),
        ..Default::default()
    }
    .bounds()
}

//! Typed inventory and read authorization. No protocol, SQL, or transport types.
use crate::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
macro_rules! hierarchy_id {
    ($name:ident,$max:literal) => {
        #[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, Serialize)]
        #[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
        #[serde(transparent)]
        pub struct $name(
            #[cfg_attr(
                        feature = "schemas",
                        schemars(length(min = 1, max = $max), regex(pattern = "^[A-Za-z0-9_.:-]+$"))
                    )]
            String,
        );
        impl $name {
            pub fn new(v: impl Into<String>) -> Result<Self, &'static str> {
                let v = v.into();
                if v.is_empty()
                    || v.len() > $max
                    || !v
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
                {
                    return Err("invalid canonical identity");
                }
                Ok(Self(v))
            }
            pub fn as_str(&self) -> &str {
                &self.0
            }
        }
        impl std::fmt::Display for $name {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str(&self.0)
            }
        }
        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
                Self::new(String::deserialize(d)?).map_err(serde::de::Error::custom)
            }
        }
    };
}
hierarchy_id!(OrganizationId, 128);
hierarchy_id!(InfrastructureId, 128);
hierarchy_id!(SiteId, 128);
hierarchy_id!(DeviceId, 256);
hierarchy_id!(PrincipalId, 128);
hierarchy_id!(RoleId, 128);
hierarchy_id!(ServiceId, 128);
/// Source identity retains the existing canonical registry type, never a tenant prefix.
pub type SourceId = DataSourceId;
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct Organization {
    pub id: OrganizationId,
    pub name: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct Infrastructure {
    pub id: InfrastructureId,
    pub organization_id: OrganizationId,
    pub name: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct Site {
    pub id: SiteId,
    pub infrastructure_id: InfrastructureId,
    pub name: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct SourcePlacement {
    pub source_id: SourceId,
    pub site_id: SiteId,
    pub device_id: DeviceId,
    pub entity_id: EntityId,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Principal {
    pub id: PrincipalId,
    pub name: String,
    pub enabled: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadRole {
    pub id: RoleId,
    pub name: String,
    pub permissions: BTreeSet<Permission>,
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(
    tag = "kind",
    content = "id",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum AccessScope {
    Platform,
    Organization(OrganizationId),
    Infrastructure(InfrastructureId),
    Site(SiteId),
    Source(SourceId),
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RoleBinding {
    pub principal_id: PrincipalId,
    pub role_id: RoleId,
    pub scope: AccessScope,
}
/// Typed offline management boundary. Not an externally enabled mutation.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProvisioningPlan {
    pub organizations: Vec<Organization>,
    pub infrastructures: Vec<Infrastructure>,
    pub sites: Vec<Site>,
    pub sources: Vec<SourcePlacement>,
    pub principals: Vec<Principal>,
    pub roles: Vec<ReadRole>,
    pub bindings: Vec<RoleBinding>,
    /// The services that the operator declares for the infrastructure.
    ///
    /// The Core measures no service: every record of the registry carries the provenance
    /// `declared`. A plan without this section is a plan without services — the section is
    /// optional, so every plan of an earlier era stays valid.
    #[serde(default)]
    pub services: Vec<ServiceDeclaration>,
    #[serde(default)]
    pub legacy_single_infrastructure: bool,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct HierarchyLocation {
    pub organization_id: OrganizationId,
    pub infrastructure_id: InfrastructureId,
    pub site_id: SiteId,
    pub source_id: SourceId,
}
/// Local administration, with no source, role, or principal supplied by the caller.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum OrganizationSetupRequest {
    Status,
    Create {
        request_id: String,
        organization: String,
        infrastructure: String,
        site: String,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum OrganizationSetupResult {
    Status { can_create: bool },
    Created {
        organization_id: OrganizationId,
        infrastructure_id: InfrastructureId,
        site_id: SiteId,
    },
}

pub fn organization_setup_invalid() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::InvalidInput,
        "ORGANIZATION_SETUP_INVALID",
        "Enter a valid name for the organization, infrastructure and site. Review and retry if the request already exists or the hierarchy is full.",
    )
}

#[derive(Clone, Debug)]
pub struct HierarchyRegistry {
    pub plan: ProvisioningPlan,
    locations: BTreeMap<SourceId, HierarchyLocation>,
    devices: BTreeMap<DeviceId, SourceId>,
}
pub fn inaccessible() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::ResourceNotFound,
        "RESOURCE_NOT_ACCESSIBLE",
        "Resource is not accessible",
    )
}
pub fn denied() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::PermissionDenied,
        "PERMISSION_DENIED",
        "Capability is not authorized",
    )
}
impl HierarchyRegistry {
    pub fn can_create_organization(&self, principal: &PrincipalId) -> bool {
        !self.plan.legacy_single_infrastructure
            && self.plan.bindings.iter().any(|binding| {
                &binding.principal_id == principal
                    && matches!(&binding.scope, AccessScope::Organization(_))
                    && self.permits(principal, CapabilityId::OrganizationSetup, &binding.scope, false)
            })
    }

    pub fn new(mut plan: ProvisioningPlan) -> Result<Self, &'static str> {
        if plan.organizations.is_empty()
            || plan.organizations.len() > 64
            || plan.infrastructures.len() > 128
            || plan.sites.len() > 256
            || plan.sources.len() > 32
            || plan.principals.is_empty()
            || plan.principals.len() > 64
            || plan.roles.len() > 64
            || plan.bindings.len() > 512
            || plan.services.len() > 256
        {
            return Err("invalid bounded hierarchy");
        }
        fn unique<'a, T: Ord + 'a>(values: impl Iterator<Item = &'a T>) -> bool {
            let v: Vec<_> = values.collect();
            v.iter().copied().collect::<BTreeSet<_>>().len() == v.len()
        }
        if !unique(plan.organizations.iter().map(|v| &v.id))
            || !unique(plan.infrastructures.iter().map(|v| &v.id))
            || !unique(plan.sites.iter().map(|v| &v.id))
            || !unique(plan.sources.iter().map(|v| &v.source_id))
            || !unique(plan.sources.iter().map(|v| &v.device_id))
            || !unique(plan.principals.iter().map(|v| &v.id))
            || !unique(plan.roles.iter().map(|v| &v.id))
            || !unique(plan.services.iter().map(|v| &v.id))
        {
            return Err("duplicate hierarchy identity");
        }
        for name in plan
            .organizations
            .iter()
            .map(|v| &v.name)
            .chain(plan.infrastructures.iter().map(|v| &v.name))
            .chain(plan.sites.iter().map(|v| &v.name))
            .chain(plan.principals.iter().map(|v| &v.name))
            .chain(plan.roles.iter().map(|v| &v.name))
        {
            if name.trim().is_empty() || name.len() > 256 || name.chars().any(char::is_control) {
                return Err("invalid display name");
            }
        }
        for i in &plan.infrastructures {
            if !plan.organizations.iter().any(|o| o.id == i.organization_id) {
                return Err("infrastructure parent missing");
            }
        }
        for s in &plan.sites {
            if !plan
                .infrastructures
                .iter()
                .any(|i| i.id == s.infrastructure_id)
            {
                return Err("site parent missing");
            }
        }
        for service in &plan.services {
            validate_service_declaration(service, &plan.sites)?;
        }
        let mut locations = BTreeMap::new();
        let mut devices = BTreeMap::new();
        for s in &plan.sources {
            if s.source_id.as_str().is_empty()
                || s.source_id.as_str().len() > 128
                || !s
                    .source_id
                    .as_str()
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
                || s.entity_id.as_str().is_empty()
                || s.entity_id.as_str().len() > 128
            {
                return Err("invalid source/entity identity");
            }
            let site = plan
                .sites
                .iter()
                .find(|x| x.id == s.site_id)
                .ok_or("source site missing")?;
            let infra = plan
                .infrastructures
                .iter()
                .find(|i| i.id == site.infrastructure_id)
                .ok_or("infrastructure missing")?;
            locations.insert(
                s.source_id.clone(),
                HierarchyLocation {
                    organization_id: infra.organization_id.clone(),
                    infrastructure_id: infra.id.clone(),
                    site_id: site.id.clone(),
                    source_id: s.source_id.clone(),
                },
            );
            devices.insert(s.device_id.clone(), s.source_id.clone());
        }
        plan.organizations.sort_by(|a, b| a.id.cmp(&b.id));
        plan.infrastructures.sort_by(|a, b| a.id.cmp(&b.id));
        plan.sites.sort_by(|a, b| a.id.cmp(&b.id));
        plan.sources.sort_by(|a, b| a.source_id.cmp(&b.source_id));
        plan.principals.sort_by(|a, b| a.id.cmp(&b.id));
        plan.roles.sort_by(|a, b| a.id.cmp(&b.id));
        plan.bindings.sort_by(|a, b| {
            (&a.principal_id, &a.role_id, &a.scope).cmp(&(&b.principal_id, &b.role_id, &b.scope))
        });
        plan.services.sort_by(|a, b| a.id.cmp(&b.id));
        let registry = Self {
            plan,
            locations,
            devices,
        };
        if registry.plan.roles.iter().any(|r| {
            r.permissions.is_empty() || r.permissions.contains(&Permission::SimulationControl)
        }) {
            return Err("only explicit read roles are supported");
        }
        for b in &registry.plan.bindings {
            if !registry
                .plan
                .principals
                .iter()
                .any(|p| p.id == b.principal_id)
                || !registry.plan.roles.iter().any(|r| r.id == b.role_id)
                || !registry.scope_exists(&b.scope)
            {
                return Err("invalid policy binding");
            }
        }
        if registry.plan.legacy_single_infrastructure
            && (registry.plan.organizations.len() != 1
                || registry.plan.infrastructures.len() != 1
                || registry.plan.sites.len() != 1)
        {
            return Err("legacy context must be a single infrastructure/site");
        }
        Ok(registry)
    }
    pub fn location(&self, id: &SourceId) -> Option<&HierarchyLocation> {
        self.locations.get(id)
    }
    pub fn source_for_device(&self, id: &str) -> Option<&SourceId> {
        self.devices.get(&DeviceId::new(id).ok()?)
    }
    pub fn placement(&self, id: &SourceId) -> Option<&SourcePlacement> {
        self.plan.sources.iter().find(|s| &s.source_id == id)
    }
    pub fn scope_exists(&self, scope: &AccessScope) -> bool {
        match scope {
            AccessScope::Platform => true,
            AccessScope::Organization(id) => self.plan.organizations.iter().any(|o| &o.id == id),
            AccessScope::Infrastructure(id) => {
                self.plan.infrastructures.iter().any(|o| &o.id == id)
            }
            AccessScope::Site(id) => self.plan.sites.iter().any(|o| &o.id == id),
            AccessScope::Source(id) => self.locations.contains_key(id),
        }
    }
    fn ancestor(&self, ancestor: &AccessScope, child: &AccessScope) -> bool {
        if ancestor == child || matches!(ancestor, AccessScope::Platform) {
            return true;
        }
        match child {
            AccessScope::Source(s) => self.location(s).is_some_and(|l| match ancestor {
                AccessScope::Organization(v) => v == &l.organization_id,
                AccessScope::Infrastructure(v) => v == &l.infrastructure_id,
                AccessScope::Site(v) => v == &l.site_id,
                _ => false,
            }),
            AccessScope::Site(s) => self
                .plan
                .sites
                .iter()
                .find(|v| &v.id == s)
                .is_some_and(|v| {
                    self.ancestor(
                        ancestor,
                        &AccessScope::Infrastructure(v.infrastructure_id.clone()),
                    )
                }),
            AccessScope::Infrastructure(i) => self
                .plan
                .infrastructures
                .iter()
                .find(|v| &v.id == i)
                .is_some_and(|v| {
                    self.ancestor(
                        ancestor,
                        &AccessScope::Organization(v.organization_id.clone()),
                    )
                }),
            _ => false,
        }
    }
    /// Permissions are unioned ONLY after target scope resolution, never independently.
    pub fn permits(
        &self,
        principal: &PrincipalId,
        id: CapabilityId,
        target: &AccessScope,
        parent_discovery: bool,
    ) -> bool {
        if !self
            .plan
            .principals
            .iter()
            .any(|p| &p.id == principal && p.enabled)
            || !self.scope_exists(target)
        {
            return false;
        }
        let mut permissions = BTreeSet::new();
        for binding in self
            .plan
            .bindings
            .iter()
            .filter(|b| &b.principal_id == principal)
        {
            if self.ancestor(&binding.scope, target)
                || (parent_discovery && self.ancestor(target, &binding.scope))
            {
                if let Some(role) = self.plan.roles.iter().find(|r| r.id == binding.role_id) {
                    permissions.extend(role.permissions.iter().copied());
                }
            }
        }
        id.descriptor()
            .permission
            .iter()
            .all(|p| permissions.contains(p))
    }
    pub fn allowed_sources(&self, p: &PrincipalId, id: CapabilityId) -> BTreeSet<SourceId> {
        self.locations
            .keys()
            .filter(|s| self.permits(p, id, &AccessScope::Source((*s).clone()), false))
            .cloned()
            .collect()
    }
    pub fn platform(&self, p: &PrincipalId, id: CapabilityId) -> bool {
        self.permits(p, id, &AccessScope::Platform, false)
    }
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct HierarchyQuery {
    pub organization: Option<OrganizationId>,
    pub infrastructure: Option<InfrastructureId>,
    pub site: Option<SiteId>,
    pub offset: Option<usize>,
    pub limit: Option<usize>,
}
impl HierarchyQuery {
    pub fn bounds(&self) -> Result<(usize, usize), CapabilityError> {
        let o = self.offset.unwrap_or(0);
        let l = self.limit.unwrap_or(40);
        if o > 1_000_000 || !(1..=100).contains(&l) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "INVALID_PAGE",
                "Invalid bounded page",
            ));
        }
        Ok((o, l))
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Page<T> {
    pub items: Vec<T>,
    pub offset: usize,
    pub limit: usize,
    pub has_more: bool,
}
impl<T> Page<T> {
    pub fn bounded(mut all: Vec<T>, query: &HierarchyQuery) -> Result<Self, CapabilityError> {
        let (offset, limit) = query.bounds()?;
        let has_more = all.len() > offset.saturating_add(limit);
        let items = all.drain(..).skip(offset).take(limit).collect();
        Ok(Self {
            items,
            offset,
            limit,
            has_more,
        })
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ScopedSnapshot {
    pub sources: Vec<SourceHealth>,
    pub devices: Vec<Device>,
    pub observations: Vec<ObservationEnvelope>,
    pub events: Vec<EventRecord>,
    pub locations: Vec<HierarchyLocation>,
    /// Observed links between authorized devices. Empty means no usable
    /// neighbor evidence was available; it is not a global network census.
    #[serde(default)]
    pub topology: Vec<Link>,
    pub resync_required: bool,
    pub replay_supported: bool,
}

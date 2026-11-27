use crate::async_opcua::mapping::{
    data_value_to_observation, datetime_to_timestamp, external_datetime_is_valid,
    metric_value_to_variant, variant_to_metric_value, SimulationMetadata,
};
use crate::endpoint::validate_client_endpoint;
use crate::{
    AdapterError, BrowseEntry, ClientEvent, ClientOptions, DataGap, EndpointInfo, FreshnessPolicy,
    ReadOnlyOpcUaAdapter,
};
use async_trait::async_trait;
use futures::StreamExt;
use oip_core::{MetricId, MetricValue, Timestamp};
use opcua::client::{ClientBuilder, DataChangeCallback, IdentityToken, Session, SessionPollResult};
use opcua::crypto::SecurityPolicy;
use opcua::types::{
    AttributeId, BrowseDescription, BrowseDescriptionResultMask, BrowseDirection, DataValue,
    MessageSecurityMode, MonitoredItemCreateRequest, NodeClassMask, NodeId, ReadValueId,
    ReferenceTypeId, StatusCode, TimestampsToReturn, UserTokenPolicy, UserTokenType, Variant,
    WriteValue,
};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::mpsc;
use tokio::task::JoinHandle;

/// Capacity of the observation event channel.
const EVENT_CHANNEL_CAPACITY: usize = 1_024;
const MAX_SELECTED_POINTS: usize = 16;
const MAX_BROWSE_DEPTH: usize = 24;
const MAX_BROWSE_REQUESTS: usize = 5_200;
const SELECTED_READ_TIMEOUT: Duration = Duration::from_secs(5);

/// Canonicalize a persistent point identifier without accepting a volatile
/// namespace index. The server's NamespaceArray is consulted separately.
pub fn canonical_node_identifier(value: &str) -> Option<String> {
    if value.len() > 256 || value.starts_with("ns=") || value.chars().any(char::is_control) {
        return None;
    }
    value.parse::<NodeId>().ok().map(|id| id.to_string())
}

// The guard also covers connect failures after spawning but before returning Self.
struct OwnedEventTask(JoinHandle<()>);
impl Drop for OwnedEventTask {
    fn drop(&mut self) {
        self.0.abort();
    }
}

pub struct AsyncOpcUaClient {
    session: Arc<Session>,
    namespace: u16,
    endpoints: Vec<EndpointInfo>,
    state: CollectionState,
    subscribed_metrics: Arc<Mutex<Vec<MetricId>>>,
    max_browse_nodes: usize,
    read_only: bool,
    explicit_secure_server: bool,
    requests: tokio::sync::Semaphore,
    events: tokio::sync::Mutex<Option<mpsc::Receiver<ClientEvent>>>,
    event_task: OwnedEventTask,
    reported_drops: AtomicU64,
}

impl AsyncOpcUaClient {
    pub async fn connect(options: &ClientOptions) -> Result<Self, AdapterError> {
        tokio::time::timeout(Duration::from_secs(15), Self::connect_inner(options))
            .await
            .map_err(|_| {
                AdapterError::Connection(
                    "OPC UA connection/security handshake timed out".to_owned(),
                )
            })?
    }

    /// Writes one typed value to the server node. The caller must already
    /// restrict this operation to a browsed node whose UserAccessLevel grants
    /// CurrentWrite; the server remains the final authority and rejects any
    /// node or type that it does not permit.
    pub async fn write_node(&self, node_id: &str, value: &MetricValue) -> Result<(), AdapterError> {
        if self.read_only {
            return Err(AdapterError::Protocol("OPC-UA client is read-only".into()));
        }
        let node = node_id
            .parse::<NodeId>()
            .map_err(|_| AdapterError::InvalidValue("invalid OPC-UA node id".to_owned()))?;
        if let MetricValue::Float(value) = value {
            if !value.is_finite() {
                return Err(AdapterError::InvalidValue(
                    "non-finite floating point values are forbidden".to_owned(),
                ));
            }
        }
        if let MetricValue::Text(value) = value {
            if value.len() > 256 || value.contains('\0') {
                return Err(AdapterError::InvalidValue(
                    "text write exceeds the bounded value limit".to_owned(),
                ));
            }
        }
        let result = self
            .session
            .write(&[WriteValue::value_attr(node, metric_value_to_variant(value))])
            .await
            .map_err(|error| AdapterError::Protocol(error.to_string()))?;
        match result.first() {
            Some(status) if status.is_good() => Ok(()),
            Some(status) => Err(AdapterError::Protocol(format!(
                "OPC-UA server rejected write: {status}"
            ))),
            None => Err(AdapterError::Protocol(
                "OPC-UA server returned no write status".to_owned(),
            )),
        }
    }

    /// Resolve stable identifiers against the authenticated session's namespace
    /// array. Re-run after each connection and never persist the resulting index.
    pub async fn resolve_selected_nodes(
        &self,
        namespace_uri: &str,
        identifiers: &[String],
    ) -> Result<Vec<String>, AdapterError> {
        self.check_selection(identifiers.len())?;
        let mut result = self
            .read_batch(&[ReadValueId::from(NodeId::new(0, 2255u32))])
            .await?;
        let value = result.pop().expect("read_batch checked result count");
        let Some(Variant::Array(namespaces)) = value.value.as_ref() else {
            return Err(AdapterError::Protocol(
                "invalid server NamespaceArray".into(),
            ));
        };
        if !value.status().is_good() || namespaces.dimensions.as_ref().is_some_and(|d| d.len() != 1)
        {
            return Err(AdapterError::Protocol(
                "invalid server NamespaceArray".into(),
            ));
        }
        let mut matches = namespaces
            .values
            .iter()
            .enumerate()
            .filter_map(|(i, value)| {
                matches!(value, Variant::String(uri) if uri.as_ref() == namespace_uri).then_some(i)
            });
        let index = matches
            .next()
            .and_then(|index| u16::try_from(index).ok())
            .filter(|_| matches.next().is_none())
            .ok_or_else(|| {
                AdapterError::Protocol("configured namespace not uniquely offered".into())
            })?;
        identifiers
            .iter()
            .map(|identifier| {
                let mut id = canonical_node_identifier(identifier)
                    .and_then(|value| value.parse::<NodeId>().ok())
                    .ok_or_else(|| {
                        AdapterError::InvalidValue("invalid configured point identifier".into())
                    })?;
                id.namespace = index;
                Ok(id.to_string())
            })
            .collect()
    }

    /// Read the selected points together, bounded to one in-flight request.
    pub async fn read_selected(
        &self,
        points: &[(String, MetricId)],
    ) -> Result<Vec<Result<oip_core::ObservationEnvelope, AdapterError>>, AdapterError> {
        self.check_selection(points.len())?;
        let ids = points
            .iter()
            .map(|(node_id, _)| {
                node_id
                    .parse::<NodeId>()
                    .map(ReadValueId::from)
                    .map_err(|_| {
                        AdapterError::InvalidValue("invalid resolved point identifier".into())
                    })
            })
            .collect::<Result<Vec<_>, _>>()?;
        let values = self.read_batch(&ids).await?;
        let metadata = SimulationMetadata {
            simulation_origin_required: false,
            ..Default::default()
        };
        Ok(points
            .iter()
            .zip(&values)
            .map(|((_, metric), value)| {
                let mut observation = data_value_to_observation(
                    metric,
                    value,
                    &metadata,
                    None,
                    &self.state.freshness,
                )?;
                if let Some(entity) = &self.state.entity_id {
                    observation.entity_id = entity.clone();
                }
                // The configured metric ID is a label and establishes no unit.
                observation.unit = oip_core::Unit::None;
                observation.status_code = value.status.map(|status| status.bits());
                Ok(observation)
            })
            .collect())
    }

    fn check_selection(&self, count: usize) -> Result<(), AdapterError> {
        if !self.explicit_secure_server || !(1..=MAX_SELECTED_POINTS).contains(&count) {
            return Err(AdapterError::InvalidValue(
                "invalid selected read profile or batch size".into(),
            ));
        }
        Ok(())
    }

    async fn read_batch(&self, ids: &[ReadValueId]) -> Result<Vec<DataValue>, AdapterError> {
        let _permit = self
            .requests
            .try_acquire()
            .map_err(|_| AdapterError::Protocol("selected read already in progress".into()))?;
        let result = tokio::time::timeout(
            SELECTED_READ_TIMEOUT,
            self.session.read(ids, TimestampsToReturn::Both, 0.0),
        )
        .await
        .map_err(|_| AdapterError::Protocol("selected read timed out".into()))?
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
        if result.len() != ids.len() {
            return Err(AdapterError::Protocol(
                "selected read returned an unexpected number of values".into(),
            ));
        }
        Ok(result)
    }

    async fn user_can_write(&self, node_id: &NodeId) -> Result<bool, AdapterError> {
        let mut values = self
            .session
            .read(
                &[ReadValueId::new(
                    node_id.clone(),
                    AttributeId::UserAccessLevel,
                )],
                TimestampsToReturn::Neither,
                0.0,
            )
            .await
            .map_err(|error| AdapterError::Protocol(error.to_string()))?;
        let Some(value) = values.pop().and_then(|value| value.value) else {
            return Ok(false);
        };
        let opcua::types::Variant::Byte(level) = value else {
            return Ok(false);
        };
        Ok(level & 0x02 != 0)
    }

    async fn connect_inner(options: &ClientOptions) -> Result<Self, AdapterError> {
        let local_simulation = options.security_profile.is_local_simulation();
        let explicit_secure_server = options.expected_server_uri.is_some();
        validate_client_endpoint(&options.endpoint, local_simulation)?;
        if explicit_secure_server && local_simulation {
            return Err(AdapterError::InvalidSecurityConfiguration(
                "an explicit server identity requires a secured connection".into(),
            ));
        }
        if options.session_retry_limit < 0 {
            return Err(AdapterError::Protocol(
                "session retry limit must be finite".to_owned(),
            ));
        }
        let (security_policy, security_mode) = match &options.security_profile {
            crate::SecurityProfile::LocalSimulation => {
                if options.production_security.is_some() {
                    return Err(AdapterError::InvalidSecurityConfiguration(
                        "local simulation must not carry production PKI settings".to_owned(),
                    ));
                }
                (SecurityPolicy::None, MessageSecurityMode::None)
            }
            crate::SecurityProfile::Production {
                security_policy,
                security_mode,
            } => {
                if security_policy != SecurityPolicy::Basic256Sha256.to_str()
                    || security_mode != "SignAndEncrypt"
                {
                    return Err(AdapterError::InvalidSecurityConfiguration(
                        "production requires Basic256Sha256 and SignAndEncrypt".to_owned(),
                    ));
                }
                let pki = options.production_security.as_ref().ok_or_else(|| {
                    AdapterError::InvalidSecurityConfiguration(
                        "production requires explicit certificate, key and trust store paths"
                            .to_owned(),
                    )
                })?;
                if explicit_secure_server {
                    super::security::validate_private_pki(pki)?;
                }
                super::security::validate_production_pki(pki)?;
                (
                    SecurityPolicy::Basic256Sha256,
                    MessageSecurityMode::SignAndEncrypt,
                )
            }
        };
        let connector = (
            options.endpoint.as_str(),
            security_policy.to_str(),
            security_mode,
            UserTokenPolicy::anonymous(),
        );
        let mut builder = ClientBuilder::new()
            .application_name("OIP Read-only Client")
            .application_uri("urn:oip:local-test-client")
            .product_uri("urn:oip:local-simulation")
            .trust_server_certs(false)
            .verify_server_certs(true)
            .ignore_clock_skew(false)
            .create_sample_keypair(false);
        if let Some(pki) = &options.production_security {
            builder = builder
                .pki_dir(&pki.pki_dir)
                .certificate_path(&pki.certificate_path)
                .private_key_path(&pki.private_key_path);
        }
        if explicit_secure_server {
            builder = builder
                .max_array_length(4_096)
                .max_string_length(64 * 1_024)
                .max_byte_string_length(1024 * 1024);
        }
        let mut client = builder
            .session_retry_limit(if explicit_secure_server {
                0
            } else {
                options.session_retry_limit
            })
            .session_retry_initial(Duration::from_millis(100))
            .session_retry_max(Duration::from_millis(500))
            .keep_alive_interval(Duration::from_millis(if explicit_secure_server {
                5_000
            } else {
                100
            }))
            .max_failed_keep_alive_count(3)
            .recreate_subscriptions(false)
            .client()
            .map_err(|errors| AdapterError::Connection(errors.join(", ")))?;
        let endpoint_descriptions = client
            .get_server_endpoints_from_url(options.endpoint.as_str())
            .await
            .map_err(|error| AdapterError::Connection(error.to_string()))?;
        if endpoint_descriptions.is_empty() {
            return Err(AdapterError::NoEndpoints);
        }
        let endpoints = endpoint_descriptions
            .iter()
            .map(|endpoint| EndpointInfo {
                url: endpoint.endpoint_url.to_string(),
                security_policy: endpoint.security_policy_uri.to_string(),
                security_mode: format!("{:?}", endpoint.security_mode),
            })
            .collect::<Vec<_>>();
        let (session, event_loop) = if let Some(expected_uri) = &options.expected_server_uri {
            let expected_url = url::Url::parse(&options.endpoint)
                .map_err(|_| AdapterError::NoEndpoints)?;
            let mut candidates = endpoint_descriptions.into_iter().filter(|candidate| {
                url::Url::parse(candidate.endpoint_url.as_ref()).ok().is_some_and(|url| same_endpoint(url, &expected_url))
                    && SecurityPolicy::from_uri(candidate.security_policy_uri.as_ref()) == security_policy
                    && candidate.security_mode == security_mode
                    && candidate.server.application_uri.as_ref() == expected_uri
                    && candidate.user_identity_tokens.as_ref().is_some_and(|tokens| {
                        tokens.iter().any(|token| token.token_type == UserTokenType::Anonymous)
                    })
            });
            let endpoint = candidates.next().ok_or_else(|| {
                AdapterError::InvalidSecurityConfiguration(
                    "configured server identity, endpoint, SignAndEncrypt or anonymous login not offered".into()
                )
            })?;
            if candidates.any(|candidate| candidate.server_certificate != endpoint.server_certificate) {
                return Err(AdapterError::InvalidSecurityConfiguration(
                    "multiple certificates offered for the same OPC-UA endpoint and identity".into()
                ));
            }
            // The discovery server cannot redirect an approved source, cause a
            // second discovery with different credentials, or set a weaker mode.
            client.connect_to_endpoint_directly(endpoint, IdentityToken::Anonymous)
        } else {
            client.connect_to_matching_endpoint(connector, IdentityToken::Anonymous).await
        }.map_err(|error| AdapterError::Connection(error.to_string()))?;
        if explicit_secure_server {
            // The Core owns the only retry loop. It resolves NamespaceArray
            // again whenever it builds a fresh session.
            session.disable_reconnects();
        }
        let (event_sender, mut event_receiver) = mpsc::channel(EVENT_CHANNEL_CAPACITY);
        let state = CollectionState::new(
            options.namespace,
            options.entity_id.clone(),
            options.simulation_origin_required,
            event_sender,
            options.freshness.clone(),
        );
        let subscribed_metrics = Arc::new(Mutex::new(Vec::new()));
        let event_task = OwnedEventTask(spawn_event_loop(
            event_loop,
            session.clone(),
            state.clone(),
            subscribed_metrics.clone(),
            explicit_secure_server,
        ));
        if !session.wait_for_connection().await {
            let reason = match event_receiver.try_recv() {
                Ok(ClientEvent::SubscriptionError { reason, .. }) => reason,
                _ => "session did not reach connected state".into(),
            };
            return Err(AdapterError::Connection(reason));
        }
        let discovered_metadata = read_simulation_metadata(
            &session,
            options.namespace,
            options.simulation_origin_required,
        )
        .await?;
        *state
            .metadata
            .lock()
            .map_err(|_| AdapterError::Task("metadata lock poisoned".to_owned()))? =
            discovered_metadata;

        Ok(Self {
            session,
            namespace: options.namespace,
            endpoints,
            state,
            subscribed_metrics,
            max_browse_nodes: options.max_browse_nodes,
            read_only: options.read_only || explicit_secure_server,
            explicit_secure_server,
            requests: tokio::sync::Semaphore::new(if explicit_secure_server { 1 } else { 8 }),
            events: tokio::sync::Mutex::new(Some(event_receiver)),
            event_task,
            reported_drops: AtomicU64::new(0),
        })
    }

    /// Local producer ownership, independent of a remote CloseSession acknowledgement.
    pub fn local_event_task_stopped(&self) -> bool {
        self.event_task.0.is_finished()
    }

    pub async fn shutdown(&self) -> Result<(), AdapterError> {
        // Stop queue admission before the protocol close. Under overflow a
        // pending control-event send otherwise blocks the session poll loop,
        // which is also needed to acknowledge CloseSession. Closing retains
        // already queued events; it does not pretend they reached the Core.
        if let Some(receiver) = self.events.lock().await.as_mut() {
            receiver.close();
        }
        // Poll the SDK's existing connection-state watch, without initiating a
        // connection. An offline peer cannot acknowledge CloseSession and must
        // retain the short cleanup budget. A connected flooded subscription may
        // need longer to delete monitored items. CoreRuntime still bounds both.
        let connected = matches!(
            tokio::time::timeout(Duration::ZERO, self.session.wait_for_connection()).await,
            Ok(true)
        );
        let close_budget = Duration::from_secs(if connected { 8 } else { 2 });
        let result = tokio::time::timeout(close_budget, self.session.disconnect()).await;
        self.event_task.0.abort();
        let _ = tokio::time::timeout(Duration::from_secs(1), async {
            while !self.event_task.0.is_finished() {
                tokio::task::yield_now().await;
            }
        })
        .await;
        result
            .map_err(|_| AdapterError::Task("disconnect timed out".into()))?
            .map_err(|e| AdapterError::Protocol(e.to_string()))
    }
    pub async fn disconnect(mut self) -> Result<(), AdapterError> {
        let result = self.shutdown().await;
        let _ = (&mut self.event_task.0).await;
        result
    }
    pub async fn queued_events(&self) -> usize {
        self.events.lock().await.as_ref().map_or(0, |r| r.len())
    }

    /// Number of observations that were dropped because the event channel was full.
    pub fn dropped_observations(&self) -> u64 {
        self.state.dropped_observations.load(Ordering::Relaxed)
    }

    /// Reads the value of one node of the server.
    ///
    /// `observe` states whether the read belongs to the **collector**: only
    /// the collector observes the source, because only the collector
    /// subscribes to the metrics of the source. The read of the browser
    /// shows the value of a node and changes nothing.
    async fn read_at(
        &self,
        node_id: NodeId,
        name: &MetricId,
        observe: bool,
        entity: Option<oip_core::EntityId>,
    ) -> Result<oip_core::ObservationEnvelope, AdapterError> {
        if self.explicit_secure_server {
            return Err(AdapterError::Protocol(
                "only selected reads are allowed".into(),
            ));
        }
        let value = read_data_value_at(&self.session, node_id).await?;
        let metadata = self
            .state
            .metadata
            .lock()
            .map_err(|_| AdapterError::Task("metadata lock poisoned".to_owned()))?
            .clone();
        let latest = if observe {
            value
                .source_timestamp
                .filter(|timestamp| external_datetime_is_valid(*timestamp))
                .map(datetime_to_timestamp)
                .and_then(|source| self.state.observe_source_timestamp(name.as_str(), source))
        } else {
            None
        };
        let mut observation =
            data_value_to_observation(name, &value, &metadata, latest, &self.state.freshness)?;
        // The measurements of the source belong to the entity of the source.
        if let Some(source_entity) = self.state.entity_id.clone() {
            observation.entity_id = source_entity;
        }
        if let Some(entity) = entity {
            // The value of a node belongs to the entity that the **source**
            // declares — not to the machine of a simulator profile.
            observation.entity_id = entity;
        }
        Ok(observation)
    }
}

#[async_trait]
impl ReadOnlyOpcUaAdapter for AsyncOpcUaClient {
    async fn endpoints(&self) -> Result<Vec<EndpointInfo>, AdapterError> {
        Ok(self.endpoints.clone())
    }

    async fn browse(&self) -> Result<Vec<BrowseEntry>, AdapterError> {
        if self.explicit_secure_server {
            return Err(AdapterError::Protocol(
                "unrestricted browse is disabled for selected reads".into(),
            ));
        }
        let mut entries = Vec::new();
        let mut visited = HashSet::new();
        // The catalogue is a **set of nodes**: a node that is reachable
        // through several parents is delivered once, so the pages of the
        // Core stay disjoint and the total is exact.
        let mut emitted = HashSet::new();
        // The pending node carries the browse name of its **parent**: it is
        // the folder of every node below it. The standard root of a server
        // has the browse name of its standard folder.
        let mut pending = vec![(NodeId::objects_folder_id(), "Objects".to_owned(), 0)];
        visited.insert(NodeId::objects_folder_id());
        let mut requests = 0;

        while let Some((node_id, parent_name, depth)) = pending.pop() {
            requests += 1;
            if requests > MAX_BROWSE_REQUESTS {
                return Err(AdapterError::BrowseLimitExceeded(self.max_browse_nodes));
            }
            let description = BrowseDescription {
                node_id,
                browse_direction: BrowseDirection::Forward,
                reference_type_id: ReferenceTypeId::HierarchicalReferences.into(),
                include_subtypes: true,
                node_class_mask: NodeClassMask::all().bits(),
                // Without an explicit result mask the server returns references
                // without browse name, display name or node class.
                result_mask: (BrowseDescriptionResultMask::RESULT_MASK_BROWSE_NAME
                    | BrowseDescriptionResultMask::RESULT_MASK_DISPLAY_NAME
                    | BrowseDescriptionResultMask::RESULT_MASK_NODE_CLASS)
                    .bits(),
            };
            let mut results = self
                .session
                .browse(&[description], 1_000, None)
                .await
                .map_err(|error| AdapterError::Protocol(error.to_string()))?;
            let mut result = results
                .pop()
                .ok_or_else(|| AdapterError::Protocol("empty browse result".to_owned()))?;
            loop {
                if result.status_code.is_bad() {
                    return Err(AdapterError::Protocol(result.status_code.to_string()));
                }
                if let Some(references) = result.references.take() {
                    for reference in references {
                        let target = reference.node_id.node_id;
                        let browse_name = reference.browse_name.to_string();
                        // A node that was already delivered is not delivered
                        // again: the folder of a node with several parents is
                        // the folder of the parent that reached it first.
                        if !emitted.insert(target.clone()) {
                            continue;
                        }
                        if entries.len() >= self.max_browse_nodes {
                            return Err(AdapterError::BrowseLimitExceeded(self.max_browse_nodes));
                        }
                        if depth < MAX_BROWSE_DEPTH
                            && visited.insert(target.clone())
                            && target.namespace == self.namespace
                        {
                            pending.push((target.clone(), browse_name.clone(), depth + 1));
                        }
                        let access = if !self.read_only
                            && reference.node_class == opcua::types::NodeClass::Variable
                            && self.user_can_write(&target).await.unwrap_or(false)
                        {
                            "ReadWrite"
                        } else if reference.node_class == opcua::types::NodeClass::Variable {
                            "Read"
                        } else {
                            "Browse"
                        };
                        entries.push(BrowseEntry {
                            node_id: target.to_string(),
                            browse_name,
                            display_name: reference.display_name.to_string(),
                            node_class: format!("{:?}", reference.node_class),
                            access: access.to_owned(),
                            folder: parent_name.clone(),
                        });
                    }
                }
                let continuation_point = std::mem::take(&mut result.continuation_point);
                if continuation_point.is_null() {
                    break;
                }
                requests += 1;
                if requests > MAX_BROWSE_REQUESTS {
                    return Err(AdapterError::BrowseLimitExceeded(self.max_browse_nodes));
                }
                let mut continued = self
                    .session
                    .browse_next(false, &[continuation_point])
                    .await
                    .map_err(|error| AdapterError::Protocol(error.to_string()))?;
                result = continued.pop().ok_or_else(|| {
                    AdapterError::Protocol("empty browse continuation result".to_owned())
                })?;
            }
        }
        Ok(entries)
    }

    async fn read(&self, metric: &MetricId) -> Result<oip_core::ObservationEnvelope, AdapterError> {
        let node_id = NodeId::new(self.namespace, metric.as_str());
        self.read_at(node_id, metric, true, None).await
    }

    async fn read_node(
        &self,
        node_id: &str,
        name: &MetricId,
        entity: &oip_core::EntityId,
    ) -> Result<oip_core::ObservationEnvelope, AdapterError> {
        let node = node_id.parse::<NodeId>().map_err(|_| {
            AdapterError::Protocol(format!("the node id {node_id} of the server is invalid"))
        })?;
        self.read_at(node, name, false, Some(entity.clone())).await
    }

    /// Reads the value of one node of the server.
    ///
    /// `observe` states whether the read belongs to the **collector**: only
    /// the collector observes the source, because only the collector
    /// subscribes to the metrics of the source. The read of the browser
    /// shows the value of a node and changes nothing.
    async fn subscribe(&self, metrics: &[MetricId]) -> Result<(), AdapterError> {
        if self.explicit_secure_server {
            return Err(AdapterError::Protocol(
                "subscriptions are disabled for selected polling".into(),
            ));
        }
        let stale = self
            .state
            .active_subscriptions
            .lock()
            .map(|active| active.clone())
            .unwrap_or_default();
        if !stale.is_empty() {
            self.session
                .delete_subscriptions(&stale)
                .await
                .map_err(|error| AdapterError::Protocol(error.to_string()))?;
            self.state
                .active_subscriptions
                .lock()
                .map_err(|_| AdapterError::Task("subscription lock poisoned".to_owned()))?
                .clear();
        }
        self.subscribed_metrics
            .lock()
            .map_err(|_| AdapterError::Task("subscription lock poisoned".to_owned()))?
            .clear();
        subscribe_session(&self.session, &self.state, metrics).await?;
        let mut subscribed = self
            .subscribed_metrics
            .lock()
            .map_err(|_| AdapterError::Task("subscription lock poisoned".to_owned()))?;
        *subscribed = metrics.to_vec();
        Ok(())
    }

    async fn next_event(&self, timeout: Duration) -> Result<ClientEvent, AdapterError> {
        let dropped = self.dropped_observations();
        let previous = self.reported_drops.swap(dropped, Ordering::Relaxed);
        if dropped > previous {
            let at = Timestamp::now()?;
            return Ok(ClientEvent::DataLoss {
                at,
                gap: crate::DataGap {
                    started_at: at,
                    ended_at: at,
                    reason: "bounded adapter queue overflow; exact lost sample interval unknown"
                        .into(),
                },
                dropped: dropped - previous,
            });
        }
        let mut guard = self.events.lock().await;
        let receiver = guard
            .as_mut()
            .ok_or_else(|| AdapterError::Task("event channel already consumed".to_owned()))?;
        tokio::time::timeout(timeout, receiver.recv())
            .await
            .map_err(|_| AdapterError::Task("timed out waiting for client event".to_owned()))?
            .ok_or_else(|| AdapterError::Task("client event channel closed".to_owned()))
    }
}

async fn read_data_value(
    session: &Arc<Session>,
    namespace: u16,
    metric: &MetricId,
) -> Result<DataValue, AdapterError> {
    read_data_value_at(session, NodeId::new(namespace, metric.as_str())).await
}

/// Reads the value of the node with the given **node id** of the server.
async fn read_data_value_at(
    session: &Arc<Session>,
    node_id: NodeId,
) -> Result<DataValue, AdapterError> {
    let mut values = session
        .read(&[ReadValueId::from(node_id)], TimestampsToReturn::Both, 0.0)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    values
        .pop()
        .ok_or_else(|| AdapterError::Protocol("empty read result".to_owned()))
}

async fn read_simulation_metadata(
    session: &Arc<Session>,
    namespace: u16,
    simulation_origin_required: bool,
) -> Result<SimulationMetadata, AdapterError> {
    if !simulation_origin_required {
        return Ok(SimulationMetadata {
            simulation_origin_required: false,
            ..Default::default()
        });
    }
    let origin = read_data_value(
        session,
        namespace,
        &MetricId::new("simulation.origin_id").expect("static metric id"),
    )
    .await?;
    let seed = read_data_value(
        session,
        namespace,
        &MetricId::new("simulation.seed").expect("static metric id"),
    )
    .await?;
    let scenario = read_data_value(
        session,
        namespace,
        &MetricId::new("simulation.scenario").expect("static metric id"),
    )
    .await?;
    let epoch = read_data_value(
        session,
        namespace,
        &MetricId::new("simulation.epoch_unix_ms").expect("static metric id"),
    )
    .await?;
    let tick_duration = read_data_value(
        session,
        namespace,
        &MetricId::new("simulation.tick_duration_ms").expect("static metric id"),
    )
    .await?;
    // Simulation metadata is optional. A physical OPC-UA server does not need
    // to fabricate simulation nodes for the general browse/read contract.
    let optional_metric = |data: &DataValue| -> Result<Option<MetricValue>, AdapterError> {
        match data.value.as_ref() {
            None | Some(opcua::types::Variant::Empty) => Ok(None),
            Some(value) => variant_to_metric_value(value).map(Some),
        }
    };
    Ok(SimulationMetadata {
        simulation_origin_required: true,
        origin_id: optional_metric(&origin)?.and_then(text_value),
        seed: optional_metric(&seed)?.and_then(unsigned_value),
        scenario: optional_metric(&scenario)?.and_then(text_value),
        epoch_unix_ms: optional_metric(&epoch)?.and_then(signed_value),
        tick_duration_ms: optional_metric(&tick_duration)?.and_then(unsigned_value),
    })
}

fn text_value(value: MetricValue) -> Option<String> {
    match value {
        MetricValue::Text(value) => Some(value),
        _ => None,
    }
}

fn unsigned_value(value: MetricValue) -> Option<u64> {
    match value {
        MetricValue::UnsignedInteger(value) => Some(value),
        _ => None,
    }
}

fn signed_value(value: MetricValue) -> Option<i64> {
    match value {
        MetricValue::SignedInteger(value) => Some(value),
        _ => None,
    }
}

/// Shared state of the collection path.
///
/// It is shared between the client, the session event loop and the subscription
/// callbacks so that the reconnect path can restore the collection without
/// losing track of subscriptions or dropped observations.
#[derive(Clone)]
struct CollectionState {
    namespace: u16,
    simulation_origin_required: bool,
    /// The entity of the source: the measurements of the source belong to it,
    /// whatever the machine id of the simulation is.
    entity_id: Option<oip_core::EntityId>,
    event_sender: mpsc::Sender<ClientEvent>,
    metadata: Arc<Mutex<SimulationMetadata>>,
    active_subscriptions: Arc<Mutex<Vec<u32>>>,
    dropped_observations: Arc<AtomicU64>,
    freshness: FreshnessPolicy,
    /// Newest source timestamp observed per metric, used as the reference
    /// clock for freshness on sources that run on a virtual clock.
    latest_source_timestamps: Arc<Mutex<HashMap<String, Timestamp>>>,
}

impl CollectionState {
    fn new(
        namespace: u16,
        entity_id: Option<oip_core::EntityId>,
        simulation_origin_required: bool,
        event_sender: mpsc::Sender<ClientEvent>,
        freshness: FreshnessPolicy,
    ) -> Self {
        Self {
            namespace,
            simulation_origin_required,
            entity_id,
            event_sender,
            metadata: Arc::new(Mutex::new(SimulationMetadata::default())),
            active_subscriptions: Arc::new(Mutex::new(Vec::new())),
            dropped_observations: Arc::new(AtomicU64::new(0)),
            freshness,
            latest_source_timestamps: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Returns the newest source timestamp known for a metric and records the
    /// given one if it is newer.
    fn observe_source_timestamp(&self, metric_id: &str, source: Timestamp) -> Option<Timestamp> {
        let mut timestamps = self.latest_source_timestamps.lock().ok()?;
        let entry = timestamps.entry(metric_id.to_owned()).or_insert(source);
        let previous = *entry;
        if source > previous {
            *entry = source;
        }
        Some(previous)
    }
}

async fn subscribe_session(
    session: &Arc<Session>,
    state: &CollectionState,
    metrics: &[MetricId],
) -> Result<(), AdapterError> {
    if metrics.is_empty() {
        return Ok(());
    }
    let namespace = state.namespace;
    let event_sender = state.event_sender.clone();
    let metadata = state.metadata.clone();
    let dropped_observations = state.dropped_observations.clone();
    let freshness = state.freshness.clone();
    let collection_state = state.clone();
    let monitored_metrics = metrics.to_vec();
    let subscription_id = session
        .create_subscription(
            Duration::from_millis(50),
            20,
            60,
            0,
            0,
            true,
            DataChangeCallback::new(move |value, item| {
                // Once shutdown closes admission, discard callbacks before the
                // per-node lookup/conversion. Otherwise a flooded subscription
                // can starve the same event loop needed for CloseSession.
                if event_sender.is_closed() {
                    return;
                }
                let node_id = &item.item_to_monitor().node_id;
                let metric = monitored_metrics
                    .iter()
                    .find(|metric| NodeId::new(namespace, metric.as_str()) == *node_id)
                    .cloned();
                let Some(metric) = metric else {
                    return;
                };
                let mapped =
                    metadata
                        .lock()
                        .map_err(|error| error.to_string())
                        .and_then(|metadata| {
                            let latest = value
                                .source_timestamp
                                .filter(|timestamp| external_datetime_is_valid(*timestamp))
                                .map(datetime_to_timestamp)
                                .and_then(|source| {
                                    collection_state
                                        .observe_source_timestamp(metric.as_str(), source)
                                });
                            data_value_to_observation(
                                &metric, &value, &metadata, latest, &freshness,
                            )
                            .map(|mut observation| {
                                // The measurements of the source belong to
                                // the entity of the source.
                                if let Some(entity) = collection_state.entity_id.clone() {
                                    observation.entity_id = entity;
                                }
                                observation
                            })
                            .map_err(|error| error.to_string())
                        });
                match mapped {
                    Ok(observation) => {
                        if let Err(error) =
                            event_sender.try_send(ClientEvent::Observation(Box::new(observation)))
                        {
                            let dropped = dropped_observations.fetch_add(1, Ordering::Relaxed) + 1;
                            tracing::warn!(
                                dropped,
                                %error,
                                "observation event channel is full; observation dropped"
                            );
                        }
                    }
                    Err(error) => {
                        if let Ok(at) = Timestamp::now() {
                            if event_sender
                                .try_send(ClientEvent::SubscriptionError { at, reason: error })
                                .is_err()
                            {
                                dropped_observations.fetch_add(1, Ordering::Relaxed);
                            }
                        }
                    }
                }
            }),
        )
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    let items = metrics
        .iter()
        .map(|metric| NodeId::new(namespace, metric.as_str()))
        .map(MonitoredItemCreateRequest::from)
        .collect::<Vec<_>>();
    session
        .create_monitored_items(subscription_id, TimestampsToReturn::Both, items)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    if let Ok(mut active) = state.active_subscriptions.lock() {
        active.push(subscription_id);
    }
    Ok(())
}

fn is_certificate_security_error(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::BadNoValidCertificates
            | StatusCode::BadSecurityChecksFailed
            | StatusCode::BadCertificateUntrusted
            | StatusCode::BadCertificateTimeInvalid
            | StatusCode::BadCertificateInvalid
            | StatusCode::BadCertificateHostNameInvalid
            | StatusCode::BadCertificateUriInvalid
            | StatusCode::BadCertificateRevoked
            | StatusCode::BadCertificateIssuerTimeInvalid
            | StatusCode::BadCertificateChainIncomplete
            | StatusCode::BadSecurityModeRejected
    )
}

fn same_endpoint(mut candidate: url::Url, expected: &url::Url) -> bool {
    if (candidate.path().is_empty() || candidate.path() == "/")
        && (expected.path().is_empty() || expected.path() == "/")
    {
        candidate.set_path(expected.path());
    }
    &candidate == expected
}

fn spawn_event_loop<T>(
    event_loop: opcua::client::SessionEventLoop<T>,
    session: Arc<Session>,
    state: CollectionState,
    subscribed_metrics: Arc<Mutex<Vec<MetricId>>>,
    explicit_secure_server: bool,
) -> JoinHandle<()>
where
    T: opcua::client::transport::Connector + Send + Sync + 'static,
{
    let namespace = state.namespace;
    let event_sender = state.event_sender.clone();
    tokio::spawn(async move {
        let stream = event_loop.enter();
        tokio::pin!(stream);
        let mut gap_started: Option<(Timestamp, String)> = None;
        let mut children = tokio::task::JoinSet::new();
        loop {
            let next = tokio::select! { result=stream.next()=>result,_=children.join_next(),if !children.is_empty()=>continue };
            let Some(result) = next else {
                break;
            };
            match result {
                Ok(SessionPollResult::ConnectionLost(status)) => {
                    tracing::debug!(%status, "OIP client observed connection loss");
                    let certificate_change = is_certificate_security_error(status);
                    if let Ok(at) = Timestamp::now() {
                        let reason = status.to_string();
                        gap_started = Some((at, reason.clone()));
                        let _ = event_sender
                            .send(ClientEvent::ConnectionLost { at, reason })
                            .await;
                        if certificate_change {
                            // The pinned client caches the peer certificate
                            // thumbprint for reconnect. Retrying a changed or
                            // rejected certificate cannot succeed and must not
                            // weaken trust. Require fresh endpoint discovery and
                            // a new explicitly configured client instead.
                            let _ = event_sender
                                .send(ClientEvent::SubscriptionError {
                                    at,
                                    reason: format!(
                                        "{status}; certificate/trust change requires fresh discovery and a new client"
                                    ),
                                })
                                .await;
                            break;
                        }
                    }
                }
                Ok(SessionPollResult::ReconnectFailed(status)) => {
                    let security_failure = is_certificate_security_error(status);
                    if let Ok(at) = Timestamp::now() {
                        if security_failure {
                            let _ = event_sender
                                .send(ClientEvent::SubscriptionError {
                                    at,
                                    reason: format!(
                                        "{status}; certificate/trust change requires fresh discovery and a new client"
                                    ),
                                })
                                .await;
                        } else {
                            let _ = event_sender
                                .send(ClientEvent::ConnectionLost {
                                    at,
                                    reason: format!("reconnect failed: {status}"),
                                })
                                .await;
                        }
                    }
                    if security_failure {
                        break;
                    }
                }
                Ok(SessionPollResult::Reconnected(mode)) => {
                    if explicit_secure_server {
                        // Selected reads do not create a subscription or
                        // consult simulator nodes on the external server.
                        continue;
                    }
                    tracing::debug!(?mode, "OIP client observed reconnect");
                    let at = match Timestamp::now() {
                        Ok(at) => at,
                        Err(error) => {
                            tracing::error!(%error, "failed to timestamp reconnect");
                            continue;
                        }
                    };
                    // A reconnect must always restore the collection path, even
                    // when no explicit connection loss was observed.
                    let (started_at, reason) = gap_started
                        .take()
                        .unwrap_or((at, "reconnect without recorded connection loss".to_owned()));
                    let metrics = subscribed_metrics
                        .lock()
                        .map(|metrics| metrics.clone())
                        .unwrap_or_default();
                    tracing::debug!(
                        metrics = metrics.len(),
                        "OIP client recreating subscription"
                    );
                    // Subscription requests require the session event loop to keep polling.
                    // Run resubscription independently instead of deadlocking this callback.
                    children.spawn({
                        let session = session.clone();
                        let event_sender = event_sender.clone();
                        let state = state.clone();
                        async move {
                            // Remove stale subscriptions so that a reconnect cannot
                            // produce duplicate monitored items.
                            let stale = state
                                .active_subscriptions
                                .lock()
                                .map(|active| active.clone())
                                .unwrap_or_default();
                            if !stale.is_empty() {
                                let _ = session.delete_subscriptions(&stale).await;
                                if let Ok(mut active) = state.active_subscriptions.lock() {
                                    active.clear();
                                }
                            }
                            match read_simulation_metadata(
                                &session,
                                namespace,
                                state.simulation_origin_required,
                            )
                            .await
                            {
                                Ok(discovered) => {
                                    if let Ok(mut timestamps) =
                                        state.latest_source_timestamps.lock()
                                    {
                                        timestamps.clear();
                                    }
                                    if let Ok(mut metadata) = state.metadata.lock() {
                                        *metadata = discovered;
                                    }
                                }
                                Err(error) => {
                                    let _ = event_sender
                                        .send(ClientEvent::SubscriptionError {
                                            at,
                                            reason: format!("metadata refresh failed: {error}"),
                                        })
                                        .await;
                                    return;
                                }
                            }
                            match subscribe_session(&session, &state, &metrics).await {
                                Ok(()) => {
                                    let _ = event_sender
                                        .send(ClientEvent::Reconnected {
                                            at,
                                            gap: DataGap {
                                                started_at,
                                                ended_at: at,
                                                reason,
                                            },
                                        })
                                        .await;
                                }
                                Err(error) => {
                                    let _ = event_sender
                                        .send(ClientEvent::SubscriptionError {
                                            at,
                                            reason: format!("resubscribe failed: {error}"),
                                        })
                                        .await;
                                }
                            }
                        }
                    });
                }
                Err(status) => {
                    if let Ok(at) = Timestamp::now() {
                        let certificate_change = is_certificate_security_error(status);
                        let reason = if certificate_change {
                            format!(
                                "{status}; certificate/trust change requires fresh discovery and a new client"
                            )
                        } else {
                            status.to_string()
                        };
                        let _ = event_sender
                            .send(ClientEvent::SubscriptionError { at, reason })
                            .await;
                    }
                    break;
                }
                _ => {}
            }
        }
    })
}

#[cfg(test)]
mod tests;

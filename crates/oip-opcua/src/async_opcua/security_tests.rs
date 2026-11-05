use super::{AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
use crate::async_opcua::AsyncOpcUaClient;
use crate::{
    AdapterError, ClientEvent, ClientOptions, ProductionSecurityConfig, ReadOnlyOpcUaAdapter,
    SecurityProfile,
};
use oip_core::{DataQuality, MetricId, MetricValue};
use oip_simulator::{Scenario, SimulationConfig};
use opcua::crypto::{CertificateStore, SecurityPolicy, X509Data, X509};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

static NEXT_FIXTURE: AtomicU64 = AtomicU64::new(0);
const SERVER_URI: &str = "urn:oip:local-simulation-server";
const CLIENT_URI: &str = "urn:oip:local-test-client";

fn production_profile() -> SecurityProfile {
    SecurityProfile::Production {
        security_policy: SecurityPolicy::Basic256Sha256.to_str().to_owned(),
        security_mode: "SignAndEncrypt".to_owned(),
    }
}

fn free_port() -> u16 {
    std::net::TcpListener::bind(("127.0.0.1", 0))
        .expect("bind loopback")
        .local_addr()
        .expect("local address")
        .port()
}

fn create_identity(
    root: &Path,
    application_uri: &str,
    duration_days: u32,
) -> ProductionSecurityConfig {
    for directory in ["own", "private", "trusted", "rejected"] {
        std::fs::create_dir_all(root.join(directory)).expect("create PKI directory");
    }
    let config = ProductionSecurityConfig::new(root, "own/cert.der", "private/private.pem");
    let certificate_path = root.join(&config.certificate_path);
    let private_key_path = root.join(&config.private_key_path);
    let data = X509Data {
        key_size: 2048,
        common_name: "OIP loopback security test".to_owned(),
        organization: "OIP test only".to_owned(),
        organizational_unit: "OIP-002".to_owned(),
        country: "DE".to_owned(),
        state: "test".to_owned(),
        alt_host_names: X509Data::alt_host_names(
            application_uri,
            Some(vec!["127.0.0.1".to_owned()]),
            false,
            false,
            false,
        ),
        certificate_duration_days: duration_days,
    };
    CertificateStore::create_certificate_and_key(
        &data,
        false,
        &certificate_path,
        &private_key_path,
    )
    .expect("generate test certificate");
    config
}

struct SecurityFixture {
    root: PathBuf,
    server: ProductionSecurityConfig,
    client: ProductionSecurityConfig,
}

impl SecurityFixture {
    fn new(server_duration_days: u32) -> Self {
        let sequence = NEXT_FIXTURE.fetch_add(1, Ordering::Relaxed);
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../target/oip-002-tests")
            .join(format!("pki-{}-{sequence}", std::process::id()));
        let server = create_identity(&root.join("server"), SERVER_URI, server_duration_days);
        let client = create_identity(&root.join("client"), CLIENT_URI, 1);
        trust_peer(&client, &server);
        trust_peer(&server, &client);
        Self {
            root,
            server,
            client,
        }
    }

    fn server_config(&self, port: u16) -> AsyncOpcUaServerConfig {
        AsyncOpcUaServerConfig {
            port,
            simulation: SimulationConfig {
                bulk_node_count: 0,
                tick_duration_ms: 50,
                ..SimulationConfig::default()
            },
            scenario: Scenario::Normal,
            security_profile: production_profile(),
            production_security: Some(self.server.clone()),
        }
    }

    fn client_options(&self, endpoint: &str) -> ClientOptions {
        ClientOptions {
            security_profile: production_profile(),
            production_security: Some(self.client.clone()),
            ..ClientOptions::local_simulation(endpoint, 2)
        }
    }

    fn replacement_server(&self, name: &str) -> ProductionSecurityConfig {
        let replacement = create_identity(&self.root.join(name), SERVER_URI, 1);
        trust_peer(&self.client, &replacement);
        trust_peer(&replacement, &self.client);
        replacement
    }
}

fn trust_peer(recipient: &ProductionSecurityConfig, peer: &ProductionSecurityConfig) {
    let peer_certificate = peer.pki_dir.join(&peer.certificate_path);
    let certificate =
        X509::from_der(&std::fs::read(&peer_certificate).expect("read peer certificate"))
            .expect("parse peer certificate");
    let name = CertificateStore::cert_file_name(&certificate);
    std::fs::copy(
        peer_certificate,
        recipient.pki_dir.join("trusted").join(name),
    )
    .expect("explicitly trust test peer certificate");
}

fn trusted_peer_path(
    recipient: &ProductionSecurityConfig,
    peer: &ProductionSecurityConfig,
) -> PathBuf {
    let certificate = X509::from_der(
        &std::fs::read(peer.pki_dir.join(&peer.certificate_path)).expect("read peer certificate"),
    )
    .expect("parse peer certificate");
    recipient
        .pki_dir
        .join("trusted")
        .join(CertificateStore::cert_file_name(&certificate))
}

async fn start_and_connect(
    fixture: &SecurityFixture,
) -> (RunningAsyncOpcUaServer, AsyncOpcUaClient) {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_test_writer()
        .try_init();
    let server = RunningAsyncOpcUaServer::start(fixture.server_config(free_port()))
        .await
        .expect("start secure server");
    let client = AsyncOpcUaClient::connect(&fixture.client_options(server.endpoint()))
        .await
        .expect("connect secure client");
    (server, client)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn production_sign_and_encrypt_supports_read_and_subscription() {
    let fixture = SecurityFixture::new(1);
    let (server, client) = start_and_connect(&fixture).await;
    let endpoints = client.endpoints().await.expect("endpoints");
    assert!(endpoints.iter().any(|endpoint| {
        endpoint.security_policy == "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256"
            && endpoint.security_mode == "SignAndEncrypt"
    }));
    assert!(!endpoints.iter().any(|endpoint| {
        endpoint.security_policy == "http://opcfoundation.org/UA/SecurityPolicy#None"
            && endpoint.security_mode == "None"
    }));
    let metric = MetricId::new("temperature").expect("metric");
    let observation = client.read(&metric).await.expect("secure read");
    assert!(matches!(observation.value, Some(MetricValue::Float(_))));
    assert_eq!(observation.quality, DataQuality::Good);
    client
        .subscribe(std::slice::from_ref(&metric))
        .await
        .expect("secure subscribe");
    loop {
        if let ClientEvent::Observation(observation) = client
            .next_event(Duration::from_secs(10))
            .await
            .expect("secure event")
        {
            assert_eq!(observation.quality, DataQuality::Good);
            break;
        }
    }
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unknown_server_certificate_is_rejected() {
    let fixture = SecurityFixture::new(1);
    std::fs::remove_file(trusted_peer_path(&fixture.client, &fixture.server))
        .expect("remove explicit trust");
    let server = RunningAsyncOpcUaServer::start(fixture.server_config(free_port()))
        .await
        .expect("start secure server");
    let result = AsyncOpcUaClient::connect(&fixture.client_options(server.endpoint())).await;
    assert!(result.is_err(), "unknown server certificate was trusted");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unknown_client_certificate_is_rejected() {
    let fixture = SecurityFixture::new(1);
    std::fs::remove_file(trusted_peer_path(&fixture.server, &fixture.client))
        .expect("remove explicit trust");
    let server = RunningAsyncOpcUaServer::start(fixture.server_config(free_port()))
        .await
        .expect("start secure server");
    let result = AsyncOpcUaClient::connect(&fixture.client_options(server.endpoint())).await;
    assert!(result.is_err(), "unknown client certificate was trusted");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn expired_server_certificate_is_rejected_even_when_trusted() {
    let fixture = SecurityFixture::new(0);
    tokio::time::sleep(Duration::from_millis(1_100)).await;
    let result = RunningAsyncOpcUaServer::start(fixture.server_config(free_port())).await;
    assert!(
        matches!(result, Err(AdapterError::InvalidSecurityConfiguration(_))),
        "expired server certificate was accepted"
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn malformed_client_certificate_is_rejected_without_panic() {
    let fixture = SecurityFixture::new(1);
    std::fs::write(
        fixture
            .client
            .pki_dir
            .join(&fixture.client.certificate_path),
        b"not a DER certificate",
    )
    .expect("corrupt client fixture");
    let server = RunningAsyncOpcUaServer::start(fixture.server_config(free_port()))
        .await
        .expect("start secure server");
    let result = AsyncOpcUaClient::connect(&fixture.client_options(server.endpoint())).await;
    assert!(result.is_err(), "malformed client certificate was accepted");
    server.stop().await.expect("stop server");
}

#[tokio::test]
async fn production_cannot_downgrade_or_run_without_explicit_pki() {
    let options = ClientOptions {
        security_profile: production_profile(),
        ..ClientOptions::local_simulation("opc.tcp://127.0.0.1:4840", 2)
    };
    assert!(matches!(
        AsyncOpcUaClient::connect(&options).await,
        Err(AdapterError::InvalidSecurityConfiguration(_))
    ));
    let downgraded = ClientOptions {
        security_profile: SecurityProfile::Production {
            security_policy: SecurityPolicy::None.to_str().to_owned(),
            security_mode: "None".to_owned(),
        },
        ..options
    };
    assert!(matches!(
        AsyncOpcUaClient::connect(&downgraded).await,
        Err(AdapterError::InvalidSecurityConfiguration(_))
    ));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn trusted_certificate_rotation_reconnects_and_resubscribes() {
    let fixture = SecurityFixture::new(1);
    let (server, client) = start_and_connect(&fixture).await;
    let metric = MetricId::new("temperature").expect("metric");
    client
        .subscribe(std::slice::from_ref(&metric))
        .await
        .expect("subscribe");
    loop {
        if matches!(
            client
                .next_event(Duration::from_secs(10))
                .await
                .expect("event"),
            ClientEvent::Observation(_)
        ) {
            break;
        }
    }
    let port = server.port();
    let replacement = fixture.replacement_server("replacement");
    server.stop().await.expect("stop original server");
    loop {
        if matches!(
            client
                .next_event(Duration::from_secs(10))
                .await
                .expect("event"),
            ClientEvent::ConnectionLost { .. }
        ) {
            break;
        }
    }
    let mut config = fixture.server_config(port);
    config.scenario = Scenario::Reconnect;
    config.production_security = Some(replacement);
    let restarted = RunningAsyncOpcUaServer::start(config)
        .await
        .expect("start rotated server");
    loop {
        match client
            .next_event(Duration::from_secs(15))
            .await
            .expect("event")
        {
            ClientEvent::Reconnected { .. } => {
                panic!("stale certificate thumbprint must not reconnect automatically")
            }
            ClientEvent::SubscriptionError { reason, .. } => {
                assert!(reason.contains("BadNoValidCertificates"), "{reason}");
                assert!(reason.contains("fresh discovery"));
                break;
            }
            _ => {}
        }
    }
    // Certificate rotation deliberately requires fresh discovery. The new
    // client uses the same explicit trust store, now containing the rotated
    // certificate; no certificate is trusted automatically.
    let reconnected = AsyncOpcUaClient::connect(&fixture.client_options(restarted.endpoint()))
        .await
        .expect("fresh client after trusted rotation");
    let observation = reconnected.read(&metric).await.expect("rotated read");
    assert_eq!(observation.quality, DataQuality::Good);
    reconnected
        .subscribe(std::slice::from_ref(&metric))
        .await
        .expect("rotated subscribe");
    loop {
        if matches!(
            reconnected
                .next_event(Duration::from_secs(10))
                .await
                .expect("post-rotation event"),
            ClientEvent::Observation(_)
        ) {
            break;
        }
    }
    reconnected.disconnect().await.expect("disconnect");
    restarted.stop().await.expect("stop replacement");
}

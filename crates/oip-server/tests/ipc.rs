#![cfg(unix)]
use oip_server::{
    application_services::ApplicationServices,
    config::{CoreConfig, SourceConfig},
    mcp::ipc::{local_uid, LocalIpc},
    state::AppState,
};
use oip_storage::SqliteStore;
use rmcp::{
    model::*,
    service::{ClientLifecycleMode, ClientServiceExt},
};
use serde_json::{json, Value};
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::UnixStream,
};
use tokio_util::sync::CancellationToken;
struct Fixture {
    dir: PathBuf,
    config: PathBuf,
    socket: PathBuf,
}
impl Fixture {
    fn new() -> Self {
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::current_dir()
            .unwrap()
            .join(format!(
                "../../target/i7-{}-{}",
                std::process::id(),
                SEQ.fetch_add(1, Ordering::Relaxed)
            ))
            .canonicalize_parent();
        std::fs::create_dir(&dir).unwrap();
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).unwrap();
        let socket = dir.join("s");
        let config = dir.join("c.json");
        let uid = local_uid().unwrap();
        let all: Value =
            serde_json::from_str(include_str!("../../../examples/mcp-read-local.json")).unwrap();
        let clients = (1..=3)
            .map(|n| {
                let token = dir.join(format!("t{n}"));
                std::fs::write(&token, [n; 32]).unwrap();
                std::fs::set_permissions(&token, std::fs::Permissions::from_mode(0o600)).unwrap();
                let mut p = all.clone();
                p["actor"] = json!(format!("client-{n}"));
                if n > 1 {
                    p["sources"] =
                        json!({"kind":"only","sources":[if n==2 {"sim-a"}else{"sim-b"}]});
                }
                json!({"uid":uid,"credential_file":token,"policy":p})
            })
            .collect::<Vec<_>>();
        std::fs::write(
            &config,
            json!({"socket":socket,"clients":clients,"max_sessions":8,"rest_policy":all})
                .to_string(),
        )
        .unwrap();
        std::fs::set_permissions(&config, std::fs::Permissions::from_mode(0o600)).unwrap();
        Self {
            dir,
            config,
            socket,
        }
    }
    fn edit(&self, f: impl FnOnce(&mut Value)) {
        let mut v = serde_json::from_slice(&std::fs::read(&self.config).unwrap()).unwrap();
        f(&mut v);
        std::fs::write(&self.config, v.to_string()).unwrap();
    }
}
trait CanonicalParent {
    fn canonicalize_parent(self) -> PathBuf;
}
impl CanonicalParent for PathBuf {
    fn canonicalize_parent(self) -> PathBuf {
        self.parent()
            .unwrap()
            .canonicalize()
            .unwrap()
            .join(self.file_name().unwrap())
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}
async fn auth(f: &Fixture, n: u8) -> UnixStream {
    let mut s = UnixStream::connect(&f.socket).await.unwrap();
    s.write_all(b"OIPIPC1\n").await.unwrap();
    s.write_all(&[n; 32]).await.unwrap();
    let mut b = [0];
    s.read_exact(&mut b).await.unwrap();
    assert_eq!(b, [1]);
    s
}
fn service() -> (AppState, Arc<ApplicationServices>) {
    let c = CoreConfig {
        sources: vec![
            SourceConfig {
                id: "sim-a".into(),
                name: "A".into(),
                endpoint: "opc.tcp://127.0.0.1:15841".into(),
                namespace: 2,
            },
            SourceConfig {
                id: "sim-b".into(),
                name: "B".into(),
                endpoint: "opc.tcp://127.0.0.1:15842".into(),
                namespace: 2,
            },
        ],
        ..Default::default()
    };
    let s = AppState::configured(SqliteStore::open_in_memory().unwrap(), &c, None).unwrap();
    (s.clone(), Arc::new(ApplicationServices::new(s)))
}
#[tokio::test]
async fn three_real_sdk_sessions_have_independent_scopes_and_disconnect_does_not_stop_owner() {
    let f = Fixture::new();
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    let (state, svc) = service();
    state.started().await.unwrap();
    let stop = CancellationToken::new();
    let task = tokio::spawn(ipc.run(svc, stop.clone()));
    let mut clients = Vec::new();
    for n in 1..=3 {
        let stream = auth(&f, n).await;
        clients.push(
            ().serve_with_lifecycle(
                stream,
                ClientLifecycleMode::Discover {
                    preferred_versions: vec![ProtocolVersion::V_2026_07_28],
                },
            )
            .await
            .unwrap(),
        );
    }
    // Modern Discover must survive legitimate idle before first tool.
    tokio::time::sleep(Duration::from_millis(5200)).await;
    assert_eq!(clients[0].list_tools(None).await.unwrap().tools.len(), 6);
    let allowed = clients[1]
        .call_tool(
            CallToolRequestParams::new("oip_sources_read")
                .with_arguments(json!({"source":"sim-a"}).as_object().unwrap().clone()),
        )
        .await
        .unwrap();
    assert_ne!(allowed.is_error, Some(true));
    let denied = clients[1]
        .call_tool(
            CallToolRequestParams::new("oip_sources_read")
                .with_arguments(json!({"source":"sim-b"}).as_object().unwrap().clone()),
        )
        .await
        .unwrap();
    assert_eq!(denied.is_error, Some(true));
    let snapshot = clients[2]
        .read_resource(ReadResourceRequestParams::new("oip://v1/snapshot/current"))
        .await;
    assert!(snapshot.is_err());
    clients.remove(0).close().await.unwrap();
    assert!(!task.is_finished());
    assert!(state.view().health.live);
    assert_eq!(clients[0].list_tools(None).await.unwrap().tools.len(), 6);
    for mut c in clients {
        c.close().await.unwrap();
    }
    stop.cancel();
    tokio::time::timeout(Duration::from_secs(6), task)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(!f.socket.exists());
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn bad_credential_and_partial_auth_are_isolated_from_valid_sessions() {
    let f = Fixture::new();
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    let (s, svc) = service();
    let stop = CancellationToken::new();
    let t = tokio::spawn(ipc.run(svc, stop.clone()));
    let mut bad = UnixStream::connect(&f.socket).await.unwrap();
    bad.write_all(b"OIPIPC1\n").await.unwrap();
    bad.write_all(&[8; 32]).await.unwrap();
    let mut b = [0];
    assert_eq!(bad.read(&mut b).await.unwrap(), 0);
    let _partial = UnixStream::connect(&f.socket).await.unwrap();
    let good = auth(&f, 1).await;
    drop(good);
    assert!(!t.is_finished());
    stop.cancel();
    tokio::time::timeout(Duration::from_secs(6), t)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn protected_paths_permissions_symlinks_and_regular_socket_targets_are_rejected() {
    let f = Fixture::new();
    std::fs::set_permissions(&f.dir, std::fs::Permissions::from_mode(0o755)).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    std::fs::set_permissions(&f.dir, std::fs::Permissions::from_mode(0o700)).unwrap();
    std::fs::set_permissions(&f.config, std::fs::Permissions::from_mode(0o644)).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    std::fs::set_permissions(&f.config, std::fs::Permissions::from_mode(0o600)).unwrap();
    let link = f.dir.join("link");
    std::os::unix::fs::symlink(f.dir.join("t1"), &link).unwrap();
    f.edit(|v| v["clients"][0]["credential_file"] = json!(link));
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    f.edit(|v| v["clients"][0]["credential_file"] = json!(f.dir.join("t1")));
    std::os::unix::fs::symlink(f.dir.join("t1"), &f.socket).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    assert!(std::fs::symlink_metadata(&f.socket)
        .unwrap()
        .file_type()
        .is_symlink());
    std::fs::remove_file(&f.socket).unwrap();
    std::fs::write(&f.socket, b"operator-owned").unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    assert_eq!(std::fs::read(&f.socket).unwrap(), b"operator-owned");
}
#[tokio::test]
async fn endpoint_single_owner_stale_recovery_and_inode_safe_cleanup() {
    let f = Fixture::new();
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    drop(ipc);
    assert!(!f.socket.exists());
    let stale = std::os::unix::net::UnixListener::bind(&f.socket).unwrap();
    drop(stale);
    // Fixture for a crashed cooperating owner; the process E2E also performs
    // an actual SIGKILL and recovers the real sidecar record.
    use std::os::unix::fs::MetadataExt;
    let m = std::fs::metadata(&f.socket).unwrap();
    std::fs::write(
        f.socket.with_extension("ipc-lock"),
        serde_json::to_vec(&(m.dev(), m.ino(), m.ctime(), m.ctime_nsec())).unwrap(),
    )
    .unwrap();
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    std::fs::remove_file(&f.socket).unwrap();
    std::fs::write(&f.socket, b"replaced-by-operator").unwrap();
    drop(ipc);
    assert_eq!(std::fs::read(&f.socket).unwrap(), b"replaced-by-operator");
}
#[tokio::test]
async fn invalid_identity_duplicate_credentials_mutation_and_limits_are_rejected() {
    let f = Fixture::new();
    f.edit(|v| v["clients"][0]["uid"] = json!(u32::MAX));
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    f.edit(|v| v["clients"][0]["uid"] = json!(local_uid().unwrap()));
    f.edit(|v| v["max_sessions"] = json!(0));
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    f.edit(|v| v["max_sessions"] = json!(8));
    f.edit(|v| v["clients"][1]["credential_file"] = v["clients"][0]["credential_file"].clone());
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    f.edit(|v| v["clients"][1]["credential_file"] = json!(f.dir.join("t2")));
    f.edit(|v| {
        v["clients"][0]["policy"]["permissions"]
            .as_array_mut()
            .unwrap()
            .push(json!("simulation_control"))
    });
    assert!(LocalIpc::prepare(&f.config).await.is_err());
}
#[tokio::test]
async fn session_limit_is_bounded_and_slots_are_reclaimed() {
    let f = Fixture::new();
    f.edit(|v| v["max_sessions"] = json!(1));
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    let (s, svc) = service();
    let stop = CancellationToken::new();
    let t = tokio::spawn(ipc.run(svc, stop.clone()));
    let first = auth(&f, 1).await;
    let mut second = UnixStream::connect(&f.socket).await.unwrap();
    let mut b = [0];
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(2), second.read(&mut b))
            .await
            .unwrap()
            .unwrap(),
        0
    );
    drop(first);
    tokio::time::sleep(Duration::from_millis(100)).await;
    drop(auth(&f, 2).await);
    stop.cancel();
    t.await.unwrap().unwrap();
    assert!(s.shutdown().await.clean);
}

#[tokio::test]
async fn active_uncooperative_socket_is_never_unlinked_and_legacy_initialize_works() {
    let f = Fixture::new();
    let live = std::os::unix::net::UnixListener::bind(&f.socket).unwrap();
    let start = std::time::Instant::now();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    assert!(start.elapsed() < Duration::from_secs(2));
    assert!(f.socket.exists());
    drop(live);
    std::fs::remove_file(&f.socket).unwrap();
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    let (s, svc) = service();
    let stop = CancellationToken::new();
    let t = tokio::spawn(ipc.run(svc, stop.clone()));
    let mut client =
        ().serve_with_lifecycle(auth(&f, 1).await, ClientLifecycleMode::Initialize)
            .await
            .unwrap();
    assert_eq!(client.list_tools(None).await.unwrap().tools.len(), 6);
    client.close().await.unwrap();
    stop.cancel();
    t.await.unwrap().unwrap();
    assert!(s.shutdown().await.clean);
}

#[tokio::test]
async fn ipc_cancellation_and_disconnect_drop_pending_service_futures() {
    use oip_core::*;
    use std::sync::atomic::AtomicUsize;
    struct Pending(Arc<AtomicUsize>);
    struct Guard(Arc<AtomicUsize>);
    impl Drop for Guard {
        fn drop(&mut self) {
            self.0.fetch_sub(1, Ordering::SeqCst);
        }
    }
    impl CapabilityService for Pending {
        fn execute<'a>(
            &'a self,
            _: &'a ExecutionContext,
            _: CapabilityRequest,
        ) -> std::pin::Pin<
            Box<
                dyn std::future::Future<Output = Result<CapabilityOutput, CapabilityError>>
                    + Send
                    + 'a,
            >,
        > {
            Box::pin(async move {
                self.0.fetch_add(1, Ordering::SeqCst);
                let _guard = Guard(self.0.clone());
                std::future::pending().await
            })
        }
    }
    let f = Fixture::new();
    let ipc = LocalIpc::prepare(&f.config).await.unwrap();
    let active = Arc::new(AtomicUsize::new(0));
    let stop = CancellationToken::new();
    let t = tokio::spawn(ipc.run(Arc::new(Pending(active.clone())), stop.clone()));
    let mut client =
        ().serve_with_lifecycle(auth(&f, 1).await, ClientLifecycleMode::Initialize)
            .await
            .unwrap();
    let pending = client
        .peer()
        .send_cancellable_request(
            CallToolRequest::new(CallToolRequestParams::new("oip_sources_read")).into(),
            rmcp::service::PeerRequestOptions::no_options(),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while active.load(Ordering::SeqCst) != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    client
        .peer()
        .send_notification(
            CancelledNotification::new(CancelledNotificationParam::new(
                Some(pending.id.clone()),
                None,
            ))
            .into(),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while active.load(Ordering::SeqCst) != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let _request = client
        .peer()
        .send_cancellable_request(
            CallToolRequest::new(CallToolRequestParams::new("oip_sources_read")).into(),
            rmcp::service::PeerRequestOptions::no_options(),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(2), async {
        while active.load(Ordering::SeqCst) != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    client.close().await.unwrap();
    tokio::time::timeout(Duration::from_secs(4), async {
        while active.load(Ordering::SeqCst) != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert!(!t.is_finished());
    stop.cancel();
    t.await.unwrap().unwrap();
}

#[tokio::test]
async fn credentials_and_lock_hardlinks_and_bad_modes_are_refused() {
    let f = Fixture::new();
    let token = f.dir.join("t1");
    let link = f.dir.join("hard");
    std::fs::hard_link(&token, &link).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    std::fs::remove_file(&link).unwrap();
    std::fs::set_permissions(&token, std::fs::Permissions::from_mode(0o644)).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    std::fs::set_permissions(&token, std::fs::Permissions::from_mode(0o600)).unwrap();
    std::fs::write(&token, [1; 33]).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    std::fs::write(&token, [1; 32]).unwrap();
    let lock = f.socket.with_extension("ipc-lock");
    std::os::unix::fs::symlink(&token, &lock).unwrap();
    assert!(LocalIpc::prepare(&f.config).await.is_err());
    assert_eq!(std::fs::read(&token).unwrap(), [1; 32]);
}

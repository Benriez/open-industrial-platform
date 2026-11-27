use oip_server::{
    api,
    application_services::ApplicationServices,
    config::CoreConfig,
    mcp::{transport::BoundedTransport, McpAdapter, McpPolicy},
    runtime::CoreRuntime,
};
use rmcp::ServiceExt;
use std::sync::Arc;
use std::{
    error::Error,
    net::{Ipv4Addr, SocketAddrV4},
    time::Duration,
};
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;
fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt()
        .json()
        .with_writer(std::io::stderr)
        .with_env_filter(
            if std::env::args().any(|a| {
                matches!(
                    a.as_str(),
                    "--mcp-stdio" | "--mcp-bridge" | "--daemon" | "--browser-login"
                )
            }) {
                // SDK trace/debug can contain complete untrusted requests. Do not
                // allow a more specific RUST_LOG directive to override redaction.
                tracing_subscriber::EnvFilter::new("warn,oip_server=info,rmcp=off")
            } else {
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn,oip_server=info"))
            },
        )
        .try_init()
        .ok();
    let executor = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    let result = executor.block_on(tokio::task::LocalSet::new().run_until(run()));
    // macOS stdin uses Tokio's blocking read; signals must not wait forever for it.
    executor.shutdown_timeout(Duration::from_secs(2));
    result
}
async fn signal() {
    #[cfg(unix)]
    {
        let mut terminate =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
                .expect("signal handler");
        tokio::select! {_=tokio::signal::ctrl_c()=>{},_=terminate.recv()=>{}}
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
async fn run() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args
        .first()
        .is_some_and(|arg| arg == "--check-license-policy")
    {
        let allow_no_trusted_keys = match &args[1..] {
            [] => false,
            [option] if option == "--allow-no-trusted-keys" => true,
            _ => {
                return Err(
                    "usage: --check-license-policy [--allow-no-trusted-keys] < POLICY.json".into(),
                )
            }
        };
        oip_server::check_license_policy(std::io::stdin().lock(), allow_no_trusted_keys)?;
        return Ok(());
    }
    // Bridge mode is parsed and returned before config, DB or CoreRuntime access.
    if args.iter().any(|a| a == "--mcp-bridge") {
        #[cfg(unix)]
        {
            if args.len() != 5
                || args[0] != "--mcp-bridge"
                || args[1] != "--ipc-socket"
                || args[3] != "--ipc-credential"
            {
                return Err(
                    "bridge usage: --mcp-bridge --ipc-socket ABS --ipc-credential ABS".into(),
                );
            }
            tokio::select! { result=oip_server::mcp::ipc::bridge(std::path::Path::new(&args[2]),std::path::Path::new(&args[4]))=>result?,_=signal()=>{} }
            return Ok(());
        }
        #[cfg(not(unix))]
        {
            return Err("local IPC is currently supported on Unix only".into());
        }
    }
    if args.first().is_some_and(|a| a == "--browser-login") {
        #[cfg(unix)]
        {
            if args.len() != 5 || args[1] != "--ipc-socket" || args[3] != "--ipc-credential" {
                return Err(
                    "browser-login usage: --browser-login --ipc-socket ABS --ipc-credential ABS"
                        .into(),
                );
            }
            let value = oip_server::mcp::ipc::browser_login(
                std::path::Path::new(&args[2]),
                std::path::Path::new(&args[4]),
            )
            .await?;
            println!("{value}");
            return Ok(());
        }
        #[cfg(not(unix))]
        return Err("local browser login currently supports Unix only".into());
    }
    let daemon = args.iter().any(|a| a == "--daemon");
    let mut ipc_config = None;
    let mut config = CoreConfig::default();
    if let Some(i) = args.iter().position(|a| a == "--config") {
        config = serde_json::from_slice(&std::fs::read(
            args.get(i + 1).ok_or("missing config path")?,
        )?)?;
    }
    let mcp = args.iter().any(|a| a == "--mcp-stdio");
    let mcp_rest = args.iter().any(|a| a == "--mcp-rest");
    let mut inventory_initialize = None;
    let mut inventory_plan = None;
    let mut inventory_query = None;
    let mut inventory_inspect = None;
    let mut inventory_apply = false;
    let mut settings_change = None;
    let mut provision = None;
    let mut adoption = None;
    let mut inspect_legacy = false;
    let mut policy_path = None;
    let mut demo = false;
    let mut opcua_port = 4840;
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        i += 1;
        match arg.as_str() {
            "--mcp-stdio" | "--mcp-rest" | "--daemon" => continue,
            "--inventory-apply" => {
                inventory_apply = true;
                continue;
            }
            "--inspect-legacy" => {
                inspect_legacy = true;
                continue;
            }
            "--legacy-single-infrastructure" => {
                config.legacy_single_infrastructure = true;
                continue;
            }
            "--demo" => {
                config.legacy_single_infrastructure = true;
                demo = true;
                continue;
            }
            "--no-web" => {
                config.web_dir = None;
                continue;
            }
            _ => {}
        }
        let value = args.get(i).ok_or("missing argument value")?;
        i += 1;
        match arg.as_str() {
            "--inventory-initialize" => inventory_initialize = Some(value.clone()),
            "--inventory-plan" => inventory_plan = Some(value.clone()),
            "--inventory-query" => inventory_query = Some(value.clone()),
            "--inventory-cleanup-plan" => inventory_inspect = Some(value.clone()),
            "--settings-change" => settings_change = Some(value.clone()),
            "--provision" => provision = Some(value.clone()),
            "--adopt-legacy" => adoption = Some(value.clone()),
            "--config" => {}
            "--mcp-policy" => policy_path = Some(value.clone()),
            "--ipc-config" => ipc_config = Some(std::path::PathBuf::from(value)),
            "--port" => config.http_port = value.parse()?,
            "--opcua-port" => {
                opcua_port = value.parse()?;
                config.sources = vec![oip_server::config::SourceConfig::primary(opcua_port)];
            }
            "--database" => config.database = value.into(),
            "--web-dir" => config.web_dir = Some(value.clone()),
            _ => return Err(format!("unknown argument: {arg}").into()),
        }
    }
    if config.legacy_single_infrastructure
        && !args.iter().any(|a| a == "--database" || a == "--config")
    {
        return Err(
            "explicit simulation/legacy mode requires an isolated --database or --config".into(),
        );
    }
    if config.legacy_single_infrastructure && config.sources.is_empty() {
        config.sources = vec![oip_server::config::SourceConfig::primary(opcua_port)];
    }
    config.validate()?;
    let inventory_modes = [
        inventory_initialize.is_some(),
        inventory_plan.is_some(),
        inventory_query.is_some(),
        inventory_inspect.is_some(),
    ]
    .into_iter()
    .filter(|v| *v)
    .count();
    if inventory_modes > 1 || inventory_apply && inventory_plan.is_none() {
        return Err("select one inventory operator mode; apply requires plan".into());
    }
    if inventory_modes != 0 {
        if daemon
            || mcp
            || mcp_rest
            || demo
            || ipc_config.is_some()
            || policy_path.is_some()
            || provision.is_some()
            || adoption.is_some()
            || inspect_legacy
            || settings_change.is_some()
        {
            return Err("inventory administration is offline only".into());
        }
        let read = |path: String| -> Result<Vec<u8>, Box<dyn Error>> {
            use std::io::Read;
            let f = std::fs::File::open(path)?;
            let mut b = Vec::new();
            f.take(1_048_577).read_to_end(&mut b)?;
            if b.len() > 1_048_576 {
                return Err("inventory request too large".into());
            }
            Ok(b)
        };
        if let Some(path) = inventory_initialize {
            #[derive(serde::Deserialize)]
            #[serde(deny_unknown_fields)]
            struct Init {
                principal: oip_core::PrincipalId,
            }
            let q: Init = serde_json::from_slice(&read(path)?)
                .map_err(|_| "invalid inventory initialization")?;
            let version = oip_storage::SqliteStore::inventory_initialize_file(
                &config.database,
                &q.principal,
            )?;
            println!(
                "{}",
                serde_json::json!({"schema":version,"initialized":true,"devices_created_from_names":false})
            );
            return Ok(());
        }
        if let Some(path) = inventory_plan {
            let request =
                serde_json::from_slice(&read(path)?).map_err(|_| "invalid typed inventory plan; updates require complete metadata and expected revision")?;
            let result = oip_storage::SqliteStore::inventory_admin_file(
                &config.database,
                request,
                inventory_apply,
                oip_server::state::now_ms(),
            )?;
            println!("{}", serde_json::to_string(&result)?);
            return Ok(());
        }
        #[derive(serde::Deserialize)]
        #[serde(deny_unknown_fields)]
        struct LocalQuery {
            principal: oip_core::PrincipalId,
            #[serde(default)]
            query: oip_core::InventoryQuery,
        }
        if let Some(path) = inventory_inspect {
            let q: LocalQuery =
                serde_json::from_slice(&read(path)?).map_err(|_| "invalid inventory inspection")?;
            let result =
                oip_storage::SqliteStore::inventory_inspect_file(&config.database, &q.principal)?;
            println!("{}", serde_json::to_string(&result)?);
            return Ok(());
        }
        if let Some(path) = inventory_query {
            let q: LocalQuery =
                serde_json::from_slice(&read(path)?).map_err(|_| "invalid inventory query")?;
            let (h, rows) = oip_storage::SqliteStore::inventory_snapshot_file(&config.database)?;
            let context = oip_core::ExecutionContext {
                actor: q.principal.to_string(),
                principal: Some(q.principal),
                correlation_id: format!("offline-inventory-{}", std::process::id()),
                permissions: Default::default(),
                sources: oip_core::SourceScope::Only(Default::default()),
            };
            let result = oip_server::inventory_services::inventory_projection(
                Some(&h),
                &rows,
                &[],
                &context,
                q.query,
            )?;
            println!("{}", serde_json::to_string(&result)?);
            return Ok(());
        }
    }
    if let Some(path) = settings_change {
        if daemon
            || mcp
            || mcp_rest
            || demo
            || ipc_config.is_some()
            || policy_path.is_some()
            || provision.is_some()
            || adoption.is_some()
            || inspect_legacy
        {
            return Err("settings administration is offline only".into());
        }
        let file = std::fs::File::open(path)?;
        use std::io::Read;
        let mut bytes = Vec::new();
        file.take(4097).read_to_end(&mut bytes)?;
        if bytes.len() > 4096 {
            return Err("settings change too large".into());
        }
        let change = serde_json::from_slice(&bytes).map_err(|_| "invalid typed settings change")?;
        let result = oip_storage::SqliteStore::change_settings_file(
            &config.database,
            change,
            oip_server::state::now_ms(),
        )?;
        println!("{}", serde_json::to_string(&result)?);
        return Ok(());
    }
    if (inspect_legacy || provision.is_some() || adoption.is_some())
        && (daemon || mcp || mcp_rest || ipc_config.is_some() || policy_path.is_some() || demo)
    {
        return Err("offline provisioning/inspection cannot be combined with runtime modes".into());
    }
    if inspect_legacy && (provision.is_some() || adoption.is_some()) {
        return Err("inspection and provisioning are separate operator steps".into());
    }
    if inspect_legacy {
        println!(
            "{}",
            serde_json::to_string_pretty(&oip_storage::SqliteStore::inspect_legacy(
                &config.database
            )?)?
        );
        return Ok(());
    }
    if let Some(path) = provision {
        let bytes = std::fs::read(path)?;
        if bytes.len() > 1_048_576 {
            return Err("provisioning plan too large".into());
        }
        let plan = serde_json::from_slice(&bytes)?;
        let adoption: Option<oip_storage::LegacyAdoption> = adoption
            .map(|p| {
                std::fs::read(p)
                    .and_then(|b| serde_json::from_slice(&b).map_err(std::io::Error::other))
            })
            .transpose()?;
        let definitions = config
            .sources
            .iter()
            .map(|s| s.definition())
            .collect::<Result<Vec<_>, _>>()?;
        let external_sources = definitions
            .iter()
            .filter(|definition| definition.origin_class == oip_core::OriginClass::External)
            .map(|definition| definition.id.clone())
            .collect();
        let result = oip_storage::SqliteStore::provision_file_with_external_sources(
            &config.database,
            plan,
            &definitions,
            &external_sources,
            adoption.as_ref(),
        )?;
        println!("{}", serde_json::to_string(&result)?);
        return Ok(());
    }
    if adoption.is_some() {
        return Err("--adopt-legacy requires --provision".into());
    }
    if daemon && (mcp || mcp_rest || policy_path.is_some() || demo) {
        return Err(
            "daemon cannot use stdio-owned core, MCP policy or embedded demo control".into(),
        );
    }
    if !daemon && ipc_config.is_some() {
        return Err("--ipc-config requires --daemon".into());
    }
    if daemon && !config.database.is_absolute() {
        return Err("daemon requires an absolute database path".into());
    }
    #[cfg(unix)]
    let ipc = if daemon {
        Some(
            oip_server::mcp::ipc::LocalIpc::prepare(
                &ipc_config.ok_or("--daemon requires protected --ipc-config")?,
            )
            .await?,
        )
    } else {
        None
    };
    #[cfg(not(unix))]
    if daemon {
        return Err("local IPC daemon currently supports Unix only".into());
    }

    if !mcp && (mcp_rest || policy_path.is_some()) {
        return Err("MCP flags require --mcp-stdio".into());
    }
    let policy: Option<McpPolicy> = if mcp {
        if !config.database.is_absolute() {
            return Err("MCP requires an explicit absolute database path; use --database to select the canonical core data store".into());
        }
        let path = policy_path.ok_or("--mcp-stdio requires a trusted --mcp-policy file")?;
        let bytes = std::fs::read(path)?;
        if bytes.len() > 16384 {
            return Err("MCP policy file too large".into());
        }
        let policy: McpPolicy =
            serde_json::from_slice(&bytes).map_err(|_| "Invalid MCP policy file")?;
        policy.validate()?;
        if demo {
            return Err("MCP mode does not allow embedded demo scenario control".into());
        }
        Some(policy)
    } else {
        None
    };
    if demo
        && (config.sources.len() != 1
            || config.sources[0].id != oip_simulator::SIMULATION_ORIGIN_ID)
    {
        return Err("--demo requires the single legacy simulation profile".into());
    }
    #[cfg(unix)]
    let stdio_output = if mcp {
        Some(oip_server::mcp::transport::protocol_stdout()?)
    } else {
        None
    };
    // Bind before starting background resources: a bind failure cannot orphan workers.
    let listener = if !mcp || mcp_rest {
        Some(
            tokio::net::TcpListener::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, config.http_port))
                .await?,
        )
    } else {
        None
    };
    let (tx, rx) = watch::channel("normal".to_owned());
    let runtime = CoreRuntime::start(config.clone(), if demo { Some(tx) } else { None }).await?;
    let state = runtime.state.clone();
    {
        let mut info = state.management.lock().map_err(|_| "management lock")?;
        info.mcp_mode = if daemon {
            "local_ipc"
        } else if mcp {
            "stdio_owned"
        } else {
            "unavailable"
        }
        .into();
        #[cfg(unix)]
        if let Some(ipc) = &ipc {
            info.session_limit = Some(ipc.session_limit());
        }
    }
    let stop = CancellationToken::new();
    let simulator = if demo {
        let c = stop.clone();
        Some(tokio::task::spawn_local(
            oip_server::collector::supervised_simulator(opcua_port, rx, c),
        ))
    } else {
        None
    };
    let service = Arc::new(ApplicationServices::new(state.clone()));
    let rest_authority = policy.as_ref().map(McpPolicy::execution_context);
    #[cfg(unix)]
    let rest_authority = ipc
        .as_ref()
        .and_then(|i| i.rest_context())
        .or(rest_authority);
    #[cfg(unix)]
    let credentials = ipc
        .as_ref()
        .map(|i| i.rest_identities())
        .unwrap_or_default();
    #[cfg(not(unix))]
    let credentials = oip_server::identity::RestIdentities::default();
    #[cfg(unix)]
    if let Some(i) = &ipc {
        if let Err(e) = i.validate_principals(&state) {
            runtime.shutdown().await;
            return Err(e.into());
        }
    }
    let adapter = policy
        .map(|p| McpAdapter::new(service.clone(), p))
        .transpose()?;
    let app = api::router_with_identity(
        state.clone(),
        service.clone(),
        rest_authority,
        credentials,
        config.web_dir.as_deref(),
    );
    let http_cancel = stop.clone();
    let mut http = tokio::spawn(async move {
        if let Some(listener) = listener {
            axum::serve(listener, app)
                .with_graceful_shutdown(http_cancel.cancelled_owned())
                .await
        } else {
            http_cancel.cancelled().await;
            Ok(())
        }
    });
    tracing::info!(
        port = config.http_port,
        sources = config.sources.len(),
        code = "core_started",
        security_blocker = "RUSTSEC-2024-0449",
        "loopback simulation core; frontend optional"
    );
    let transport_stop = CancellationToken::new();
    let mcp_stop = transport_stop.clone();
    let browser_sessions = state.browser_sessions.clone();
    let mcp_run = async move {
        #[cfg(unix)]
        if let Some(ipc) = ipc {
            if ipc
                .run_with_browser(service, mcp_stop.clone(), browser_sessions)
                .await
                .is_err()
            {
                tracing::error!(code = "ipc_listener_failed", "local IPC listener failed");
            }
            return;
        }
        if let Some(adapter) = adapter {
            #[cfg(unix)]
            let output = stdio_output.expect("validated stdio mode owns output pipe");
            #[cfg(not(unix))]
            let output = tokio::io::stdout();
            let transport = BoundedTransport::new(tokio::io::stdin(), output);
            match adapter.serve_with_ct(transport, mcp_stop.clone()).await {
                Ok(server) => {
                    let cancellation = server.cancellation_token();
                    tokio::select! { result=server.waiting()=> {tracing::info!(ok=result.is_ok(),code="mcp_closed","stdio client ended");}, _=mcp_stop.cancelled()=> {cancellation.cancel();} }
                }
                Err(_) => tracing::warn!(
                    code = "mcp_start_failed",
                    "stdio initialization failed or client disconnected"
                ),
            }
        } else {
            mcp_stop.cancelled().await;
        }
    };
    tokio::pin!(mcp_run);
    let mut ipc_finished = false;
    let http_failed = tokio::select! {_=signal()=>false,_=&mut mcp_run=>{ipc_finished=true;daemon},result=&mut http=>{tracing::error!(?result,code="http_task_ended","HTTP service ended");true}};
    transport_stop.cancel();
    // Persistent owner joins transport sessions before draining its one writer.
    if daemon && !ipc_finished {
        let _ = (&mut mcp_run).await;
    }
    state.stopping.cancel();
    let report = runtime.shutdown().await;
    stop.cancel();
    if let Some(mut task) = simulator {
        if tokio::time::timeout(Duration::from_secs(5), &mut task)
            .await
            .is_err()
        {
            task.abort();
            tracing::error!(
                code = "simulator_shutdown_timeout",
                "local simulator did not finish"
            );
        }
    }
    let http_finished = if http.is_finished() {
        true
    } else {
        match tokio::time::timeout(Duration::from_secs(3), &mut http).await {
            Ok(Ok(Ok(()))) => true,
            _ => {
                http.abort();
                let _ = (&mut http).await;
                tracing::warn!(
                    code = "http_drain_deadline",
                    http_forced_close = true,
                    "slow HTTP clients closed after data drain; clients must resynchronize"
                );
                false
            }
        }
    };
    #[derive(serde::Serialize)]
    struct ProcessShutdown {
        #[serde(flatten)]
        core: oip_server::state::ShutdownReport,
        http_drained: bool,
        http_forced_close: bool,
    }
    let clean = report.clean;
    let shutdown_json = serde_json::to_string(&ProcessShutdown {
        core: report,
        http_drained: http_finished,
        http_forced_close: !http_finished,
    })?;
    if mcp {
        eprintln!("{shutdown_json}");
    } else {
        println!("{shutdown_json}");
    }
    if !clean || http_failed {
        return Err("core shutdown incomplete; inspect structured report".into());
    }
    Ok(())
}

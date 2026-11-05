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
            if std::env::args()
                .any(|a| matches!(a.as_str(), "--mcp-stdio" | "--mcp-bridge" | "--daemon"))
            {
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
    let mut policy_path = None;
    let mut demo = false;
    let mut opcua_port = 4840;
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        i += 1;
        match arg.as_str() {
            "--mcp-stdio" | "--mcp-rest" | "--daemon" => continue,
            "--demo" => {
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
    config.validate()?;
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
    let rest_authority = ipc.as_ref().map(|i| i.rest_context()).or(rest_authority);
    let adapter = policy
        .map(|p| McpAdapter::new(service.clone(), p))
        .transpose()?;
    let app = api::router_with_service(
        state.clone(),
        service.clone(),
        rest_authority,
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
        security_blocker = "RUSTSEC-2023-0071",
        "loopback simulation core; frontend optional"
    );
    let transport_stop = CancellationToken::new();
    let mcp_stop = transport_stop.clone();
    let mcp_run = async move {
        #[cfg(unix)]
        if let Some(ipc) = ipc {
            if ipc.run(service, mcp_stop.clone()).await.is_err() {
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

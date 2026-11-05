//! Model-free interoperability client using the official SDK against a real stdio process.
use rmcp::{
    model::*,
    service::{ClientLifecycleMode, ClientServiceExt},
};
use serde_json::{json, Value};
use std::{error::Error, process::Stdio, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    process::Command,
};
#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let mut child = Command::new(&args[1])
        .args(&args[2..])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()?;
    let lifecycle = if args[0] == "legacy" {
        ClientLifecycleMode::Initialize
    } else {
        ClientLifecycleMode::Discover {
            preferred_versions: vec![ProtocolVersion::V_2026_07_28],
        }
    };
    let config = ClientConfig::new(
        ClientCapabilities::default(),
        Implementation::new("oip-sdk-verifier", "1"),
    )
    .with_protocol_version(ProtocolVersion::V_2025_11_25);
    let mut client = config
        .serve_with_lifecycle(
            (child.stdout.take().unwrap(), child.stdin.take().unwrap()),
            lifecycle,
        )
        .await?;
    println!(
        "{}",
        json!({"ready":true,"pid":child.id(),"peer":client.peer().peer_info().as_deref()})
    );
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    while let Some(line) = lines.next_line().await? {
        let command: Value = serde_json::from_str(&line)?;
        let result: Result<Value, rmcp::service::ServiceError> =
            match command["op"].as_str().unwrap_or("") {
                "batch" => {
                    let futures = (0..8).map(|_| {
                        client
                            .peer()
                            .call_tool(CallToolRequestParams::new("oip_sources_read"))
                    });
                    let results = futures::future::join_all(futures).await;
                    Ok(serde_json::to_value(
                        results
                            .into_iter()
                            .map(|r| {
                                r.map(|v| serde_json::to_value(v).unwrap())
                                    .map_err(|e| e.to_string())
                            })
                            .collect::<Vec<_>>(),
                    )
                    .unwrap())
                }
                "tools" => client
                    .peer()
                    .list_tools(None)
                    .await
                    .map(|v| serde_json::to_value(v).unwrap()),
                "resources" => client
                    .peer()
                    .list_resources(None)
                    .await
                    .map(|v| serde_json::to_value(v).unwrap()),
                "resource" => client
                    .peer()
                    .read_resource(ReadResourceRequestParams::new(
                        command["uri"].as_str().unwrap(),
                    ))
                    .await
                    .map(|v| serde_json::to_value(v).unwrap()),
                "call" => client
                    .peer()
                    .call_tool(
                        CallToolRequestParams::new(command["name"].as_str().unwrap().to_owned())
                            .with_arguments(
                                command["arguments"]
                                    .as_object()
                                    .cloned()
                                    .unwrap_or_default(),
                            ),
                    )
                    .await
                    .map(|v| serde_json::to_value(v).unwrap()),
                _ => break,
            };
        println!(
            "{}",
            match result {
                Ok(v) => json!({"ok":true,"result":v}),
                Err(e) => json!({"ok":false,"error":e.to_string()}),
            }
        );
    }
    client.close().await?;
    let status = tokio::time::timeout(Duration::from_secs(20), child.wait()).await??;
    println!("{}", json!({"closed":true,"success":status.success()}));
    if !status.success() {
        return Err("core did not stop cleanly".into());
    }
    Ok(())
}

use oip_opcua::open62541_poc::run_open62541_poc;
use std::error::Error;

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn Error>> {
    let port = std::net::TcpListener::bind(("127.0.0.1", 0))?
        .local_addr()?
        .port();
    let report = run_open62541_poc(port, 1_000).await?;
    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}

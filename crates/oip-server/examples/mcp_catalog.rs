fn main() {
    println!(
        "{}",
        serde_json::to_string_pretty(&oip_server::mcp::capability_mapping()).expect("catalog")
    );
}

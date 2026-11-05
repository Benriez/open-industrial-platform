//! Invalid CLI combinations fail before database/collector side effects.
#[test]
fn offline_management_cannot_run_inside_stdio_or_daemon_mode() {
    let database =
        std::env::temp_dir().join(format!("oip8-invalid-cli-{}.sqlite", std::process::id()));
    assert!(!database.exists());
    for mode in ["--mcp-stdio", "--daemon", "--demo"] {
        let output = std::process::Command::new(env!("CARGO_BIN_EXE_oip-server"))
            .args([
                mode,
                "--database",
                database.to_str().unwrap(),
                "--provision",
                "not-an-existing-plan.json",
            ])
            .output()
            .unwrap();
        assert!(!output.status.success());
        assert!(output.stdout.is_empty());
        assert!(!database.exists());
    }
}

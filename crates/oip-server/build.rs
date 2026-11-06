use std::process::Command;
fn git(args: &[&str]) -> Option<String> {
    Command::new("git")
        .args(args)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
}
fn main() {
    // Worktree .git is only a pointer; follow the actual per-worktree HEAD/index and shared ref.
    for name in ["HEAD", "index"] {
        if let Some(p) = git(&["rev-parse", "--git-path", name]) {
            println!("cargo:rerun-if-changed={p}");
        }
    }
    if let Some(branch) = git(&["symbolic-ref", "HEAD"]) {
        if let Some(p) = git(&["rev-parse", "--git-path", &branch]) {
            println!("cargo:rerun-if-changed={p}");
        }
    }
    println!("cargo:rerun-if-changed=../oip-core/src");
    println!("cargo:rerun-if-changed=../oip-storage/src");
    println!("cargo:rerun-if-changed=src");
    let revision = git(&["describe", "--always", "--abbrev=40", "--dirty"])
        .unwrap_or_else(|| "unavailable".into());
    println!("cargo:rustc-env=OIP_BUILD_REVISION={revision}");
}

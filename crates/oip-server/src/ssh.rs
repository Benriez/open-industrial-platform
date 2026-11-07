//! Read-only system-OpenSSH adapter. No shell/client file path is accepted from API input.
use oip_core::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWriteExt},
    process::Command,
};
use tokio_util::sync::CancellationToken;
#[derive(Clone, Debug, Deserialize, Serialize, Default)]
#[serde(default, deny_unknown_fields)]
pub struct SshSettings {
    pub profiles: Vec<SshIdentityProfile>,
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SshIdentityProfile {
    pub id: String,
    pub label: String,
    pub principals: Vec<PrincipalId>,
    pub allowed_hosts: Vec<String>,
    pub allowed_ports: Vec<u16>,
    pub identity_file: Option<PathBuf>,
    pub agent_socket: Option<PathBuf>,
    pub known_hosts_file: Option<PathBuf>,
    #[serde(default)]
    pub aliases: BTreeMap<String, SshAlias>,
}
impl std::fmt::Debug for SshIdentityProfile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SshIdentityProfile")
            .field("id", &self.id)
            .field("server_identity", &"redacted")
            .finish()
    }
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SshAlias {
    pub host: String,
    pub port: u16,
    pub user: String,
}
#[derive(Clone, Debug)]
pub struct PublicHostKey {
    pub key: String,
    pub fingerprint: String,
}
pub fn fault(code: &str) -> ConnectionFault {
    ConnectionFault {
        code: code.into(),
        message: match code {
            "SSH_PRIVILEGED_ACCOUNT" => "An unprivileged remote SSH account is required; root or unverifiable UID is blocked",
            "SSH_AUTHENTICATION_FAILED" => {
                "SSH authentication failed; check the authorized local identity and remote user"
            }
            "SSH_HOST_KEY_CHANGED" => {
                "SSH host key differs from the trusted binding; connection blocked"
            }
            "SSH_ENDPOINT_UNREACHABLE" => {
                "The explicitly configured SSH endpoint could not be reached"
            }
            "SSH_TIMEOUT" => "SSH request exceeded its bounded deadline",
            "SSH_OUTPUT_LIMIT" => "SSH response exceeded the allowed output size",
            "SSH_PROFILE_UNAVAILABLE" => {
                "No authorized local SSH identity profile permits this endpoint"
            }
            "SSH_CANCELLED" => "SSH request was cancelled",
            "SSH_UNSUPPORTED_OS" => {
                "Only verified Linux and macOS read-only collection is supported"
            }
            _ => "SSH read-only verification failed; no successful connection is asserted",
        }
        .into(),
    }
}
fn operator_uid() -> std::io::Result<u32> {
    // Metadata validation is also called outside an async reactor. The process
    // never changes UID; resolve the real OS identity once through a fixed tool.
    static UID: std::sync::OnceLock<Option<u32>> = std::sync::OnceLock::new();
    UID.get_or_init(|| {
        let out = std::process::Command::new("/usr/bin/id")
            .arg("-u")
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        std::str::from_utf8(&out.stdout).ok()?.trim().parse().ok()
    })
    .ok_or_else(|| std::io::Error::other("Cannot establish local operator identity"))
}
fn safe_path(path: &Path) -> Result<(), ConnectionFault> {
    if !path.is_absolute() {
        return Err(fault("SSH_PROFILE_UNAVAILABLE"));
    }
    #[cfg(unix)]
    let uid = operator_uid().map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
    let mut current = PathBuf::new();
    for c in path.components() {
        if matches!(
            c,
            std::path::Component::ParentDir | std::path::Component::CurDir
        ) {
            return Err(fault("SSH_PROFILE_UNAVAILABLE"));
        }
        current.push(c);
        let m =
            std::fs::symlink_metadata(&current).map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
        if m.is_symlink() {
            return Err(fault("SSH_PROFILE_UNAVAILABLE"));
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            if m.is_dir()
                && ((m.uid() != uid && m.uid() != 0)
                    || (m.mode() & 0o022 != 0 && !(m.uid() == 0 && m.mode() & 0o1000 != 0)))
            {
                return Err(fault("SSH_PROFILE_UNAVAILABLE"));
            }
        }
    }
    Ok(())
}
impl SshSettings {
    pub fn validate(&self, h: Option<&HierarchyRegistry>) -> Result<(), ConnectionFault> {
        if self.profiles.len() > 32 {
            return Err(fault("SSH_PROFILE_UNAVAILABLE"));
        }
        let mut ids = std::collections::BTreeSet::new();
        for p in &self.profiles {
            if p.id.is_empty()
                || p.id.len() > 64
                || !p
                    .id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
                || !ids.insert(&p.id)
                || p.label.is_empty()
                || p.label.len() > 128
                || p.principals.is_empty()
                || p.principals.len() > 64
                || p.allowed_hosts.is_empty()
                || p.allowed_hosts.len() > 64
                || p.allowed_ports.is_empty()
                || p.allowed_ports.len() > 8
                || p.allowed_ports.contains(&0)
                || (p.identity_file.is_none() && p.agent_socket.is_none())
                || p.aliases.len() > 32
            {
                return Err(fault("SSH_PROFILE_UNAVAILABLE"));
            }
            if p.principals.iter().any(|id| {
                h.is_none_or(|h| !h.plan.principals.iter().any(|x| &x.id == id && x.enabled))
            }) {
                return Err(fault("SSH_PROFILE_UNAVAILABLE"));
            }
            for host in &p.allowed_hosts {
                SshEndpoint {
                    host: host.clone(),
                    port: 22,
                    user: "operator".into(),
                    identity_profile: p.id.clone(),
                    alias: None,
                }
                .validate()
                .map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
            }
            Self::validate_profile_paths(p)?;
            for a in p.aliases.values() {
                if !p.allowed_hosts.contains(&a.host) || !p.allowed_ports.contains(&a.port) {
                    return Err(fault("SSH_PROFILE_UNAVAILABLE"));
                }
            }
        }
        Ok(())
    }
    fn validate_profile_paths(p: &SshIdentityProfile) -> Result<(), ConnectionFault> {
        for path in [&p.identity_file, &p.agent_socket, &p.known_hosts_file]
            .into_iter()
            .flatten()
        {
            safe_path(path)?;
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::{FileTypeExt, MetadataExt};
            let uid = operator_uid().map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
            if let Some(path) = &p.identity_file {
                let m = std::fs::metadata(path).map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
                if !m.is_file() || m.uid() != uid || m.mode() & 0o077 != 0 || m.nlink() != 1 {
                    return Err(fault("SSH_PROFILE_UNAVAILABLE"));
                }
            }
            if let Some(path) = &p.agent_socket {
                let m = std::fs::metadata(path).map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
                if !m.file_type().is_socket() || m.uid() != uid || m.mode() & 0o077 != 0 {
                    return Err(fault("SSH_PROFILE_UNAVAILABLE"));
                }
            }
            if let Some(path) = &p.known_hosts_file {
                let m = std::fs::metadata(path).map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
                if !m.is_file()
                    || (m.uid() != uid && m.uid() != 0)
                    || m.mode() & 0o022 != 0
                    || m.nlink() != 1
                {
                    return Err(fault("SSH_PROFILE_UNAVAILABLE"));
                }
            }
        }
        #[cfg(not(unix))]
        return Err(fault("SSH_PROFILE_UNAVAILABLE"));
        Ok(())
    }
    pub fn resolve(
        &self,
        p: &PrincipalId,
        e: &SshEndpoint,
    ) -> Result<(SshIdentityProfile, SshEndpoint), ConnectionFault> {
        let profile = self
            .profiles
            .iter()
            .find(|v| v.id == e.identity_profile && v.principals.contains(p))
            .ok_or_else(|| fault("SSH_PROFILE_UNAVAILABLE"))?;
        // Recheck the actual server-side paths on each use, not only at startup.
        // No client can supply a new path through the request.
        Self::validate_profile_paths(profile)?;
        let mut endpoint = e.clone();
        if let Some(alias) = &e.alias {
            let a = profile
                .aliases
                .get(alias)
                .ok_or_else(|| fault("SSH_PROFILE_UNAVAILABLE"))?;
            endpoint.host = a.host.clone();
            endpoint.port = a.port;
            endpoint.user = a.user.clone();
        }
        endpoint.alias = None;
        endpoint
            .validate()
            .map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
        if !profile.allowed_hosts.contains(&endpoint.host)
            || !profile.allowed_ports.contains(&endpoint.port)
        {
            return Err(fault("SSH_PROFILE_UNAVAILABLE"));
        }
        Ok((profile.clone(), endpoint))
    }
    pub fn visible(&self, p: &PrincipalId) -> Vec<SshIdentityProfileInfo> {
        self.profiles
            .iter()
            .filter(|v| v.principals.contains(p))
            .map(|v| SshIdentityProfileInfo {
                id: v.id.clone(),
                label: v.label.clone(),
                authentication: if v.identity_file.is_some() {
                    "local_key_reference"
                } else {
                    "local_agent_reference"
                }
                .into(),
                aliases: v.aliases.keys().cloned().collect(),
            })
            .collect()
    }
}
async fn bounded(mut input: impl AsyncRead + Unpin, max: usize) -> std::io::Result<Vec<u8>> {
    let mut b = Vec::new();
    (&mut input)
        .take(max as u64 + 1)
        .read_to_end(&mut b)
        .await?;
    if b.len() > max {
        return Err(std::io::Error::other("output limit"));
    }
    Ok(b)
}
async fn run(
    mut command: Command,
    input: Option<&[u8]>,
    cancel: &CancellationToken,
    limit: usize,
) -> Result<Vec<u8>, ConnectionFault> {
    command
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command
        .spawn()
        .map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
    let stdout = child.stdout.take().ok_or_else(|| fault("SSH_FAILED"))?;
    let stderr = child.stderr.take().ok_or_else(|| fault("SSH_FAILED"))?;
    if let Some(bytes) = input {
        if let Some(mut stdin) = child.stdin.take() {
            if stdin.write_all(bytes).await.is_err() {
                let _ = child.kill().await;
                let _ = child.wait().await;
                return Err(fault("SSH_FAILED"));
            }
            let _ = stdin.shutdown().await;
        }
    }
    let result = tokio::select! {biased;_=cancel.cancelled()=>Err(fault("SSH_CANCELLED")),result=tokio::time::timeout(Duration::from_secs(10),async{tokio::try_join!(bounded(stdout,limit),bounded(stderr,16384),child.wait())})=>match result{Err(_)=>Err(fault("SSH_TIMEOUT")),Ok(Err(_))=>Err(fault("SSH_OUTPUT_LIMIT")),Ok(Ok((out,err,status)))=>if status.success(){Ok(out)}else{let err=String::from_utf8_lossy(&err);Err(fault(if err.contains("OIP_UNSUPPORTED_OS"){"SSH_UNSUPPORTED_OS"}else if err.contains("OIP_PRIVILEGED_ACCOUNT"){"SSH_PRIVILEGED_ACCOUNT"}else if err.contains("REMOTE HOST IDENTIFICATION HAS CHANGED")||err.contains("Host key verification failed"){"SSH_HOST_KEY_CHANGED"}else if err.contains("Permission denied")||err.contains("Authentication failed"){"SSH_AUTHENTICATION_FAILED"}else if err.contains("Connection refused")||err.contains("No route to host")||err.contains("Could not resolve hostname"){"SSH_ENDPOINT_UNREACHABLE"}else if err.contains("timed out"){"SSH_TIMEOUT"}else{"SSH_FAILED"}))}}};
    if result.is_err() {
        let _ = child.kill().await;
        let _ = child.wait().await;
    }
    result
}
pub fn private_workdir(path: &Path) -> Result<(), ConnectionFault> {
    if !path.exists() {
        std::fs::create_dir(path).map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
                .map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
        }
    }
    safe_path(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let m = std::fs::metadata(path).map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?;
        if !m.is_dir()
            || m.uid() != operator_uid().map_err(|_| fault("SSH_PROFILE_UNAVAILABLE"))?
            || m.mode() & 0o077 != 0
        {
            return Err(fault("SSH_PROFILE_UNAVAILABLE"));
        }
    }
    Ok(())
}
struct PinFile(PathBuf);
impl Drop for PinFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}
fn pin_file(dir: &Path, key: &str) -> Result<PinFile, ConnectionFault> {
    use std::io::Write;
    let path = dir.join(crate::browser_session::random_token().map_err(|_| fault("SSH_FAILED"))?);
    let mut opt = std::fs::OpenOptions::new();
    opt.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opt.mode(0o600);
    }
    let mut f = opt.open(&path).map_err(|_| fault("SSH_FAILED"))?;
    f.write_all(format!("oip-target {key}\n").as_bytes())
        .map_err(|_| fault("SSH_FAILED"))?;
    Ok(PinFile(path))
}
pub async fn scan(
    endpoint: &SshEndpoint,
    dir: &Path,
    cancel: &CancellationToken,
) -> Result<Vec<PublicHostKey>, ConnectionFault> {
    endpoint
        .validate()
        .map_err(|_| fault("SSH_ENDPOINT_UNREACHABLE"))?;
    let mut cmd = Command::new("/usr/bin/ssh-keyscan");
    cmd.args([
        "-T",
        "4",
        "-p",
        &endpoint.port.to_string(),
        "-t",
        "ed25519,ecdsa,rsa",
        &endpoint.host,
    ]);
    let out = run(cmd, None, cancel, 16384).await.map_err(|e| {
        if e.code == "SSH_FAILED" {
            fault("SSH_ENDPOINT_UNREACHABLE")
        } else {
            e
        }
    })?;
    let text = String::from_utf8(out).map_err(|_| fault("SSH_FAILED"))?;
    let mut keys = Vec::new();
    for line in text.lines().filter(|l| !l.starts_with('#')) {
        let parts = line.split_whitespace().collect::<Vec<_>>();
        if parts.len() != 3
            || !matches!(
                parts[1],
                "ssh-ed25519"
                    | "ssh-rsa"
                    | "ecdsa-sha2-nistp256"
                    | "ecdsa-sha2-nistp384"
                    | "ecdsa-sha2-nistp521"
            )
        {
            continue;
        }
        if keys.len() >= 8 {
            return Err(fault("SSH_OUTPUT_LIMIT"));
        }
        let key = format!("{} {}", parts[1], parts[2]);
        let pin = pin_file(dir, &key)?;
        let mut cmd = Command::new("/usr/bin/ssh-keygen");
        cmd.args(["-lf"]).arg(&pin.0).args(["-E", "sha256"]);
        let out = run(cmd, None, cancel, 2048).await?;
        let text = String::from_utf8(out).map_err(|_| fault("SSH_FAILED"))?;
        let fingerprint = text
            .split_whitespace()
            .nth(1)
            .filter(|s| s.starts_with("SHA256:"))
            .ok_or_else(|| fault("SSH_FAILED"))?
            .to_string();
        keys.push(PublicHostKey { key, fingerprint });
    }
    if keys.is_empty() {
        return Err(fault("SSH_ENDPOINT_UNREACHABLE"));
    }
    keys.sort_by_key(|k| {
        if k.key.starts_with("ssh-ed25519 ") {
            0
        } else if k.key.starts_with("ecdsa-") {
            1
        } else {
            2
        }
    });
    Ok(keys)
}
pub async fn trusted_key(
    profile: &SshIdentityProfile,
    endpoint: &SshEndpoint,
    keys: &[PublicHostKey],
    existing: Option<&DeviceConnectionRecord>,
    cancel: &CancellationToken,
) -> Result<(PublicHostKey, bool), ConnectionFault> {
    if let Some(c) = existing {
        return keys
            .iter()
            .find(|k| k.key == c.host_key)
            .cloned()
            .map(|k| (k, true))
            .ok_or_else(|| fault("SSH_HOST_KEY_CHANGED"));
    }
    if let Some(path) = &profile.known_hosts_file {
        let host = if endpoint.port == 22 {
            endpoint.host.clone()
        } else {
            format!("[{}]:{}", endpoint.host, endpoint.port)
        };
        let mut cmd = Command::new("/usr/bin/ssh-keygen");
        cmd.args(["-F", &host, "-f"]).arg(path);
        // ssh-keygen returns1 when no entry exists. Do not treat that as trusted.
        match run(cmd, None, cancel, 32768).await {
            Ok(out) => {
                let text = String::from_utf8(out).map_err(|_| fault("SSH_FAILED"))?;
                if text.lines().any(|l| l.starts_with("@revoked")) {
                    return Err(fault("SSH_HOST_KEY_CHANGED"));
                }
                let known = text
                    .lines()
                    .filter(|l| !l.starts_with('#'))
                    .filter_map(|l| {
                        let p = l.split_whitespace().collect::<Vec<_>>();
                        if p.len() >= 3 && !p[0].starts_with('@') {
                            Some(format!("{} {}", p[1], p[2]))
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
                if let Some(k) = keys.iter().find(|k| known.contains(&k.key)) {
                    return Ok((k.clone(), true));
                }
                if !known.is_empty() {
                    return Err(fault("SSH_HOST_KEY_CHANGED"));
                }
            }
            Err(e) if e.code == "SSH_FAILED" => {}
            Err(e) => return Err(e),
        }
    }
    Ok((keys[0].clone(), false))
}
async fn execute(
    endpoint: &SshEndpoint,
    profile: &SshIdentityProfile,
    key: &str,
    dir: &Path,
    script: &[u8],
    cancel: &CancellationToken,
) -> Result<Vec<u8>, ConnectionFault> {
    let pin = pin_file(dir, key)?;
    let mut cmd = Command::new("/usr/bin/ssh");
    cmd.env_clear()
        .env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        .env("LC_ALL", "C")
        .args([
            "-F",
            "/dev/null",
            "-T",
            "-p",
            &endpoint.port.to_string(),
            "-l",
            &endpoint.user,
        ]);
    for option in [
        "BatchMode=yes",
        "RequiredRSASize=2048",
        "PasswordAuthentication=no",
        "KbdInteractiveAuthentication=no",
        "PreferredAuthentications=publickey",
        "NumberOfPasswordPrompts=0",
        "StrictHostKeyChecking=yes",
        "HostKeyAlias=oip-target",
        "GlobalKnownHostsFile=/dev/null",
        "UpdateHostKeys=no",
        "VerifyHostKeyDNS=no",
        "CheckHostIP=no",
        "ProxyCommand=none",
        "ProxyJump=none",
        "PermitLocalCommand=no",
        "ForwardAgent=no",
        "ClearAllForwardings=yes",
        "ConnectionAttempts=1",
        "ConnectTimeout=5",
        "ServerAliveInterval=3",
        "ServerAliveCountMax=1",
        "LogLevel=ERROR",
        "AddKeysToAgent=no",
    ] {
        cmd.arg("-o").arg(option);
    }
    cmd.arg("-o")
        .arg(format!("UserKnownHostsFile={}", pin.0.display()));
    if let Some(path) = &profile.identity_file {
        cmd.args(["-o", "IdentitiesOnly=yes", "-i"]).arg(path);
    } else {
        cmd.args(["-o", "IdentitiesOnly=no"]);
    }
    if let Some(path) = &profile.agent_socket {
        cmd.env("SSH_AUTH_SOCK", path)
            .arg("-o")
            .arg(format!("IdentityAgent={}", path.display()));
    } else {
        cmd.args(["-o", "IdentityAgent=none"]);
    }
    cmd.arg(&endpoint.host).args(["sh", "-s"]);
    // Fixed privilege check runs for authentication and every polling query.
    // A non-root-looking username alone does not prove an unprivileged account.
    let mut guarded = PRIVILEGE_CHECK.as_bytes().to_vec();
    guarded.extend_from_slice(script);
    run(cmd, Some(&guarded), cancel, 131072).await
}
const PRIVILEGE_CHECK: &str = r#"PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
LC_ALL=C; export LC_ALL
_oip_uid=$(/usr/bin/id -u) || { printf 'OIP_PRIVILEGED_ACCOUNT\n' >&2; exit 77; }
case "$_oip_uid" in ''|*[!0-9]*) printf 'OIP_PRIVILEGED_ACCOUNT\n' >&2; exit 77;; esac
if ! [ "$_oip_uid" -gt 0 ]; then printf 'OIP_PRIVILEGED_ACCOUNT\n' >&2; exit 77; fi
"#;
pub async fn authenticate(
    endpoint: &SshEndpoint,
    profile: &SshIdentityProfile,
    key: &str,
    dir: &Path,
    cancel: &CancellationToken,
) -> Result<(), ConnectionFault> {
    let value = execute(
        endpoint,
        profile,
        key,
        dir,
        b"printf 'OIP_AUTHENTICATED\\n'\n",
        cancel,
    )
    .await?;
    if value != b"OIP_AUTHENTICATED\n" {
        return Err(fault("SSH_FAILED"));
    }
    Ok(())
}
const QUERY: &str = r#"PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
LC_ALL=C; export LC_ALL
printf '\n__OIP_OS__\n'; uname -s
printf '\n__OIP_HOSTNAME__\n'; hostname
printf '\n__OIP_ARCH__\n'; uname -m
case "$(uname -s)" in
 Linux)
 printf '\n__OIP_CPU__\n'; sed -n 's/^model name[[:space:]]*: //p;s/^Hardware[[:space:]]*: //p' /proc/cpuinfo | head -n 1
 printf '\n__OIP_MODEL__\n'; if [ -r /proc/device-tree/model ]; then tr '\000' ' ' </proc/device-tree/model; elif [ -r /sys/class/dmi/id/product_name ]; then cat /sys/class/dmi/id/product_name; fi
 printf '\n__OIP_MEMORY__\n'; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo
 printf '\n__OIP_UPTIME__\n'; cat /proc/uptime
 printf '\n__OIP_HOSTID__\n'; if [ -r /etc/machine-id ]; then cat /etc/machine-id; fi
 printf '\n__OIP_NETWORK__\n'; if command -v ip >/dev/null 2>&1; then ip -j address show; elif command -v ifconfig >/dev/null 2>&1; then ifconfig -a; fi
 ;;
 Darwin)
 printf '\n__OIP_CPU__\n'; sysctl -n machdep.cpu.brand_string
 printf '\n__OIP_MODEL__\n'; sysctl -n hw.model
 printf '\n__OIP_MEMORY__\n'; sysctl -n hw.memsize; vm_stat
 printf '\n__OIP_UPTIME__\n'; sysctl -n kern.boottime; date +%s
 printf '\n__OIP_NETWORK__\n'; ifconfig -a
 ;;
 *) printf 'OIP_UNSUPPORTED_OS\n' >&2; exit 42 ;;
esac
printf '\n__OIP_DISKS__\n'; df -Pkl
printf '\n__OIP_END__\n'
"#;
pub async fn collect(
    endpoint: &SshEndpoint,
    profile: &SshIdentityProfile,
    key: &str,
    dir: &Path,
    cancel: &CancellationToken,
) -> Result<HostInformation, ConnectionFault> {
    let bytes = execute(endpoint, profile, key, dir, QUERY.as_bytes(), cancel).await?;
    parse(&bytes, crate::state::now_ms())
}
fn number(text: &str) -> Option<u64> {
    text.split_whitespace()
        .next()?
        .trim_end_matches('.')
        .parse()
        .ok()
}
pub fn parse(bytes: &[u8], at: i64) -> Result<HostInformation, ConnectionFault> {
    let text = std::str::from_utf8(bytes).map_err(|_| fault("SSH_FAILED"))?;
    let mut fields: BTreeMap<&str, String> = BTreeMap::new();
    let mut current = None;
    for line in text.lines() {
        if line.starts_with("__OIP_") && line.ends_with("__") {
            if fields.contains_key(line) {
                return Err(fault("SSH_FAILED"));
            }
            fields.insert(line, String::new());
            current = Some(line);
        } else if let Some(key) = current {
            let value = fields.get_mut(key).ok_or_else(|| fault("SSH_FAILED"))?;
            value.push_str(line);
            value.push('\n');
        }
    }
    let field = |key: &str| fields.get(key).map(|s| s.trim()).unwrap_or("");
    let os = field("__OIP_OS__");
    if !matches!(os, "Linux" | "Darwin") {
        return Err(fault("SSH_UNSUPPORTED_OS"));
    }
    let host = field("__OIP_HOSTNAME__");
    let arch = field("__OIP_ARCH__");
    if host.is_empty()
        || host.len() > 253
        || arch.is_empty()
        || arch.len() > 128
        || !fields.contains_key("__OIP_END__")
    {
        return Err(fault("SSH_FAILED"));
    }
    let optional = |key: &str| {
        let x = field(key);
        if x.is_empty() {
            None
        } else {
            Some(x.chars().take(512).collect::<String>())
        }
    };
    let mut unavailable = vec!["gpu".into(), "temperature".into(), "cpu_utilization".into()];
    let memory = field("__OIP_MEMORY__");
    let (memory_total_bytes, memory_used_bytes) = if os == "Linux" {
        let values = memory
            .lines()
            .filter_map(|l| {
                let (k, v) = l.split_once(':')?;
                Some((k, number(v)?.checked_mul(1024)?))
            })
            .collect::<BTreeMap<_, _>>();
        let total = values.get("MemTotal").copied();
        let used = total
            .zip(values.get("MemAvailable").copied())
            .and_then(|(t, a)| t.checked_sub(a));
        (total, used)
    } else {
        let total = memory.lines().next().and_then(number);
        let page = memory
            .lines()
            .find(|l| l.contains("page size of"))
            .and_then(|l| l.split("page size of ").nth(1))
            .and_then(number);
        let pages = memory
            .lines()
            .filter_map(|l| {
                let (k, v) = l.split_once(':')?;
                Some((k, number(v)?))
            })
            .collect::<BTreeMap<_, _>>();
        let used = page.and_then(|size| {
            pages
                .get("Pages active")
                .zip(pages.get("Pages wired down"))
                .map(|(a, w)| {
                    a.saturating_add(*w)
                        .saturating_add(*pages.get("Pages occupied by compressor").unwrap_or(&0))
                })
                .and_then(|p| p.checked_mul(size))
        });
        (total, used.filter(|u| total.is_some_and(|t| *u <= t)))
    };
    let uptime = field("__OIP_UPTIME__");
    let uptime_seconds = if os == "Linux" {
        uptime
            .split_whitespace()
            .next()
            .and_then(|s| s.parse::<f64>().ok())
    } else {
        uptime
            .lines()
            .next()
            .and_then(|l| l.split("sec = ").nth(1))
            .and_then(|s| s.split(',').next())
            .and_then(|s| s.trim().parse::<i64>().ok())
            .zip(uptime.lines().last().and_then(|s| s.parse::<i64>().ok()))
            .and_then(|(boot, now)| now.checked_sub(boot).filter(|v| *v >= 0).map(|v| v as f64))
    }
    .filter(|v| v.is_finite() && *v >= 0.);
    let mut disks = Vec::new();
    for line in field("__OIP_DISKS__").lines().skip(1).take(33) {
        let p = line.split_whitespace().collect::<Vec<_>>();
        if p.len() >= 6 {
            if let (Some(t), Some(u), Some(a)) = (
                number(p[1]).and_then(|v| v.checked_mul(1024)),
                number(p[2]).and_then(|v| v.checked_mul(1024)),
                number(p[3]).and_then(|v| v.checked_mul(1024)),
            ) {
                if u <= t {
                    disks.push(DiskInformation {
                        filesystem: redact_filesystem(p[0]),
                        mount: p[5..].join(" ").chars().take(512).collect(),
                        total_bytes: t,
                        used_bytes: u,
                        available_bytes: a,
                    });
                }
            }
        }
    }
    if disks.len() > 32 {
        return Err(fault("SSH_OUTPUT_LIMIT"));
    }
    let network = field("__OIP_NETWORK__");
    let mut interfaces = Vec::new();
    if let Ok(serde_json::Value::Array(rows)) = serde_json::from_str(network) {
        for row in rows.into_iter().take(33) {
            if let Some(name) = row.get("ifname").and_then(|v| v.as_str()) {
                let addresses = row
                    .get("addr_info")
                    .and_then(|v| v.as_array())
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.get("local")?.as_str())
                            .take(32)
                            .map(str::to_string)
                            .collect()
                    })
                    .unwrap_or_default();
                interfaces.push(NetworkInterfaceInformation {
                    name: name.chars().take(128).collect(),
                    addresses,
                });
            }
        }
    } else {
        for line in network.lines() {
            if !line.starts_with(char::is_whitespace) {
                if let Some((name, _)) = line.split_once(':') {
                    interfaces.push(NetworkInterfaceInformation {
                        name: name.chars().take(128).collect(),
                        addresses: vec![],
                    });
                }
            } else {
                let p = line.split_whitespace().collect::<Vec<_>>();
                if p.len() > 1 && matches!(p[0], "inet" | "inet6") {
                    if let Some(i) = interfaces.last_mut() {
                        if i.addresses.len() < 32 {
                            i.addresses.push(p[1].chars().take(128).collect());
                        }
                    }
                }
            }
        }
    }
    if interfaces.len() > 32 {
        return Err(fault("SSH_OUTPUT_LIMIT"));
    }
    for (name, missing) in [
        ("memory_total", memory_total_bytes.is_none()),
        ("memory_used", memory_used_bytes.is_none()),
        ("uptime", uptime_seconds.is_none()),
        ("network_interfaces", interfaces.is_empty()),
        ("disks", disks.is_empty()),
    ] {
        if missing {
            unavailable.push(name.into());
        }
    }
    Ok(HostInformation{hostname:host.into(),operating_system:os.into(),architecture:arch.into(),cpu_info:optional("__OIP_CPU__"),model:optional("__OIP_MODEL__"),stable_host_id_sha256:optional("__OIP_HOSTID__").map(|v|format!("{:x}",Sha256::digest(v.as_bytes()))),memory_total_bytes,memory_used_bytes,uptime_seconds,disks,interfaces,captured_at_ms:at,unavailable,provenance:"authenticated SSH host report; fixed read-only query; capture time is Core time, remote measurement clocks unknown; no hardware attestation or inferred sensors".into()})
}
pub fn definition(c: &DeviceConnectionRecord) -> SourceDefinition {
    let mut metrics = BTreeMap::new();
    for name in [
        "hostname",
        "os",
        "architecture",
        "cpu_info",
        "model",
        "disks",
        "interfaces",
    ] {
        metrics.insert(
            MetricId::new(format!("host.{name}")).expect("static metric"),
            ValueKind::Text,
        );
    }
    for name in ["memory_total_bytes", "memory_used_bytes"] {
        metrics.insert(
            MetricId::new(format!("host.{name}")).expect("static metric"),
            ValueKind::UnsignedInteger,
        );
    }
    metrics.insert(
        MetricId::new("host.uptime_seconds").expect("static metric"),
        ValueKind::Float,
    );
    SourceDefinition {
        id: c.source_id.clone(),
        name: format!("SSH host {}", c.device_id),
        entity_id: EntityId::new(c.device_id.as_str()).expect("validated device identity"),
        binding: format!(
            "ssh://{}@{}:{}",
            c.endpoint.user, c.endpoint.host, c.endpoint.port
        ),
        simulation_origin_id: String::new(),
        origin_class: OriginClass::External,
        metrics,
        required_metrics: [MetricId::new("host.os").expect("static metric")]
            .into_iter()
            .collect(),
    }
}
fn redact_filesystem(value: &str) -> String {
    let safe = if value.starts_with("//") || value.contains("://") {
        if let Some((prefix, target)) = value.rsplit_once('@') {
            let scheme = prefix
                .split_once("://")
                .map_or_else(|| "//".to_owned(), |(s, _)| format!("{s}://"));
            format!("{scheme}[redacted-userinfo]@{target}")
        } else {
            value.to_owned()
        }
    } else {
        value.to_owned()
    };
    safe.chars().take(512).collect()
}
pub fn observations(c: &DeviceConnectionRecord, h: &HostInformation) -> Vec<ObservationEnvelope> {
    let mut values = Vec::new();
    for (name, value) in [
        ("hostname", Some(h.hostname.clone())),
        ("os", Some(h.operating_system.clone())),
        ("architecture", Some(h.architecture.clone())),
        ("cpu_info", h.cpu_info.clone()),
        ("model", h.model.clone()),
        (
            "disks",
            if h.disks.is_empty() {
                None
            } else {
                serde_json::to_string(&h.disks).ok()
            },
        ),
        (
            "interfaces",
            if h.interfaces.is_empty() {
                None
            } else {
                serde_json::to_string(&h.interfaces).ok()
            },
        ),
    ] {
        if let Some(value) = value {
            values.push((name, MetricValue::Text(value), Unit::None));
        }
    }
    for (name, value) in [
        ("memory_total_bytes", h.memory_total_bytes),
        ("memory_used_bytes", h.memory_used_bytes),
    ] {
        if let Some(value) = value {
            values.push((
                name,
                MetricValue::UnsignedInteger(value),
                Unit::Custom("bytes".into()),
            ));
        }
    }
    if let Some(v) = h.uptime_seconds {
        values.push((
            "uptime_seconds",
            MetricValue::Float(v),
            Unit::Custom("seconds".into()),
        ));
    }
    values
        .into_iter()
        .map(|(name, value, unit)| ObservationEnvelope {
            entity_id: EntityId::new(c.device_id.as_str()).expect("id"),
            data_source_id: c.source_id.clone(),
            metric_id: MetricId::new(format!("host.{name}")).expect("static metric"),
            value: Some(value),
            unit,
            quality: DataQuality::Good,
            freshness: Freshness::Fresh,
            timestamps: Timestamps {
                source: Timestamp::from_unix_millis(h.captured_at_ms),
                server: None,
                received: Some(Timestamp::from_unix_millis(h.captured_at_ms)),
            },
            status_code: None,
            collection_error: None,
            simulation_origin: None,
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    #[test]
    fn profile_paths_reject_shared_trust_files_agent_sockets_and_symlinks() {
        use std::os::unix::{fs::PermissionsExt, net::UnixListener};
        let path = std::fs::canonicalize(std::env::temp_dir())
            .unwrap()
            .join(format!(
                "oip-ssh-{}",
                &crate::browser_session::random_token().unwrap()[..12]
            ));
        std::fs::create_dir(&path).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
        let key = path.join("unit-key-reference");
        let known = path.join("unit-trust-reference");
        std::fs::write(&key, b"metadata-only unit fixture; not a key").unwrap();
        std::fs::write(&known, b"public unit fixture").unwrap();
        std::fs::set_permissions(&key, std::fs::Permissions::from_mode(0o600)).unwrap();
        std::fs::set_permissions(&known, std::fs::Permissions::from_mode(0o644)).unwrap();
        let mut profile = SshIdentityProfile {
            id: "unit".into(),
            label: "Unit fixture".into(),
            principals: vec![],
            allowed_hosts: vec![],
            allowed_ports: vec![],
            identity_file: Some(key.clone()),
            agent_socket: None,
            known_hosts_file: Some(known.clone()),
            aliases: BTreeMap::new(),
        };
        assert!(SshSettings::validate_profile_paths(&profile).is_ok());
        std::fs::set_permissions(&known, std::fs::Permissions::from_mode(0o666)).unwrap();
        assert!(SshSettings::validate_profile_paths(&profile).is_err());
        std::fs::set_permissions(&known, std::fs::Permissions::from_mode(0o644)).unwrap();
        let socket = path.join("agent");
        let _listener = UnixListener::bind(&socket).unwrap();
        profile.agent_socket = Some(socket.clone());
        std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o666)).unwrap();
        assert!(SshSettings::validate_profile_paths(&profile).is_err());
        std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert!(SshSettings::validate_profile_paths(&profile).is_ok());
        let link = path.join("alias");
        std::os::unix::fs::symlink(&key, &link).unwrap();
        profile.identity_file = Some(link);
        assert!(SshSettings::validate_profile_paths(&profile).is_err());
        std::fs::remove_dir_all(path).unwrap();
    }
    #[test]
    fn privilege_guard_stops_before_queries_for_zero_or_unverifiable_uid() {
        for uid in ["0", "", "not-a-uid"] {
            // Unit fixture for a remote id result; no privileged account or
            // remote host is used. Exercise the actual fixed shell guard.
            let script = format!(
                "{}\nprintf 'QUERY_MUST_NOT_RUN\\n'\n",
                PRIVILEGE_CHECK.replace("/usr/bin/id -u", &format!("printf '%s' '{uid}'"))
            );
            let output = std::process::Command::new("/bin/sh")
                .arg("-c")
                .arg(script)
                .output()
                .unwrap();
            assert_eq!(output.status.code(), Some(77));
            assert!(output.stdout.is_empty());
            assert!(String::from_utf8_lossy(&output.stderr).contains("OIP_PRIVILEGED_ACCOUNT"));
        }
    }
    #[test]
    fn missing_metrics_are_not_zero_or_interpolated() {
        let input=b"__OIP_OS__\nLinux\n__OIP_HOSTNAME__\nfixture\n__OIP_ARCH__\naarch64\n__OIP_MEMORY__\nMemTotal: 1024 kB\n__OIP_END__\n";
        let h = parse(input, 100).unwrap();
        assert_eq!(h.memory_total_bytes, Some(1048576));
        assert!(h.memory_used_bytes.is_none());
        assert!(h.uptime_seconds.is_none());
        assert!(h.unavailable.contains(&"memory_used".into()));
    }
    #[test]
    fn filesystem_userinfo_is_never_returned_as_host_evidence() {
        let safe = redact_filesystem("//unit-user:unit-pass@unit-host/share");
        assert!(!safe.contains("unit-user") && !safe.contains("unit-pass"));
        assert!(safe.ends_with("@unit-host/share"));
        assert_eq!(redact_filesystem("/dev/disk0"), "/dev/disk0");
    }
    #[test]
    fn duplicate_markers_or_unsupported_os_fail() {
        assert!(parse(b"__OIP_OS__\nLinux\n__OIP_OS__\nDarwin\n", 1).is_err());
        assert!(parse(b"__OIP_OS__\nWindows\n__OIP_END__", 1).is_err());
    }
}

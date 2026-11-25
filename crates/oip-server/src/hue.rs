//! Read-only Philips Hue Bridge collector.
//!
//! The bridge serves HTTPS with a certificate that it issued itself and does
//! not present the root of its own chain, so its identity can only be verified
//! against a **pin** — exactly the way the SSH onboarding pins a host key. The
//! read is one TLS session in which `openssl` itself refuses a bridge that
//! presents another certificate.
//!
//! The public configuration of the bridge (`/api/config`) is readable without a
//! token. The lights, groups and scenes need an application token, and the
//! creation of a token is a **write on the device** that belongs to the
//! operator. Without a token the collector reports the verified identity of the
//! bridge and names the limit; it never simulates a light.
use crate::state::{now_ms, AppState};
use oip_core::*;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    process::Command,
};
use tokio_util::sync::CancellationToken;

/// One bounded answer of the bridge. A bridge with a hundred lights answers far
/// below this bound.
const MAX_HUE_ANSWER_BYTES: usize = 262_144;
/// Every light is reported as its own metric; the bound keeps the catalogue of
/// one bridge readable in the workstations.
const MAX_REPORTED_LIGHTS: usize = 32;

#[derive(Clone, Debug, Deserialize, Serialize, Default)]
#[serde(default, deny_unknown_fields)]
pub struct HueSettings {
    pub profiles: Vec<HueProfile>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HueProfile {
    #[serde(default)]
    pub control_enabled: bool,
    pub id: String,
    pub label: String,
    pub principals: Vec<PrincipalId>,
    pub device_id: DeviceId,
    pub host: String,
    #[serde(default = "https_port")]
    pub port: u16,
    #[serde(default = "default_poll_seconds")]
    pub poll_seconds: u64,
    pub pin_file: PathBuf,
    /// The application token of the operator, read from a private file. Without
    /// a token the honest limit applies: the verified identity of the bridge.
    #[serde(default)]
    pub token_file: Option<PathBuf>,
}

fn https_port() -> u16 {
    443
}
fn default_poll_seconds() -> u64 {
    30
}

impl std::fmt::Debug for HueProfile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HueProfile")
            .field("id", &self.id)
            .field("host", &self.host)
            .field("token", &"redacted")
            .finish()
    }
}

pub fn source_id(profile: &HueProfile) -> DataSourceId {
    DataSourceId::new(format!("hue-{}", profile.id)).expect("validated profile identity")
}

pub fn fault(code: &str) -> ConnectionFault {
    ConnectionFault {
        code: code.into(),
        message: match code {
            "HUE_PROFILE_UNAVAILABLE" => "A Hue profile needs a bounded identity, an authorized principal, a registered device and a pinned certificate",
            "HUE_DEVICE_UNREGISTERED" => "The Hue bridge is not a registered device of the authorized inventory",
            "HUE_PIN_MISSING" => "The pinned certificate of the bridge is not readable; its identity cannot be verified",
            "HUE_TOKEN_FILE_UNREADABLE" => "The configured token file of the bridge cannot be read",
            "HUE_TLS_TOOL_UNAVAILABLE" => "Hue collection requires OpenSSL with pinned partial-chain verification",
            "HUE_ENDPOINT_UNREACHABLE" => "The configured Hue bridge could not be reached over its verified TLS endpoint",
            "HUE_IDENTITY_CHANGED" => "The bridge presents a certificate that is not the pinned one; the operator must confirm the identity of the bridge again",
            "HUE_TIMEOUT" => "The Hue bridge exceeded its bounded deadline",
            "HUE_ANSWER_LIMIT" => "The answer of the Hue bridge exceeded the allowed size",
            "HUE_ANSWER_INVALID" => "The bridge answered without a usable configuration; no identity is asserted",
            "HUE_TOKEN_REQUIRED" => "The lights of the bridge need an application token of the operator; only the verified identity of the bridge is readable",
            "HUE_CANCELLED" => "The Hue collection was cancelled",
            _ => "Hue read-only verification failed; no measurement is asserted",
        }
        .into(),
    }
}

impl HueSettings {
    pub fn validate(&self, hierarchy: Option<&HierarchyRegistry>) -> Result<(), ConnectionFault> {
        if self.profiles.is_empty() || self.profiles.len() > 8 {
            return Err(fault("HUE_PROFILE_UNAVAILABLE"));
        }
        let mut ids = std::collections::BTreeSet::new();
        for profile in &self.profiles {
            if profile.id.is_empty()
                || profile.id.len() > 64
                || !profile
                    .id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
                || !ids.insert(&profile.id)
                || profile.label.is_empty()
                || profile.label.len() > 128
                || profile.principals.is_empty()
                || profile.principals.len() > 64
                || profile.host.parse::<std::net::IpAddr>().is_err()
                || profile.port != 443
                || oip_core::validate_poll_seconds(profile.poll_seconds).is_err()
                || profile.pin_file.as_os_str().is_empty()
                || !profile.pin_file.is_absolute()
                || profile
                    .token_file
                    .as_ref()
                    .is_some_and(|path| path.as_os_str().is_empty() || !path.is_absolute())
            {
                return Err(fault("HUE_PROFILE_UNAVAILABLE"));
            }
            // The bounds of a profile are checked without a hierarchy; the
            // authorization of its principals only when the hierarchy is known.
            if let Some(hierarchy) = hierarchy {
                if profile.principals.iter().any(|id| {
                    !hierarchy
                        .plan
                        .principals
                        .iter()
                        .any(|principal| &principal.id == id && principal.enabled)
                }) {
                    return Err(fault("HUE_PROFILE_UNAVAILABLE"));
                }
            }
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct BridgeIdentity {
    pub name: String,
    pub bridge_id: String,
    pub model_id: String,
    pub software_version: String,
    pub api_version: String,
    pub mac: String,
    pub datastore_version: String,
}

#[derive(Clone, Debug, Default)]
pub struct BridgeReport {
    pub captured_at_ms: i64,
    pub identity: BridgeIdentity,
    /// `None` when the bridge refuses the lights: the limit is named, never
    /// replaced by a simulated value.
    pub lights: Option<Vec<HueLight>>,
}

struct HttpAnswer {
    status: Option<u16>,
    body: String,
}

/// The answer of the bridge, with the chunked encoding unwound.
fn split_answer(raw: &[u8]) -> Result<HttpAnswer, ConnectionFault> {
    let invalid = || fault("HUE_ANSWER_INVALID");
    let end = raw
        .windows(4)
        .position(|bytes| bytes == b"\r\n\r\n")
        .ok_or_else(invalid)?;
    let head = std::str::from_utf8(&raw[..end]).map_err(|_| invalid())?;
    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse::<u16>().ok())
        .ok_or_else(invalid)?;
    let mut body = &raw[end + 4..];
    let mut decoded = Vec::new();
    if head.lines().any(|line| {
        line.split_once(':').is_some_and(|(k, v)| {
            k.eq_ignore_ascii_case("transfer-encoding") && v.trim().eq_ignore_ascii_case("chunked")
        })
    }) {
        loop {
            let end = body
                .windows(2)
                .position(|p| p == b"\r\n")
                .ok_or_else(invalid)?;
            let line = std::str::from_utf8(&body[..end]).map_err(|_| invalid())?;
            let size = usize::from_str_radix(line.split(';').next().unwrap_or("").trim(), 16)
                .map_err(|_| invalid())?;
            body = &body[end + 2..];
            if size == 0 {
                break;
            }
            let chunk = body.get(..size).ok_or_else(invalid)?;
            body = body[size..].strip_prefix(b"\r\n").ok_or_else(invalid)?;
            decoded.extend_from_slice(chunk);
        }
        body = &decoded;
    }
    Ok(HttpAnswer {
        status: Some(status),
        body: std::str::from_utf8(body).map_err(|_| invalid())?.to_owned(),
    })
}

fn text(value: &serde_json::Value, key: &str) -> String {
    value
        .get(key)
        .and_then(|value| match value {
            serde_json::Value::String(text) => Some(text.clone()),
            serde_json::Value::Number(number) => Some(number.to_string()),
            _ => None,
        })
        .unwrap_or_default()
}

fn number(value: &serde_json::Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|value| match value {
        serde_json::Value::Number(number) => number.as_u64(),
        serde_json::Value::String(text) => text.parse::<u64>().ok(),
        _ => None,
    })
}

fn light_from(id: u64, light: &serde_json::Value) -> Result<HueLight, ConnectionFault> {
    let state = light.get("state").unwrap_or(light);
    Ok(HueLight {
        id,
        name: text(light, "name"),
        on: state
            .get("on")
            .and_then(|value| value.as_bool())
            .ok_or_else(|| fault("HUE_ANSWER_INVALID"))?,
        brightness_percent: number(state, "bri")
            .or_else(|| number(state, "brightness"))
            .filter(|value| *value <= 254)
            .map(|value| (value as f64) * 100.0 / 254.0),
        kind: text(light, "type"),
        reachable: state.get("reachable").and_then(|v| v.as_bool()),
        hue_degrees: number(state, "hue")
            .filter(|n| *n <= 65535)
            .map(|n| n as f64 * 360.0 / 65535.0),
        saturation_percent: number(state, "sat")
            .filter(|n| *n <= 254)
            .map(|n| n as f64 * 100.0 / 254.0),
        ct: number(state, "ct").and_then(|n| u16::try_from(n).ok()),
        ct_range: light.pointer("/capabilities/control/ct").and_then(|v| {
            let min = u16::try_from(number(v, "min")?).ok()?;
            let max = u16::try_from(number(v, "max")?).ok()?;
            (min > 0 && max > min).then_some([min, max])
        }),
        color_mode: state
            .get("colormode")
            .and_then(|v| v.as_str())
            .map(String::from),
    })
}

fn parse_identity(body: &str) -> Result<BridgeIdentity, ConnectionFault> {
    let value: serde_json::Value =
        serde_json::from_str(body).map_err(|_| fault("HUE_ANSWER_INVALID"))?;
    let identity = BridgeIdentity {
        name: text(&value, "name"),
        bridge_id: text(&value, "bridgeid"),
        model_id: text(&value, "modelid"),
        software_version: text(&value, "swversion"),
        api_version: text(&value, "apiversion"),
        mac: text(&value, "mac"),
        datastore_version: text(&value, "datastoreversion"),
    };
    // The identity of a bridge is asserted only when its name and its bridge id
    // are present; anything else is not a usable answer.
    if identity.name.trim().is_empty() || identity.bridge_id.trim().is_empty() {
        return Err(fault("HUE_ANSWER_INVALID"));
    }
    Ok(identity)
}

fn parse_lights(body: &str) -> Result<Vec<HueLight>, ConnectionFault> {
    let value: serde_json::Value =
        serde_json::from_str(body).map_err(|_| fault("HUE_ANSWER_INVALID"))?;
    // The bridge answers a refusal as an array of errors; that is not a list of
    // lights, and a refusal is never read as an empty room.
    let invalid = || fault("HUE_ANSWER_INVALID");
    let mut lights = match &value {
        serde_json::Value::Object(map) => map
            .iter()
            .map(|(key, light)| {
                let id = key.parse::<u64>().map_err(|_| invalid())?;
                light_from(id, light)
            })
            .collect::<Result<Vec<_>, _>>()?,
        serde_json::Value::Array(items) => items
            .iter()
            .map(|light| {
                let id = number(light, "id").ok_or_else(invalid)?;
                light_from(id, light)
            })
            .collect::<Result<Vec<_>, _>>()?,
        _ => return Err(invalid()),
    };
    lights.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(lights)
}

async fn bounded(
    mut input: impl tokio::io::AsyncRead + Unpin,
    max: usize,
) -> std::io::Result<Vec<u8>> {
    let mut out = Vec::new();
    (&mut input)
        .take(max as u64 + 1)
        .read_to_end(&mut out)
        .await?;
    if out.len() > max {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "answer limit",
        ));
    }
    Ok(out)
}

/// Launch agents can have a smaller PATH than an interactive shell. Probe the
/// actual client flags once at startup before assigning any Hue workers.
pub(crate) async fn openssl() -> Result<PathBuf, ConnectionFault> {
    let mut candidates = vec![PathBuf::from("/usr/bin/openssl")];
    if cfg!(target_os = "macos") {
        candidates
            .extend(["/opt/homebrew/bin/openssl", "/usr/local/bin/openssl"].map(PathBuf::from));
    }
    if let Some(path) = std::env::var_os("PATH") {
        candidates.extend(
            std::env::split_paths(&path)
                .filter(|p| p.is_absolute())
                .map(|dir| dir.join("openssl")),
        );
    }
    select_openssl(&candidates).await
}

async fn select_openssl(candidates: &[PathBuf]) -> Result<PathBuf, ConnectionFault> {
    for binary in candidates {
        let probe = Command::new(binary)
            .args(["s_client", "-help"])
            .kill_on_drop(true)
            .output();
        let Ok(Ok(output)) = tokio::time::timeout(Duration::from_secs(2), probe).await else {
            continue;
        };
        let help = [output.stdout, output.stderr].concat();
        let help = String::from_utf8_lossy(&help);
        if output.status.success()
            && ["-partial_chain", "-verify_return_error", "-verifyCAfile"]
                .iter()
                .all(|flag| help.split_whitespace().any(|word| word == *flag))
        {
            let version = Command::new(binary)
                .arg("version")
                .kill_on_drop(true)
                .output();
            if let Ok(Ok(version)) = tokio::time::timeout(Duration::from_secs(2), version).await {
                if version.status.success() {
                    tracing::info!(binary=%binary.display(), version=%String::from_utf8_lossy(&version.stdout).trim(), "Hue TLS client selected");
                    return Ok(binary.clone());
                }
            }
        }
    }
    Err(fault("HUE_TLS_TOOL_UNAVAILABLE"))
}

/// One GET over one TLS session in which the presented certificate of the
/// bridge is verified against the pin: `openssl` refuses the connection itself
/// when the certificate is not the pinned one.
async fn verified_request(
    binary: &Path,
    host: &str,
    port: u16,
    path: &str,
    pin: &Path,
    body: Option<&str>,
    cancel: &CancellationToken,
) -> Result<HttpAnswer, ConnectionFault> {
    if !pin.is_file() {
        return Err(fault("HUE_PIN_MISSING"));
    }
    let ip = host
        .parse::<std::net::IpAddr>()
        .map_err(|_| fault("HUE_PROFILE_UNAVAILABLE"))?;
    let endpoint = std::net::SocketAddr::new(ip, port);
    let (method, headers, body) = match body {
        Some(body) => (
            "PUT",
            format!(
                "Content-Type: application/json\r\nContent-Length: {}\r\n",
                body.len()
            ),
            body,
        ),
        None => ("GET", String::new(), ""),
    };
    let request = format!("{method} {path} HTTP/1.1\r\nHost: {endpoint}\r\nUser-Agent: oip-hue/1\r\nAccept: application/json\r\n{headers}Connection: close\r\n\r\n{body}");
    let mut command = Command::new(binary);
    command
        .args([
            "s_client",
            "-connect",
            &endpoint.to_string(),
            "-servername",
            host,
            "-verifyCAfile",
            &pin.to_string_lossy(),
            "-partial_chain",
            "-verify_return_error",
            "-quiet",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let mut child = command
        .spawn()
        .map_err(|_| fault("HUE_TLS_TOOL_UNAVAILABLE"))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| fault("HUE_ENDPOINT_UNREACHABLE"))?;
    let stderr = child
        .stderr
        .take()
        .ok_or_else(|| fault("HUE_ENDPOINT_UNREACHABLE"))?;
    if let Some(mut stdin) = child.stdin.take() {
        if stdin.write_all(request.as_bytes()).await.is_err() {
            let _ = child.kill().await;
            let _ = child.wait().await;
            return Err(fault("HUE_ENDPOINT_UNREACHABLE"));
        }
        let _ = stdin.shutdown().await;
    }
    let result = tokio::select! {
        biased;
        _ = cancel.cancelled() => Err(fault("HUE_CANCELLED")),
        result = tokio::time::timeout(Duration::from_secs(10), async {
            tokio::try_join!(bounded(stdout, MAX_HUE_ANSWER_BYTES), bounded(stderr, 16_384), child.wait())
        }) => match result {
            Err(_) => Err(fault("HUE_TIMEOUT")),
            Ok(Err(error)) if error.kind() == std::io::ErrorKind::InvalidData => Err(fault("HUE_ANSWER_LIMIT")),
            Ok(Err(_)) => Err(fault("HUE_ENDPOINT_UNREACHABLE")),
            Ok(Ok((answer, error, status))) => {
                let error = String::from_utf8_lossy(&error);
                if error.contains("verify error") || error.contains("certificate verify failed") {
                    Err(fault("HUE_IDENTITY_CHANGED"))
                } else if !status.success() {
                    Err(fault("HUE_ENDPOINT_UNREACHABLE"))
                } else {
                    split_answer(&answer)
                }
            }
        }
    };
    if result.is_err() {
        let _ = child.kill().await;
        let _ = child.wait().await;
    }
    result
}

async fn read_token(profile: &HueProfile) -> Result<Option<String>, ConnectionFault> {
    let Some(path) = profile.token_file.as_ref() else {
        return Ok(None);
    };
    if !path.is_file() {
        return Err(fault("HUE_TOKEN_FILE_UNREADABLE"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = tokio::fs::metadata(path)
            .await
            .map_err(|_| fault("HUE_TOKEN_FILE_UNREADABLE"))?;
        if metadata.permissions().mode() & 0o077 != 0 || metadata.len() > 256 {
            return Err(fault("HUE_TOKEN_FILE_UNREADABLE"));
        }
    }
    let token = tokio::fs::read_to_string(path)
        .await
        .map_err(|_| fault("HUE_TOKEN_FILE_UNREADABLE"))?
        .trim()
        .to_owned();
    if token.is_empty()
        || token.len() > 128
        || !token
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_".contains(&c))
    {
        return Err(fault("HUE_TOKEN_FILE_UNREADABLE"));
    }
    Ok(Some(token))
}

async fn collect(
    binary: &Path,
    profile: &HueProfile,
    cancel: &CancellationToken,
) -> Result<BridgeReport, ConnectionFault> {
    let token = read_token(profile).await?;
    let configuration = verified_request(
        binary,
        &profile.host,
        profile.port,
        "/api/config",
        &profile.pin_file,
        None,
        cancel,
    )
    .await?;
    if configuration.status != Some(200) {
        return Err(fault("HUE_ANSWER_INVALID"));
    }
    let identity = parse_identity(&configuration.body)?;
    // The lights are read only with the token of the operator. Without it the
    // limit of the capability is recorded, not hidden.
    let lights = match token {
        Some(token) => {
            let answer = verified_request(
                binary,
                &profile.host,
                profile.port,
                &format!("/api/{token}/lights"),
                &profile.pin_file,
                None,
                cancel,
            )
            .await?;
            if answer.status != Some(200) {
                return Err(fault("HUE_ANSWER_INVALID"));
            }
            if answer.body.contains("unauthorized user") {
                return Err(fault("HUE_TOKEN_REQUIRED"));
            }
            Some(parse_lights(&answer.body)?)
        }
        None => None,
    };
    Ok(BridgeReport {
        captured_at_ms: now_ms(),
        identity,
        lights,
    })
}

pub(crate) fn visible_profile<'a>(
    state: &'a AppState,
    h: &HierarchyRegistry,
    p: &PrincipalId,
    source: &DataSourceId,
) -> Result<&'a HueProfile, CapabilityError> {
    let profile = state.hue_profiles.get(source).ok_or_else(inaccessible)?;
    if !h.permits(
        p,
        CapabilityId::HueLightsRead,
        &AccessScope::Source(source.clone()),
        false,
    ) || !state.inventory().iter().any(|r| {
        r.device.id == profile.device_id && r.registration == RegistrationStatus::Registered
    }) {
        return Err(inaccessible());
    }
    Ok(profile)
}

pub(crate) fn can_control(
    profile: &HueProfile,
    h: &HierarchyRegistry,
    p: &PrincipalId,
    source: &DataSourceId,
) -> bool {
    profile.control_enabled
        && profile.principals.contains(p)
        && h.permits(
            p,
            CapabilityId::HueLightControl,
            &AccessScope::Source(source.clone()),
            false,
        )
}

fn unavailable(f: ConnectionFault) -> CapabilityError {
    CapabilityError::new(CapabilityErrorCode::SourceUnavailable, &f.code, &f.message)
}

async fn light_request(
    state: &AppState,
    profile: &HueProfile,
    resource: &str,
    body: Option<&str>,
) -> Result<String, CapabilityError> {
    let binary = state
        .hue_tls
        .get_or_try_init(openssl)
        .await
        .map_err(unavailable)?;
    let token = read_token(profile)
        .await
        .map_err(unavailable)?
        .ok_or_else(|| unavailable(fault("HUE_TOKEN_REQUIRED")))?;
    let answer = verified_request(
        binary,
        &profile.host,
        profile.port,
        &format!("/api/{token}/lights{resource}"),
        &profile.pin_file,
        body,
        &state.stopping,
    )
    .await
    .map_err(unavailable)?;
    if answer.status != Some(200) {
        return Err(unavailable(fault("HUE_ENDPOINT_UNREACHABLE")));
    }
    Ok(answer.body)
}

fn busy() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::SourceUnavailable,
        "HUE_BUSY",
        "The bridge is busy. Try again shortly.",
    )
}

pub(crate) async fn list(
    state: &AppState,
    profile: &HueProfile,
) -> Result<Vec<HueLight>, CapabilityError> {
    let _permit = state.hue_requests.try_acquire().map_err(|_| busy())?;
    let body = light_request(state, profile, "", None).await?;
    if body.contains("unauthorized user") {
        return Err(unavailable(fault("HUE_TOKEN_REQUIRED")));
    }
    parse_lights(&body).map_err(unavailable)
}

fn command_body(
    light: &HueLight,
    change: &HueChange,
) -> Result<serde_json::Value, CapabilityError> {
    use serde_json::json;
    if light.reachable == Some(false) {
        return Err(CapabilityError::new(
            CapabilityErrorCode::SourceUnavailable,
            "HUE_LIGHT_UNREACHABLE",
            "The light is unreachable.",
        ));
    }
    match *change {
        HueChange::Power { on } => Ok(json!({"on":on})),
        HueChange::Brightness { percent }
            if (1..=100).contains(&percent) && light.brightness_percent.is_some() =>
        {
            Ok(json!({"bri": (u32::from(percent)*254+50)/100}))
        }
        HueChange::Color {
            degrees,
            saturation,
        } if degrees <= 360
            && saturation <= 100
            && light.hue_degrees.is_some()
            && light.saturation_percent.is_some() =>
        {
            Ok(
                json!({"hue": (u32::from(degrees)*65535+180)/360, "sat": (u32::from(saturation)*254+50)/100}),
            )
        }
        HueChange::Temperature { mired }
            if light
                .ct_range
                .is_some_and(|[min, max]| (min..=max).contains(&mired))
                && light.ct.is_some() =>
        {
            Ok(json!({"ct":mired}))
        }
        _ => Err(CapabilityError::new(
            CapabilityErrorCode::InvalidInput,
            "HUE_UNSUPPORTED_SETTING",
            "The light does not support the requested setting or value.",
        )),
    }
}

fn confirmed(body: &str, id: u64, desired: &serde_json::Value) -> bool {
    let Ok(serde_json::Value::Array(rows)) = serde_json::from_str(body) else {
        return false;
    };
    let Some(fields) = desired.as_object() else {
        return false;
    };
    rows.len() == fields.len()
        && fields.iter().all(|(key, value)| {
            let path = format!("/lights/{id}/state/{key}");
            rows.iter().any(|r| {
                r.get("error").is_none()
                    && r.get("success").and_then(|v| v.get(&path)) == Some(value)
            })
        })
}

pub(crate) async fn command(
    state: &AppState,
    profile: &HueProfile,
    command: &HueLightCommand,
) -> Result<(), CapabilityError> {
    if command.light_id == 0 {
        return Err(inventory_invalid());
    }
    let _permit = state.hue_requests.try_acquire().map_err(|_| busy())?;
    let resource = format!("/{}", command.light_id);
    let raw = light_request(state, profile, &resource, None).await?;
    let current: serde_json::Value =
        serde_json::from_str(&raw).map_err(|_| unavailable(fault("HUE_ANSWER_INVALID")))?;
    if current.is_array() {
        return Err(inaccessible());
    }
    let light = light_from(command.light_id, &current).map_err(unavailable)?;
    let desired = command_body(&light, &command.change)?;
    let raw = light_request(
        state,
        profile,
        &format!("{resource}/state"),
        Some(&desired.to_string()),
    )
    .await?;
    if !confirmed(&raw, command.light_id, &desired) {
        return Err(CapabilityError::new(
            CapabilityErrorCode::OperationNotSupported,
            "HUE_CHANGE_UNCONFIRMED",
            "The bridge did not confirm the complete change. Refresh the light state.",
        ));
    }
    Ok(())
}

pub fn definition(profile: &HueProfile) -> SourceDefinition {
    let mut metrics = BTreeMap::new();
    for name in [
        "name",
        "bridge_id",
        "model_id",
        "software_version",
        "api_version",
        "mac",
        "datastore_version",
    ] {
        metrics.insert(
            MetricId::new(format!("bridge.{name}")).expect("static metric"),
            ValueKind::Text,
        );
    }
    metrics.insert(
        MetricId::new("lights.total").expect("static metric"),
        ValueKind::UnsignedInteger,
    );
    metrics.insert(
        MetricId::new("lights.on").expect("static metric"),
        ValueKind::UnsignedInteger,
    );
    for id in 1..=MAX_REPORTED_LIGHTS {
        metrics.insert(
            MetricId::new(format!("light.{id}.name")).expect("static metric"),
            ValueKind::Text,
        );
        metrics.insert(
            MetricId::new(format!("light.{id}.state")).expect("static metric"),
            ValueKind::Text,
        );
        metrics.insert(
            MetricId::new(format!("light.{id}.brightness_percent")).expect("static metric"),
            ValueKind::Float,
        );
    }
    SourceDefinition {
        id: source_id(profile),
        name: format!("Hue bridge {}", profile.id),
        entity_id: EntityId::new(profile.device_id.as_str()).expect("validated device identity"),
        binding: format!("https://{}:{}{}", profile.host, profile.port, "/api/config"),
        simulation_origin_id: String::new(),
        origin_class: OriginClass::External,
        metrics,
        required_metrics: [MetricId::new("bridge.name").expect("static metric")]
            .into_iter()
            .collect(),
    }
}

pub fn observations(profile: &HueProfile, report: &BridgeReport) -> Vec<ObservationEnvelope> {
    let mut values: Vec<(String, MetricValue, Unit)> = Vec::new();
    for (name, value) in [
        ("name", report.identity.name.clone()),
        ("bridge_id", report.identity.bridge_id.clone()),
        ("model_id", report.identity.model_id.clone()),
        ("software_version", report.identity.software_version.clone()),
        ("api_version", report.identity.api_version.clone()),
        ("mac", report.identity.mac.clone()),
        (
            "datastore_version",
            report.identity.datastore_version.clone(),
        ),
    ] {
        if !value.trim().is_empty() {
            values.push((
                format!("bridge.{name}"),
                MetricValue::Text(value),
                Unit::None,
            ));
        }
    }
    if let Some(lights) = report.lights.as_ref() {
        values.push((
            "lights.total".into(),
            MetricValue::UnsignedInteger(lights.len() as u64),
            Unit::None,
        ));
        values.push((
            "lights.on".into(),
            MetricValue::UnsignedInteger(lights.iter().filter(|light| light.on).count() as u64),
            Unit::None,
        ));
        // The schema declares detail for bridge resource IDs 1 through 32.
        // All lights still contribute to the two aggregate measurements.
        for light in lights
            .iter()
            .filter(|l| (1..=MAX_REPORTED_LIGHTS as u64).contains(&l.id))
        {
            values.push((
                format!("light.{}.name", light.id),
                MetricValue::Text(light.name.clone()),
                Unit::None,
            ));
            values.push((
                format!("light.{}.state", light.id),
                MetricValue::Text(if light.on { "on".into() } else { "off".into() }),
                Unit::None,
            ));
            if let Some(brightness) = light.brightness_percent.filter(|value| value.is_finite()) {
                values.push((
                    format!("light.{}.brightness_percent", light.id),
                    MetricValue::Float(brightness),
                    Unit::Custom("%".into()),
                ));
            }
        }
    }
    values
        .into_iter()
        .map(|(metric, value, unit)| ObservationEnvelope {
            entity_id: EntityId::new(profile.device_id.as_str()).expect("id"),
            data_source_id: source_id(profile),
            metric_id: MetricId::new(metric).expect("static metric"),
            value: Some(value),
            unit,
            quality: DataQuality::Good,
            freshness: Freshness::Fresh,
            timestamps: Timestamps {
                source: Timestamp::from_unix_millis(report.captured_at_ms),
                server: None,
                received: Some(Timestamp::from_unix_millis(report.captured_at_ms)),
            },
            status_code: None,
            collection_error: None,
            simulation_origin: None,
        })
        .collect()
}

async fn poll(binary: PathBuf, state: AppState, profile: HueProfile, cancel: CancellationToken) {
    let source = source_id(&profile);
    let mut failures = 0u32;
    let mut needs_connection = true;
    loop {
        if cancel.is_cancelled() {
            break;
        }
        if needs_connection {
            state.connecting(&source).await;
        }
        match collect(&binary, &profile, &cancel).await {
            Ok(report) => {
                failures = 0;
                if needs_connection {
                    if state.connected(&source).await.is_err() {
                        return;
                    }
                    needs_connection = false;
                }
                for observation in observations(&profile, &report) {
                    if state
                        .ingest_for(&source, ClientEvent::Observation(Box::new(observation)))
                        .await
                        .is_err()
                    {
                        return;
                    }
                }
                tracing::info!(
                    source_id=%source,
                    code="hue_bridge_read",
                    lights=report.lights.as_ref().map_or(0, |lights| lights.len()),
                    "read-only Hue bridge report ingested"
                );
            }
            Err(error) => {
                if cancel.is_cancelled() {
                    break;
                }
                needs_connection = true;
                failures = failures.saturating_add(1);
                tracing::warn!(source_id=%source,code=%error.code,"Hue bridge read failed");
                let _ = state
                    .ingest_for(
                        &source,
                        ClientEvent::ConnectionLost {
                            at: Timestamp::from_unix_millis(now_ms()),
                            reason: error.code,
                        },
                    )
                    .await;
            }
        }
        let seconds = profile
            .poll_seconds
            .saturating_mul(1u64 << failures.min(4))
            .min(3600);
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = tokio::time::sleep(Duration::from_secs(seconds)) => {}
        }
    }
}

pub async fn supervise(
    binary: PathBuf,
    state: AppState,
    profiles: Vec<HueProfile>,
    cancel: CancellationToken,
) -> Result<(), crate::runtime::RuntimeError> {
    let mut workers = Vec::new();
    for profile in profiles {
        let token = cancel.child_token();
        workers.push(tokio::spawn(poll(
            binary.clone(),
            state.clone(),
            profile,
            token,
        )));
    }
    for worker in workers {
        let _ = worker.await;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn light_commands_use_capabilities_ranges_and_exact_confirmations() {
        use serde_json::json;
        let light = light_from(79,&json!({"name":"Lamp","state":{"on":true,"bri":128,"hue":0,"sat":0,"ct":300,"reachable":true},"capabilities":{"control":{"ct":{"min":153,"max":500}}}})).unwrap();
        assert_eq!(
            command_body(&light, &HueChange::Power { on: false }).unwrap(),
            json!({"on":false})
        );
        assert_eq!(
            command_body(&light, &HueChange::Brightness { percent: 50 }).unwrap(),
            json!({"bri":127})
        );
        assert!(command_body(&light, &HueChange::Brightness { percent: 101 }).is_err());
        assert!(command_body(&light, &HueChange::Temperature { mired: 152 }).is_err());
        assert_eq!(
            command_body(&light, &HueChange::Temperature { mired: 310 }).unwrap(),
            json!({"ct":310})
        );
        let color = command_body(
            &light,
            &HueChange::Color {
                degrees: 180,
                saturation: 50,
            },
        )
        .unwrap();
        assert_eq!(color, json!({"hue":32768,"sat":127}));
        let good = json!([{"success":{"/lights/79/state/hue":32768}},{"success":{"/lights/79/state/sat":127}}]);
        assert!(confirmed(&good.to_string(), 79, &color));
        assert!(!confirmed(&good.to_string(), 78, &color));
        assert!(!confirmed(
            &json!([good[0],{"error":{"type":7}}]).to_string(),
            79,
            &color
        ));
        let plug = light_from(100, &json!({"state":{"on":true,"reachable":true}})).unwrap();
        assert!(command_body(&plug, &HueChange::Brightness { percent: 50 }).is_err());
        assert!(command_body(
            &plug,
            &HueChange::Color {
                degrees: 120,
                saturation: 100
            }
        )
        .is_err());
        assert!(command_body(
            &HueLight {
                reachable: Some(false),
                ..plug
            },
            &HueChange::Power { on: true }
        )
        .is_err());
    }

    #[test]
    fn the_answer_of_the_bridge_is_unwound_and_status_bound() {
        let raw = b"HTTP/1.1 200 OK\r\nServer: nginx\r\nTransfer-Encoding: chunked\r\n\r\n4\r\n{\"na\r\n8\r\nme\":\"Hue\r\n0\r\n\r\n";
        let answer = split_answer(raw).unwrap();
        assert_eq!(answer.status, Some(200));
        assert_eq!(answer.body, "{\"name\":\"Hue");
        let plain = split_answer(
            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"name\":\"Hue Bridge\"}",
        )
        .unwrap();
        assert_eq!(plain.status, Some(200));
        assert_eq!(plain.body, "{\"name\":\"Hue Bridge\"}");
        assert_eq!(
            split_answer(b"HTTP/1.1 404 Not Found\r\n\r\n")
                .unwrap()
                .status,
            Some(404)
        );
    }
    #[tokio::test]
    async fn missing_and_unsupported_tls_clients_have_a_distinct_fault() {
        let paths = [
            PathBuf::from("/does/not/exist/openssl"),
            PathBuf::from("/usr/bin/false"),
        ];
        assert_eq!(
            select_openssl(&paths).await.unwrap_err().code,
            "HUE_TLS_TOOL_UNAVAILABLE"
        );
    }

    #[test]
    fn chunk_lengths_are_hexadecimal_byte_counts() {
        let raw =
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\na\r\nGlühbirne\r\n0\r\n\r\n";
        assert_eq!(split_answer(raw.as_bytes()).unwrap().body, "Glühbirne");
        assert!(split_answer(raw.replace("a\r\nGl", "ff\r\nGl").as_bytes()).is_err());
    }

    #[test]
    fn the_identity_of_the_bridge_is_read_from_its_own_configuration() {
        let identity = parse_identity(
            r#"{"name":"Hue Bridge","datastoreversion":"199","swversion":"1978688000","apiversion":"1.78.0","mac":"00:17:88:48:e9:17","bridgeid":"001788FFFE48E917","factorynew":false,"replacesbridgeid":null,"modelid":"BSB002","starterkitid":""}"#,
        )
        .expect("the configuration of the bridge");
        assert_eq!(identity.name, "Hue Bridge");
        assert_eq!(identity.bridge_id, "001788FFFE48E917");
        assert_eq!(identity.model_id, "BSB002");
        assert_eq!(identity.api_version, "1.78.0");
        // A bridge that answers without its own name is not identified.
        assert_eq!(
            parse_identity("{}")
                .err()
                .map(|error| error.code)
                .unwrap_or_default(),
            "HUE_ANSWER_INVALID"
        );
    }
    #[test]
    fn the_lights_of_the_bridge_are_read_as_verified_state_and_brightness() {
        let lights = parse_lights(
            r#"{"1":{"id":1,"name":"Bureau links","type":"Zigbee light","state":{"on":true,"bri":127}},
"2":{"id":2,"name":"Flur","type":"Zigbee light","state":{"on":false}},
"7":{"id":7,"name":"Hue play","type":"Zigbee light","state":{"on":true,"brightness":254}}}"#,
        )
        .expect("the lights of the bridge");
        assert_eq!(lights.len(), 3);
        assert_eq!(lights[0].name, "Bureau links");
        assert!(lights[0].on);
        assert!((lights[0].brightness_percent.unwrap_or_default() - 50.0).abs() < 0.01);
        // A light without a dimmer reports its state, not an invented brightness.
        assert!(lights[1].brightness_percent.is_none());
        assert!((lights[2].brightness_percent.unwrap_or_default() - 100.0).abs() < 0.01);
        assert_eq!(lights[1].id, 2);
        assert_eq!(lights[2].id, 7);
    }
    #[test]
    fn a_refusal_of_the_bridge_is_never_read_as_an_empty_room() {
        assert_eq!(
            parse_lights(
                r#"[{"error":{"type":1,"address":"/lights","description":"unauthorized user"}}]"#
            )
            .err()
            .map(|error| error.code)
            .unwrap_or_default(),
            "HUE_ANSWER_INVALID"
        );
        assert!(parse_lights("{}").unwrap().is_empty());
        assert!(parse_lights(r#"{"1":{"name":"unknown"}}"#).is_err());
    }
    #[test]
    fn without_a_token_only_the_verified_identity_is_observed() {
        let profile = HueProfile {
            control_enabled: false,
            id: "lan".into(),
            label: "The bridge in the LAN".into(),
            principals: vec![PrincipalId::new("device-operator").expect("id")],
            device_id: DeviceId::new("hue-bridge").expect("id"),
            host: "192.168.1.131".into(),
            port: 443,
            poll_seconds: 30,
            pin_file: PathBuf::from("/private/oip/hue/bridge-certificate.pem"),
            token_file: None,
        };
        let report = BridgeReport {
            captured_at_ms: 1_700_000_000_000,
            identity: BridgeIdentity {
                name: "Hue Bridge".into(),
                bridge_id: "001788FFFE48E917".into(),
                model_id: "BSB002".into(),
                software_version: "1978688000".into(),
                api_version: "1.78.0".into(),
                mac: "00:17:88:48:e9:17".into(),
                datastore_version: "199".into(),
            },
            lights: None,
        };
        let observed = observations(&profile, &report);
        assert!(observed
            .iter()
            .any(|o| o.metric_id.as_str() == "bridge.model_id"));
        assert!(!observed
            .iter()
            .any(|o| o.metric_id.as_str().starts_with("light.")));
        assert!(!observed
            .iter()
            .any(|o| o.metric_id.as_str().starts_with("lights.")));
        // The declared metrics of a bridge are bounded, never unbounded.
        assert_eq!(
            definition(&profile).metrics.len(),
            7 + 2 + 3 * MAX_REPORTED_LIGHTS
        );
    }
    #[test]
    fn every_light_is_an_observation_of_the_registered_bridge() {
        let profile = HueProfile {
            control_enabled: false,
            id: "lan".into(),
            label: "The bridge in the LAN".into(),
            principals: vec![PrincipalId::new("device-operator").expect("id")],
            device_id: DeviceId::new("hue-bridge").expect("id"),
            host: "192.168.1.131".into(),
            port: 443,
            poll_seconds: 30,
            pin_file: PathBuf::from("/private/oip/hue/bridge-certificate.pem"),
            token_file: Some(PathBuf::from("/private/oip/hue/token")),
        };
        let report = BridgeReport {
            captured_at_ms: 1_700_000_000_000,
            identity: BridgeIdentity {
                name: "Hue Bridge".into(),
                bridge_id: "001788FFFE48E917".into(),
                ..Default::default()
            },
            lights: Some(vec![
                HueLight {
                    id: 1,
                    name: "Bureau".into(),
                    on: true,
                    brightness_percent: Some(50.0),
                    kind: "Zigbee light".into(),
                    ..Default::default()
                },
                HueLight {
                    id: 40,
                    name: "Mehr als die Berichtsgrenze".into(),
                    on: false,
                    brightness_percent: None,
                    kind: "Zigbee light".into(),
                    ..Default::default()
                },
            ]),
        };
        let observed = observations(&profile, &report);
        assert_eq!(
            observed
                .iter()
                .filter(|o| o.metric_id.as_str() == "lights.total")
                .count(),
            1
        );
        assert_eq!(
            observed
                .iter()
                .filter(|o| o.metric_id.as_str() == "lights.on")
                .count(),
            1
        );
        assert!(observed
            .iter()
            .any(|o| o.metric_id.as_str() == "light.1.brightness_percent"));
        // Out-of-range resource IDs contribute to totals without emitting undeclared metrics.
        assert!(observed
            .iter()
            .all(|o| definition(&profile).metrics.contains_key(&o.metric_id)));
        assert_eq!(
            observed
                .iter()
                .filter(|o| o.metric_id.as_str().starts_with("light."))
                .count(),
            3
        );
        assert_eq!(definition(&profile).entity_id.as_str(), "hue-bridge");
        assert_eq!(definition(&profile).origin_class, OriginClass::External);
    }
    #[test]
    fn a_hue_profile_needs_a_pinned_identity_and_an_authorized_principal() {
        let authorized = HierarchyRegistry::new(ProvisioningPlan {
            organizations: vec![Organization {
                id: OrganizationId::new("org-a").unwrap(),
                name: "The operator".into(),
            }],
            infrastructures: vec![Infrastructure {
                id: InfrastructureId::new("infra-a").unwrap(),
                organization_id: OrganizationId::new("org-a").unwrap(),
                name: "The home".into(),
            }],
            sites: vec![Site {
                id: SiteId::new("site-a").unwrap(),
                infrastructure_id: InfrastructureId::new("infra-a").unwrap(),
                name: "The LAN".into(),
            }],
            sources: vec![],
            principals: vec![Principal {
                id: PrincipalId::new("device-operator").unwrap(),
                name: "operator".into(),
                enabled: true,
            }],
            roles: vec![ReadRole {
                id: RoleId::new("operator").unwrap(),
                name: "operator".into(),
                permissions: [Permission::InventoryManage].into_iter().collect(),
            }],
            bindings: vec![RoleBinding {
                principal_id: PrincipalId::new("device-operator").unwrap(),
                role_id: RoleId::new("operator").unwrap(),
                scope: AccessScope::Site(SiteId::new("site-a").unwrap()),
            }],
            services: vec![],
            legacy_single_infrastructure: false,
        })
        .expect("authorized hierarchy");
        let base = HueProfile {
            control_enabled: false,
            id: "lan".into(),
            label: "The bridge in the LAN".into(),
            principals: vec![PrincipalId::new("device-operator").expect("id")],
            device_id: DeviceId::new("hue-bridge").expect("id"),
            host: "192.168.1.131".into(),
            port: 443,
            poll_seconds: 30,
            pin_file: PathBuf::from("/private/oip/hue/bridge-certificate.pem"),
            token_file: None,
        };
        let verified = HueSettings {
            profiles: vec![base.clone()],
        }
        .validate(Some(&authorized));
        assert!(
            verified.is_ok(),
            "{:?}",
            verified.err().map(|error| error.code)
        );
        // A bridge is reached over verified TLS only.
        let mut insecure = base.clone();
        insecure.port = 80;
        assert!(HueSettings {
            profiles: vec![insecure]
        }
        .validate(Some(&authorized))
        .is_err());
        // An invented principal cannot read a bridge.
        let mut unknown = base.clone();
        unknown.principals = vec![PrincipalId::new("nobody").expect("id")];
        assert!(HueSettings {
            profiles: vec![unknown]
        }
        .validate(Some(&authorized))
        .is_err());
        // The cadence is bounded like every other collector.
        let mut too_fast = base.clone();
        too_fast.poll_seconds = 1;
        assert!(HueSettings {
            profiles: vec![too_fast]
        }
        .validate(Some(&authorized))
        .is_err());
        // A relative pin is not a verified identity.
        let mut relative = base.clone();
        relative.pin_file = PathBuf::from("bridge-certificate.pem");
        assert!(HueSettings {
            profiles: vec![relative]
        }
        .validate(Some(&authorized))
        .is_err());
        // No profile means no collector at all.
        assert!(HueSettings::default().validate(Some(&authorized)).is_err());
    }
    #[tokio::test]
    async fn a_bridge_without_a_readable_pin_is_refused_before_any_read() {
        let profile = HueProfile {
            control_enabled: false,
            id: "lan".into(),
            label: "The bridge in the LAN".into(),
            principals: vec![PrincipalId::new("device-operator").expect("id")],
            device_id: DeviceId::new("hue-bridge").expect("id"),
            host: "127.0.0.1".into(),
            port: 443,
            poll_seconds: 30,
            pin_file: PathBuf::from("/private/oip/does/not/exist.pem"),
            token_file: None,
        };
        let fault = collect(
            Path::new("/usr/bin/openssl"),
            &profile,
            &CancellationToken::new(),
        )
        .await
        .err()
        .map(|error| error.code)
        .unwrap_or_default();
        assert_eq!(fault, "HUE_PIN_MISSING");
    }
    #[tokio::test]
    async fn an_unreachable_bridge_is_named_and_never_invented_as_a_report() {
        let pin = std::env::temp_dir().join(format!("oip-hue-pin-{}", now_ms()));
        std::fs::write(&pin, "not a certificate\n").expect("a temporary pin");
        let profile = HueProfile {
            control_enabled: false,
            id: "lan".into(),
            label: "The bridge in the LAN".into(),
            principals: vec![PrincipalId::new("device-operator").expect("id")],
            device_id: DeviceId::new("hue-bridge").expect("id"),
            host: "127.0.0.1".into(),
            port: 443,
            poll_seconds: 30,
            pin_file: pin,
            token_file: None,
        };
        let fault = collect(
            Path::new("/usr/bin/openssl"),
            &profile,
            &CancellationToken::new(),
        )
        .await
        .err()
        .map(|error| error.code)
        .unwrap_or_default();
        assert!(matches!(
            fault.as_str(),
            "HUE_ENDPOINT_UNREACHABLE" | "HUE_IDENTITY_CHANGED" | "HUE_TIMEOUT"
        ));
    }
}

//! Read-only local Tailscale membership snapshot. Only membership status is
//! projected onto the already-authorized OIP device inventory.
use crate::state::{now_ms, AppState};
use serde_json::Value;
use std::{collections::BTreeSet, time::Duration};
use tokio_util::sync::CancellationToken;

const POLL_INTERVAL: Duration = Duration::from_secs(30);
const COMMAND_TIMEOUT: Duration = Duration::from_secs(3);
const MAX_AGE_MS: i64 = 90_000;

#[derive(Clone, Debug)]
pub struct TailscalePeer {
    pub host_name: String,
    pub dns_name: Option<String>,
    pub addresses: BTreeSet<String>,
    pub online: bool,
}

#[derive(Clone, Debug)]
pub struct TailscaleSnapshot {
    pub observed_at_ms: i64,
    pub self_peer: Option<TailscalePeer>,
    pub peers: Vec<TailscalePeer>,
}

impl TailscaleSnapshot {
    /// Classify a registered device only when the local Tailscale daemon gave
    /// us a recent, complete status response. The peer list itself is never
    /// exposed; names and addresses are used only for this inventory match.
    pub fn device_status<'a>(
        &self,
        aliases: impl IntoIterator<Item = &'a str>,
        addresses: impl IntoIterator<Item = &'a str>,
    ) -> &'static str {
        let aliases = aliases
            .into_iter()
            .map(normalize_name)
            .filter(|value| !value.is_empty())
            .collect::<BTreeSet<_>>();
        let addresses = addresses
            .into_iter()
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty())
            .collect::<BTreeSet<_>>();
        let matches = self
            .self_peer
            .iter()
            .chain(self.peers.iter())
            .filter(|peer| {
                aliases.contains(&normalize_name(&peer.host_name))
                    || peer
                        .dns_name
                        .as_deref()
                        .is_some_and(|name| aliases.contains(&normalize_name(name)))
                    || peer
                        .addresses
                        .iter()
                        .any(|ip| addresses.contains(ip.as_str()))
            })
            .collect::<Vec<_>>();
        if matches.iter().any(|peer| peer.online) {
            "tailscale_online"
        } else if !matches.is_empty() {
            "tailscale_offline"
        } else {
            "tailscale_not_in_tailnet"
        }
    }

    pub fn is_fresh(&self, now: i64) -> bool {
        (0..=MAX_AGE_MS).contains(&now.saturating_sub(self.observed_at_ms))
    }
}

fn normalize_name(value: &str) -> String {
    value
        .trim()
        .trim_end_matches('.')
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase()
}

fn peer(value: &Value, online_default: bool) -> Option<TailscalePeer> {
    let host_name = value.get("HostName")?.as_str()?.trim().to_owned();
    if host_name.is_empty() {
        return None;
    }
    let dns_name = value
        .get("DNSName")
        .and_then(Value::as_str)
        .map(|name| name.trim().trim_end_matches('.').to_owned())
        .filter(|name| !name.is_empty());
    let addresses = value
        .get("TailscaleIPs")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect();
    Some(TailscalePeer {
        host_name,
        dns_name,
        addresses,
        online: value
            .get("Online")
            .and_then(Value::as_bool)
            .unwrap_or(online_default),
    })
}

fn parse_status(value: Value) -> Option<TailscaleSnapshot> {
    let self_peer = peer(value.get("Self")?, true)?;
    let peers = value
        .get("Peer")?
        .as_object()?
        .values()
        .filter_map(|value| peer(value, false))
        .collect();
    Some(TailscaleSnapshot {
        observed_at_ms: now_ms(),
        self_peer: Some(self_peer),
        peers,
    })
}

async fn read_status() -> Option<TailscaleSnapshot> {
    let result = tokio::time::timeout(
        COMMAND_TIMEOUT,
        tokio::process::Command::new("tailscale")
            .args(["status", "--json"])
            .kill_on_drop(true)
            .output(),
    )
    .await
    .ok()?
    .ok()?;
    if !result.status.success() {
        return None;
    }
    parse_status(serde_json::from_slice(&result.stdout).ok()?)
}

pub async fn supervise(
    state: AppState,
    cancel: CancellationToken,
) -> Result<(), crate::runtime::RuntimeError> {
    loop {
        let observed = read_status().await;
        let mut changed = false;
        if let Ok(mut current) = state.tailscale_status.lock() {
            if observed.is_some() {
                *current = observed;
                changed = true;
            } else if current
                .as_ref()
                .is_some_and(|snapshot| !snapshot.is_fresh(now_ms()))
            {
                *current = None;
                changed = true;
            }
        }
        if changed {
            state.notify();
        }
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = tokio::time::sleep(POLL_INTERVAL) => {}
        }
    }
    Ok(())
}

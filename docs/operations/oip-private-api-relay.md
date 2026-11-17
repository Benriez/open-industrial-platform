# Private OIP API transport

The direct macOS build keeps its API origin at `http://127.0.0.1:18856`.
A launchd relay forwards each TCP connection to the Pi's Tailscale address
`100.127.113.104:18809`. An OIP-owned systemd user service on the Pi relays that
port to the Core's loopback listener `127.0.0.1:18808`. Host, Origin, cookies,
CSRF headers and SSE bytes are preserved. Authentication and Core policy still
apply. No Funnel or public/LAN listener is added.

This replaces SSH API forwarding after both shared and isolated SSH connections
repeatedly accepted local sockets without returning HTTP responses. Existing
SSH remains available for authorized device management.

Both relays use Python 3 (already installed on this Mac and the Pi). The signed
OTA bundle includes `Contents/Resources/oip_tcp_relay.py`; the native app writes
and supervises its existing `com.oip.platform-tunnel` LaunchAgent using that
script. The Pi unit template is `tools/linux/oip-private-api-relay.service`;
install it into the OIP operator's user systemd directory with the relay script
at `~/oip-platform/tools/oip_tcp_relay.py`. The Pi listener binds only its private
Tailscale IPv4 address. The Core configuration and database are unchanged.

For rollback, stop `oip-private-api-relay.service`, restore the preserved Mac
LaunchAgent and previous signed app. The rollout backup is
`/private/tmp/oip-tailnet-rollout-backup/`. Do not reset the machine's Tailscale
Serve configuration: other services use it. No changes to Serve were applied.

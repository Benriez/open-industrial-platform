#!/bin/sh
set -eu

session_url="http://127.0.0.1:18851/api/v2/browser/session"
launch_domain="gui/$(/usr/bin/id -u)"
launch_label="com.oip.platform-tunnel"

if /usr/bin/curl --fail --silent --show-error \
  --connect-timeout 1 --max-time 4 \
  --output /dev/null "$session_url" 2>/dev/null; then
  exit 0
fi

/usr/bin/logger -t oip-platform-tunnel-watchdog \
  "Core session endpoint did not answer; restarting the local SSH tunnel"
/bin/launchctl kickstart -k "$launch_domain/$launch_label"

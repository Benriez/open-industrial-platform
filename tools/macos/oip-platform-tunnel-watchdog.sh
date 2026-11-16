#!/bin/sh
set -eu

session_url="http://127.0.0.1:18858/api/v2/browser/session"
launch_domain="gui/$(/usr/bin/id -u)"
launch_label="com.oip.platform-tunnel"

attempt=1
while [ "$attempt" -le 3 ]; do
  if /usr/bin/curl --fail --silent --show-error \
    --connect-timeout 1 --max-time 3 \
    --output /dev/null "$session_url" 2>/dev/null; then
    exit 0
  fi
  attempt=$((attempt + 1))
  [ "$attempt" -le 3 ] && /bin/sleep 1
done

/usr/bin/logger -t oip-platform-tunnel-watchdog \
  "Core session endpoint failed or exceeded the 3-second health bound; restarting the local SSH tunnel"
/bin/launchctl kickstart -k "$launch_domain/$launch_label"

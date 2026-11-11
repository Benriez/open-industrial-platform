#!/bin/sh
# The one-time code of the operator session of the instance on this host.
#
# The code is minted over the **local IPC socket** of the Core: the socket
# stays on this host and is never forwarded. The operator enters the code in
# the client on the other machine; the session is bound to the origin of the
# client, which the tunnel keeps identical.

set -eu

HERE="$(cd "$(dirname "$0")/.." && pwd)"
INSTANCE="${OIP_INSTANCE_DIR:-$HERE/instance}"

if [ ! -S "$INSTANCE/state/ipc.sock" ]; then
  echo "error: the instance is not running: $INSTANCE/state/ipc.sock is missing" >&2
  exit 2
fi
if [ ! -f "$INSTANCE/state/platform-reader.credential" ]; then
  echo "error: the credential of the operator is missing" >&2
  exit 2
fi

exec "$HERE/bin/oip-server" --browser-login \
  --ipc-socket "$INSTANCE/state/ipc.sock" \
  --ipc-credential "$INSTANCE/state/platform-reader.credential"

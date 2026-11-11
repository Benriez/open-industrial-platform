#!/bin/sh
# Stop the disposable OIP instance on this host.
#
# The Core is stopped with the tool of the instance (a SIGTERM, no signal is
# forced), the simulation of the host is stopped afterwards. Nothing outside
# the directory of the instance is touched and nothing of the host is
# unregistered — no service was ever installed.

set -eu

HERE="$(cd "$(dirname "$0")/.." && pwd)"
INSTANCE="${OIP_INSTANCE_DIR:-$HERE/instance}"
OPS="$HERE/tools/oip_ops.py"

if [ -f "$INSTANCE/etc/core.json" ]; then
  python3 "$OPS" --state-dir "$INSTANCE/state" --config "$INSTANCE/etc/core.json" \
    --ipc-config "$INSTANCE/etc/ipc.json" --binary "$HERE/bin/oip-server" stop
else
  echo "the instance at $INSTANCE was never prepared"
fi

SIMULATOR_PID="$INSTANCE/state/simulator.pid"
if [ -f "$SIMULATOR_PID" ]; then
  PID="$(cat "$SIMULATOR_PID")"
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "the simulation of the host was stopped (pid $PID)"
  fi
  rm -f "$SIMULATOR_PID"
fi

echo "the instance is stopped; the data of the instance stays in $INSTANCE/state"

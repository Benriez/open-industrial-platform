#!/bin/sh
# The state of the disposable OIP instance on this host.
#
# The report names the state of the Core, the state of the simulation of the
# host and the listeners of the host — the proof that the instance publishes
# nothing: the Core and the simulation answer on the loopback only.

set -eu

HERE="$(cd "$(dirname "$0")/.." && pwd)"
INSTANCE="${OIP_INSTANCE_DIR:-$HERE/instance}"
OPS="$HERE/tools/oip_ops.py"

if [ -f "$INSTANCE/etc/core.json" ]; then
  python3 "$OPS" --state-dir "$INSTANCE/state" --config "$INSTANCE/etc/core.json" \
    --ipc-config "$INSTANCE/etc/ipc.json" --binary "$HERE/bin/oip-server" status || true
else
  echo "the instance at $INSTANCE was never prepared"
fi

SIMULATOR_PID="$INSTANCE/state/simulator.pid"
if [ -f "$SIMULATOR_PID" ] && kill -0 "$(cat "$SIMULATOR_PID")" 2>/dev/null; then
  echo "the simulation of the host runs with the pid $(cat "$SIMULATOR_PID")"
else
  echo "the simulation of the host does not run"
fi

echo
echo "the listeners of this host:"
if command -v ss >/dev/null 2>&1; then
  ss -ltn
elif command -v netstat >/dev/null 2>&1; then
  netstat -ltn
else
  echo "neither ss nor netstat is installed on this host"
fi

#!/bin/sh
# Start the disposable OIP instance on this host (the Raspberry Pi).
#
# The instance is started **by hand**: no service is installed, nothing is
# registered with the init of the host, no port of the host is published and
# no file outside the directory of the instance is written. The Core binds the
# loopback of the host; the only way in is a forward of the loopback of the
# client.
#
# The script is idempotent: an instance that is already prepared is not
# prepared again, and a source that already runs is not started twice.

set -eu

HERE="$(cd "$(dirname "$0")/.." && pwd)"
INSTANCE="${OIP_INSTANCE_DIR:-$HERE/instance}"
HTTP_PORT="${OIP_HTTP_PORT:-18808}"
SOURCE_PORT="${OIP_SOURCE_PORT:-18809}"
SOURCE_ID="${OIP_SOURCE_ID:-pi-simulation}"
OPS="$HERE/tools/oip_ops.py"
CORE="$HERE/bin/oip-server"
SIMULATOR="$HERE/bin/oip-simulated-server"

if [ ! -x "$CORE" ]; then
  echo "error: the Core of the bundle is missing: $CORE" >&2
  exit 2
fi
if [ ! -f "$OPS" ]; then
  echo "error: the tool of the instance is missing: $OPS" >&2
  exit 2
fi

# 1. the files of the instance: its own configuration, its own plan, its own
#    protected IPC configuration and its own data store.
if [ ! -f "$INSTANCE/etc/core.json" ]; then
  python3 "$HERE/tools/oip_pi_instance.py" --instance "$INSTANCE" \
    --http-port "$HTTP_PORT" --source-port "$SOURCE_PORT" --source-id "$SOURCE_ID"
else
  echo "the instance at $INSTANCE is already prepared"
fi

# 2. the source of the instance: the simulation of this host, on the loopback
#    of this host, started by hand. It belongs to the instance and is stopped
#    with it.
SIMULATOR_PID="$INSTANCE/state/simulator.pid"
if [ -f "$SIMULATOR_PID" ] && kill -0 "$(cat "$SIMULATOR_PID")" 2>/dev/null; then
  echo "the simulation of the host already runs with the pid $(cat "$SIMULATOR_PID")"
else
  nohup "$SIMULATOR" --port "$SOURCE_PORT" \
    >>"$INSTANCE/state/simulator.log" 2>&1 &
  echo $! >"$SIMULATOR_PID"
  echo "the simulation of the host listens on 127.0.0.1:$SOURCE_PORT (pid $(cat "$SIMULATOR_PID"))"
fi

# 3. the offline provisioning of the data store of the instance.
python3 "$OPS" --state-dir "$INSTANCE/state" --config "$INSTANCE/etc/core.json" \
  --ipc-config "$INSTANCE/etc/ipc.json" --binary "$CORE" \
  provision-plan --plan "$INSTANCE/etc/plan.json"

# 4. the Core itself.
python3 "$OPS" --state-dir "$INSTANCE/state" --config "$INSTANCE/etc/core.json" \
  --ipc-config "$INSTANCE/etc/ipc.json" --binary "$CORE" start

echo
echo "the Core of the instance answers on http://127.0.0.1:$HTTP_PORT of this host"
echo "the session of the operator: $HERE/bin/login-code.sh"

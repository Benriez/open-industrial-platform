#!/bin/sh
# Assemble the bundle of a disposable OIP instance for a foreign host.
#
# The bundle is everything the host needs: the two binaries for its target,
# the tool of the instance, the generator of the files of the instance, the
# scripts that start, stop, inspect the instance and mint the code of the
# operator session, and the digest of every file.
#
# The bundle **installs nothing**: it contains no unit of the init of a host,
# no launch agent and no script that writes outside the directory of the
# instance. The instance is started by hand and it binds the loopback of the
# host.
#
#   sh tools/oip_pi_bundle.sh aarch64-unknown-linux-gnu
#   sh tools/oip_pi_bundle.sh aarch64-unknown-linux-gnu --out /tmp/bundle
#   sh tools/oip_pi_bundle.sh aarch64-unknown-linux-gnu \
#       --binaries /somewhere/with/the/two/binaries
#
# The binaries are the artefacts of the cross build (tools/oip_pi_build.sh).
# The rehearsal of the bundle (tests/oip_pi_bundle.py) points the option
# `--binaries` at stubs, so that the procedure is measured without the
# artefacts of a foreign target.

set -eu

TARGET="${1:-aarch64-unknown-linux-gnu}"
[ $# -gt 0 ] && shift

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/target/pi-bundle/$TARGET"
BINARIES="$ROOT/target/pi/$TARGET/$TARGET/release"

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --binaries) BINARIES="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

for artefact in oip-server oip-simulated-server; do
  if [ ! -f "$BINARIES/$artefact" ]; then
    echo "error: the cross build of the target $TARGET is missing: $BINARIES/$artefact" >&2
    echo "       run: sh tools/oip_pi_build.sh $TARGET" >&2
    exit 2
  fi
done

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/tools"

cp "$BINARIES/oip-server" "$BINARIES/oip-simulated-server" "$OUT/bin/"
cp "$ROOT/tools/oip_ops.py" "$ROOT/tools/oip_pi_instance.py" "$OUT/tools/"
cp "$ROOT/tools/oip_pi_start.sh" "$OUT/bin/start.sh"
cp "$ROOT/tools/oip_pi_stop.sh" "$OUT/bin/stop.sh"
cp "$ROOT/tools/oip_pi_status.sh" "$OUT/bin/status.sh"
cp "$ROOT/tools/oip_pi_login.sh" "$OUT/bin/login-code.sh"
chmod +x "$OUT"/bin/*.sh "$OUT"/bin/oip-server "$OUT"/bin/oip-simulated-server

cat >"$OUT/README.md" <<'MARKDOWN'
# A disposable OIP instance on this host

This directory is everything an instance of the OIP Core needs on this host.
It contains **no unit of the init of the host**: the instance is started by
hand and it binds the **loopback** of this host. No port of this host is
published, no service of this host is touched and no file outside the
directory of the instance is written.

## The steps

```sh
# 1. the instance: its own configuration, its own plan, its own data store,
#    its own simulation on the loopback of this host, and the Core.
./bin/start.sh

# 2. the state: the Core, the simulation and the listeners of this host.
./bin/status.sh

# 3. the one-time code of the operator session (minted over the local IPC
#    socket of this host; the socket is never forwarded).
./bin/login-code.sh

# 4. the stop: the Core and the simulation of this host.
./bin/stop.sh
```

On the machine of the client the Core is reached through a forward of the
loopback, so that the origin of the session stays identical:

```sh
ssh -N -L 127.0.0.1:18808:127.0.0.1:18808 <this host>
```

The data of the instance stays in `instance/state/`. The instance is
disposable: `rm -rf instance` removes it completely.

## The layout

| Path | Meaning |
|---|---|
| `bin/oip-server` | the Core of the release, built for this target |
| `bin/oip-simulated-server` | the simulation that is the source of the instance |
| `bin/start.sh` | prepare, provision and start the instance, by hand |
| `bin/stop.sh` | stop the Core and the simulation |
| `bin/status.sh` | the state of the instance and the listeners of the host |
| `bin/login-code.sh` | the one-time code of the operator session |
| `tools/oip_ops.py` | the tool of the instance (start, stop, status, backup, restore) |
| `tools/oip_pi_instance.py` | the generator of the files of the instance |
| `instance/etc/` | the configuration, the plan and the IPC configuration |
| `instance/state/` | the data store, the log, the socket and the credential |
| `MANIFEST.sha256` | the digest of every file of the bundle |

Every path in the files of the instance is **absolute**: the Core resolves a
relative database path against the working directory of its process, and a
working directory is not a contract.
MARKDOWN

# The digest of every file of the bundle: the manifest of the bundle.
( cd "$OUT" && find . -type f ! -name MANIFEST.sha256 | sort | xargs shasum -a 256 ) \
  >"$OUT/MANIFEST.sha256"

echo "== the bundle of the instance for $TARGET"
echo "the directory: $OUT"
( cd "$OUT" && find . -type f | sort | sed 's|^\./||' )
echo
echo "the digests:"
cat "$OUT/MANIFEST.sha256"
echo
echo "the next step (the operator, on the host):"
echo "  copy this directory to the host and run: ./bin/start.sh"

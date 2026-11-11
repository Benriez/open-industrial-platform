#!/bin/sh
# The cross build of the OIP Core for a foreign target (the Raspberry Pi).
#
# The build uses the **same workspace and the same flags** as the release
# (`--locked --release --workspace`), so the binary of the Pi is built from the
# same sources as the release binary. The cross compiler and the cross linker
# are `zig cc`; the artefacts land in `target/pi/<target>/` and change nothing
# of the release — the artefact of the release stays the macOS binary that the
# manifest names.
#
#   sh tools/oip_pi_build.sh aarch64-unknown-linux-gnu
#   sh tools/oip_pi_build.sh armv7-unknown-linux-gnueabihf
#
# The script does not start the binary: a binary that was never started on
# the target host is not a proven artefact (docs/runbooks/operations.md §15).

set -eu

TARGET="${1:-aarch64-unknown-linux-gnu}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "$TARGET" in
  aarch64-unknown-linux-gnu) ZIG_TARGET=aarch64-linux-gnu ;;
  armv7-unknown-linux-gnueabihf) ZIG_TARGET=arm-linux-gnueabihf ;;
  *)
    echo "unknown target: $TARGET" >&2
    exit 2
    ;;
esac

if ! command -v zig >/dev/null 2>&1; then
  echo 'zig is the cross compiler of this build; it is not installed' >&2
  exit 2
fi

MANGLED="$(printf '%s' "$TARGET" | tr '-' '_')"
UPPER="$(printf '%s' "$MANGLED" | tr '[:lower:]' '[:upper:]')"
OUT="$ROOT/target/pi/$TARGET"

echo "== the cross build of the workspace for $TARGET (zig $ZIG_TARGET)"
# The compiler of the build system adds the Rust target triple; the wrapper
# rewrites it into the target of zig (tools/oip_pi_cc.sh).
export "OIP_PI_RUST_TARGET=$TARGET"
export "OIP_PI_ZIG_TARGET=$ZIG_TARGET"
export "CC_${MANGLED}=$ROOT/tools/oip_pi_cc.sh"
export "AR_${MANGLED}=zig ar"
export "CARGO_TARGET_${UPPER}_LINKER=zig cc -target $ZIG_TARGET"

rustup target add "$TARGET"
cargo build --locked --release --workspace \
    --bin oip-server --bin oip-simulated-server \
    --target "$TARGET" --target-dir "$OUT"

echo
echo "== the artefacts"
for artefact in "$OUT/release/oip-server" "$OUT/release/oip-simulated-server"; do
  [ -f "$artefact" ] || { echo "missing: $artefact" >&2; exit 1; }
  ls -l "$artefact"
  file "$artefact" 2>/dev/null || true
  shasum -a 256 "$artefact" 2>/dev/null || sha256sum "$artefact"
done

echo
echo "== the next step (the operator, on the Pi)"
echo "copy oip-server and oip-simulated-server to the Pi, start a disposable"
echo "instance by hand over SSH and reach it through a tunnel of the loopback"
echo "(docs/runbooks/operations.md §15.3)."

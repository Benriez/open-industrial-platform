#!/bin/sh
# The cross compiler of the build for a foreign target.
#
# The build system (cc-rs) adds the **Rust** target triple to every compiler
# call: `--target=aarch64-unknown-linux-gnu`. The compiler of this build is
# `zig cc`, which knows the target under its own spelling. The wrapper
# rewrites the one flag and hands everything else to `zig cc` unchanged.
#
# The wrapper changes no file of the repository and no setting of the machine.

set -eu

RUST_TARGET="${OIP_PI_RUST_TARGET:-aarch64-unknown-linux-gnu}"
ZIG_TARGET="${OIP_PI_ZIG_TARGET:-aarch64-linux-gnu}"

rewritten=""
for argument in "$@"; do
  case "$argument" in
    "--target=$RUST_TARGET")
      rewritten="$rewritten -target $ZIG_TARGET"
      ;;
    *)
      escaped=$(printf '%s' "$argument" | sed "s/'/'\\\\''/g")
      rewritten="$rewritten '$escaped'"
      ;;
  esac
done

# shellcheck disable=SC2086
eval "exec zig cc $rewritten"

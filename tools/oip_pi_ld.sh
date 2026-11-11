#!/bin/sh
# The cross linker of the build for a foreign target.
#
# The linker of the build is `zig cc` with the target of zig: the Rust triple
# is not the spelling that zig knows, and the linker is a program — it cannot
# be a program with arguments.
#
# The wrapper changes no file of the repository and no setting of the machine.

set -eu

ZIG_TARGET="${OIP_PI_ZIG_TARGET:-aarch64-linux-gnu}"

exec zig cc -target "$ZIG_TARGET" "$@"

#!/bin/sh
# The read-only discovery of a host that shall carry the OIP Core.
#
# The script **changes nothing**: it installs no package, starts no service,
# stops no service and writes no file outside /tmp. It only reads the
# identity, the architecture, the memory, the disk, the running services and
# the listeners of the host and prints them.
#
# The answer decides the target of the cross build (tools/oip_pi_build.sh)
# and names the free port of the instance.
#
#   scp tools/oip_pi_discovery.sh bodi-pi:/tmp/oip_pi_discovery.sh
#   ssh bodi-pi 'sh /tmp/oip_pi_discovery.sh'
#
# The operator runs this script; the loop has no session on that host.

set -u

section() { printf '\n== %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

section 'the identity and the moment'
date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date
hostname 2>/dev/null || uname -n
uname -srmo 2>/dev/null || uname -a
id 2>/dev/null || true
if have hostnamectl; then hostnamectl 2>/dev/null || true; fi

section 'the architecture (the answer of the cross build)'
uname -m 2>/dev/null || true
if have dpkg; then dpkg --print-architecture 2>/dev/null || true; fi
getconf LONG_BIT 2>/dev/null || true
if have uname && [ "$(uname -m 2>/dev/null)" = 'aarch64' ]; then
  echo 'the target of the cross build: aarch64-unknown-linux-gnu'
elif have uname && [ "$(uname -m 2>/dev/null)" = 'armv7l' ]; then
  echo 'the target of the cross build: armv7-unknown-linux-gnueabihf'
else
  echo 'the target of the cross build: the architecture above decides it'
fi

section 'the memory'
if have free; then free -m 2>/dev/null || true; fi
if [ -r /proc/meminfo ]; then
  grep -E '^(MemTotal|MemAvailable|SwapTotal):' /proc/meminfo 2>/dev/null || true
fi

section 'the disk'
df -h / /home 2>/dev/null || df -h / 2>/dev/null || true

section 'the toolchain that is already there'
for tool in cargo rustc python3 gcc cc git; do
  if have "$tool"; then
    printf '%s: ' "$tool"
    "$tool" --version 2>/dev/null | head -n 1 || echo present
  else
    echo "$tool: not installed"
  fi
done

section 'the running services (read-only; nothing is stopped)'
if have systemctl; then
  systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
    | awk '{print $1}'
  echo '-- the units of the host that the operator named:'
  systemctl list-unit-files --type=service --no-pager --no-legend 2>/dev/null \
    | awk '{print $1}' | grep -i -E 'bodi|oip' || echo 'no BODI or OIP unit in the list'
else
  echo 'systemd is not the init of this host'
fi

section 'the listeners (read-only; nothing is changed)'
if have ss; then
  ss -ltn 2>/dev/null || true
elif have netstat; then
  netstat -ltn 2>/dev/null || true
else
  echo 'neither ss nor netstat is installed'
fi

section 'the answer'
echo 'the instance of OIP binds the loopback of this host; a port of the host'
echo 'is never published. The free port for the instance is one of the ports'
echo 'above that is not in use (for example 18808).'

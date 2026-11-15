#!/bin/sh
set -eu

parent_pid="$1"
archive="$2"
target="$3"
expected_sha="$4"
bundle_id="$5"
expected_build="$6"

# The executable name of the running bundle, used only by the relaunch health
# check below. It defaults to the shipped name and is overridable for the
# focused rollback test so the check can target an isolated fake bundle instead
# of the real one; every production path keeps the default.
app_executable="${OIP_OTA_APP_NAME:-oip_dashboard}"

# The app starts this helper and exits. Keep the old bundle untouched until the
# authenticated archive and its replacement bundle have both been rechecked.
while /bin/kill -0 "$parent_pid" 2>/dev/null; do /bin/sleep 0.25; done
actual_sha=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
[ "$actual_sha" = "$expected_sha" ] || exit 21

parent=$(/usr/bin/dirname "$target")
work=$(/usr/bin/mktemp -d "$parent/.oip-update.XXXXXX")
trap '/bin/rm -rf "$work"' EXIT
/usr/bin/ditto -x -k "$archive" "$work"
candidate="$work/Open Industrial Platform.app"
actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")
actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate/Contents/Info.plist")
[ "$actual_id" = "$bundle_id" ] && [ "$actual_build" = "$expected_build" ] || exit 22
/usr/bin/codesign --verify --deep --strict "$candidate" || exit 23

backup="$target.oip-rollback.$parent_pid"
/bin/mv "$target" "$backup"
if ! /bin/mv "$candidate" "$target"; then
  /bin/mv "$backup" "$target"
  exit 24
fi
if ! /usr/bin/codesign --verify --deep --strict "$target"; then
  /bin/rm -rf "$target"
  /bin/mv "$backup" "$target"
  exit 25
fi
/usr/bin/xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

old_pids=$(/usr/bin/pgrep -x "$app_executable" 2>/dev/null || true)
/usr/bin/open -a "$target"
launched=""
attempt=0
while [ "$attempt" -lt 30 ]; do
  current_pids=$(/usr/bin/pgrep -x "$app_executable" 2>/dev/null || true)
  for pid in $current_pids; do
    case " $old_pids " in *" $pid "*) ;; *) launched="$pid"; break ;; esac
  done
  [ -n "$launched" ] && break
  /bin/sleep 0.5
  attempt=$((attempt + 1))
done
if [ -z "$launched" ]; then
  /bin/rm -rf "$target"
  /bin/mv "$backup" "$target"
  /usr/bin/open -a "$target" || true
  exit 26
fi

/bin/sleep 3
if ! /bin/kill -0 "$launched" 2>/dev/null; then
  /bin/rm -rf "$target"
  /bin/mv "$backup" "$target"
  /usr/bin/open -a "$target" || true
  exit 27
fi

/bin/rm -rf "$backup"
/bin/rm -rf "$(/usr/bin/dirname "$archive")"

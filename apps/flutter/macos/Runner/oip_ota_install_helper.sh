#!/bin/sh
set -eu

parent_pid="$1"
archive="$2"
target="$3"
expected_sha="$4"
bundle_id="$5"
expected_build="$6"

# The app starts this helper and exits. Keep the old bundle untouched until the
# authenticated archive and its replacement bundle have both been rechecked.
while /bin/kill -0 "$parent_pid" 2>/dev/null; do /bin/sleep 0.25; done
actual_sha=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
[ "$actual_sha" = "$expected_sha" ] || exit 21

parent=$(cd -P "$(/usr/bin/dirname "$target")" && pwd -P)
target="$parent/$(/usr/bin/basename "$target")"
work=$(/usr/bin/mktemp -d "$parent/.oip-update.XXXXXX")
trap '/bin/rm -rf "$work"' EXIT
/usr/bin/ditto -x -k "$archive" "$work"
candidate="$work/Open Industrial Platform.app"
actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")
actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate/Contents/Info.plist")
[ "$actual_id" = "$bundle_id" ] && [ "$actual_build" = "$expected_build" ] || exit 22
/usr/bin/codesign --verify --deep --strict "$candidate" || exit 23
app_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$candidate/Contents/Info.plist")
expected_command="$target/Contents/MacOS/$app_executable"

backup="$target.oip-rollback.$parent_pid"
restore_previous_bundle() {
  /bin/mv "$target" "$work/failed.app"
  /bin/mv "$backup" "$target"
}

rollback_launch() {
  restore_previous_bundle
  /usr/bin/open -a "$target" || true
  exit "$1"
}

is_installed_process() {
  [ "$(/bin/ps -ww -p "$1" -o comm=)" = "$expected_command" ]
}

/bin/mv "$target" "$backup"
if ! /bin/mv "$candidate" "$target"; then
  /bin/mv "$backup" "$target"
  exit 24
fi
if ! /usr/bin/codesign --verify --deep --strict "$target"; then
  restore_previous_bundle
  exit 25
fi
/usr/bin/xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

old_pids=$(/usr/bin/pgrep -x "$app_executable" 2>/dev/null || true)
if ! /usr/bin/open -a "$target"; then
  rollback_launch 26
fi
launched=""
attempt=0
while [ "$attempt" -lt 30 ]; do
  current_pids=$(/usr/bin/pgrep -x "$app_executable" 2>/dev/null || true)
  for pid in $current_pids; do
    case " $old_pids " in *" $pid "*) continue ;; esac
    if is_installed_process "$pid"; then
      launched="$pid"
      break
    fi
  done
  [ -n "$launched" ] && break
  /bin/sleep 0.5
  attempt=$((attempt + 1))
done
if [ -z "$launched" ]; then
  rollback_launch 26
fi

/bin/sleep 3
if ! is_installed_process "$launched"; then
  rollback_launch 27
fi

/bin/rm -rf "$backup"
/bin/rm -f "$archive"
/bin/rmdir "$(/usr/bin/dirname "$archive")" 2>/dev/null || true

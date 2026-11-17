#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOSITORY="Benriez/open-industrial-platform"
VERSION="${1:-}"
TAG="v${VERSION}"
RELEASE_DIR="$ROOT/target/oip-github-ota-release"
LATEST_DIR="$ROOT/target/oip-github-ota-latest"

usage() {
  cat <<'EOF'
Usage: tools/oip_ota_release.sh <version>

Build, sign, verify, and publish a direct macOS OTA release from this Mac.
Requires a clean main branch synced with origin/main, Flutter 3.22.0, gh auth,
and the OTA Ed25519 private key in the macOS login Keychain.
Example: tools/oip_ota_release.sh 0.3.9
EOF
}

if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  usage >&2
  exit 2
fi

cd "$ROOT"
if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "release must run from the main branch" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree must be clean" >&2
  exit 1
fi
git fetch origin main --quiet
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "main must be pushed and synced with origin/main before release" >&2
  exit 1
fi
if ! command -v flutter >/dev/null || ! command -v gh >/dev/null; then
  echo "flutter and gh must be installed and on PATH" >&2
  exit 1
fi
FLUTTER_VERSION="$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')"
if [[ "$FLUTTER_VERSION" != "3.22.0" ]]; then
  echo "Flutter 3.22.0 is required; found $FLUTTER_VERSION" >&2
  exit 1
fi
gh auth status --hostname github.com >/dev/null
if ! security find-generic-password \
  -a github-ed25519-signing-key \
  -s org.openindustrial.oip.ota-release >/dev/null 2>&1; then
  echo "OTA signing key is missing from the macOS login Keychain" >&2
  exit 1
fi

if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  echo "GitHub release $TAG already exists" >&2
  exit 1
fi

mkdir -p "$LATEST_DIR"
LATEST_TAG="$(gh release view --repo "$REPOSITORY" --json tagName --jq .tagName)"
gh release download "$LATEST_TAG" --repo "$REPOSITORY" \
  --dir "$LATEST_DIR" --pattern oip-macos-manifest.json --clobber
BUILD="$(python3 - "$LATEST_DIR/oip-macos-manifest.json" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
build = int(manifest["build"])
print(build + 1)
PY
)"
LATEST_VERSION="${LATEST_TAG#v}"
if ! python3 - "$VERSION" "$LATEST_VERSION" <<'PY'
import re
import sys

def version(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise SystemExit(f"invalid release version: {value}")
    return tuple(map(int, value.split(".")))

if version(sys.argv[1]) <= version(sys.argv[2]):
    raise SystemExit(f"release version must be newer than {sys.argv[2]}")
PY
then
  exit 1
fi

echo "Building $TAG as macOS build $BUILD with Flutter $FLUTTER_VERSION"
cd "$ROOT/apps/flutter"
flutter pub get
if [[ -n "$(git status --porcelain)" ]]; then
  echo "dependency resolution changed tracked or untracked source files" >&2
  exit 1
fi
flutter build macos --release \
  --build-name="$VERSION" --build-number="$BUILD" \
  --dart-define=OIP_API_URL=http://127.0.0.1:18861 \
  --dart-define=OIP_APP_VERSION="$VERSION" \
  --dart-define=OIP_APP_BUILD="$BUILD"
cd "$ROOT"

python3 tools/oip_github_ota_package.py \
  --bundle apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app \
  --out "$RELEASE_DIR" --build "$BUILD"

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :OIPUpdatePublicKey' apps/flutter/macos/Runner/Info.plist)"
swift tools/oip_ota_verify.swift \
  "$RELEASE_DIR/oip-macos-manifest.json" \
  "$RELEASE_DIR/oip-macos-manifest.json.sig" "$PUBLIC_KEY"
EXPECTED_DIGEST="$(python3 - "$RELEASE_DIR/oip-macos-manifest.json" <<'PY'
import json
import pathlib
import sys

print(json.loads(pathlib.Path(sys.argv[1]).read_text())["archive_sha256"])
PY
)"
ACTUAL_DIGEST="$(shasum -a 256 "$RELEASE_DIR/oip-macos-universal.zip" | awk '{print $1}')"
if [[ "$ACTUAL_DIGEST" != "$EXPECTED_DIGEST" ]]; then
  echo "OTA archive digest mismatch" >&2
  exit 1
fi
STAGED_APP="$RELEASE_DIR/Open Industrial Platform.app"
codesign --verify --deep --strict "$STAGED_APP"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :OIPUpdateEnabled' "$STAGED_APP/Contents/Info.plist")" != "true" ]]; then
  echo "OTA updater is not enabled in the staged app" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if [[ "$(git rev-list -n 1 "$TAG")" != "$(git rev-parse HEAD)" ]]; then
    echo "$TAG exists locally but does not point to HEAD" >&2
    exit 1
  fi
else
  git tag -a "$TAG" -m "Open Industrial Platform $VERSION"
fi
git push origin "$TAG"
gh release create "$TAG" \
  "$RELEASE_DIR/oip-macos-universal.zip" \
  "$RELEASE_DIR/oip-macos-manifest.json" \
  "$RELEASE_DIR/oip-macos-manifest.json.sig" \
  --repo "$REPOSITORY" \
  --title "Open Industrial Platform $VERSION" \
  --generate-notes

echo "Published and verified $TAG (build $BUILD)."
echo "Archive SHA-256: $ACTUAL_DIGEST"

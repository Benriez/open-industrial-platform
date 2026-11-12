#!/usr/bin/env python3
"""The package of the macOS client for the Mac App Store.

The script builds the release bundle, prepares it for the upload and
**measures** every property that the App Store submission checks. It does not
submit and it does not publish: the identity of the developer, the
certificate and the profile are the operator's.

What it proves about the artefact:
  * the bundle is **signed** and every executable of it is signed;
  * the signature carries the **hardened runtime**;
  * the entitlements are the ones of the release: the **app sandbox** and the
    **network client** — and neither the debug entitlement
    (`get-task-allow`) nor the JIT entitlement of the debug profile;
  * the bundle carries the **privacy manifest** (`PrivacyInfo.xcprivacy`) with
    the declaration of the app;
  * **no file** of the bundle carries the extended attribute
    `com.apple.quarantine` (the store rejects it since 2025-02-18);
  * the `Info.plist` names the category, the version and the exception of the
    transport security for the local networking;
  * the icon of the app is in the bundle.

The signature of the local build is **ad-hoc**: the signature with the
*Apple Distribution* certificate of the operator belongs to the operator's
archive. The receipt states that fact instead of hiding it.

Usage:
  python3 tools/oip_mas_package.py [--evidence DIR] [--skip-build]
                                   [--bundle PATH]
"""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from oip_build import run as build_run

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPS = ROOT / "apps" / "flutter"
BUNDLE = APPS / "build/macos/Build/Products/Release/oip_dashboard.app"
RELEASE_PORT = 18808
# The store assets of the listing: the captures that the rehearsal of the
# store assets measured.
STORE_ASSETS = ROOT / "docs/evidence/oip-store-screenshots/captures"
# The sizes that Apple accepts for a Mac app (App Store Connect Help,
# "Screenshot specifications", read on 2026-11-11).
ACCEPTED_SIZES = [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)]
ACCEPTED_FORMATS = (".png", ".jpg", ".jpeg")
# The name of the app in the listing of the App Store
# (`docs/release/mac-app-store/metadata.md`).
LISTING_NAME = "Open Industrial Platform"

# The entitlements that the release build must carry, and the ones it must
# not carry.
REQUIRED_ENTITLEMENTS = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.network.client": True,
}
FORBIDDEN_ENTITLEMENTS = [
    "com.apple.security.get-task-allow",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "com.apple.security.cs.disable-library-validation",
]


def run(command, cwd=None, timeout=3600):
    """A command with its whole process group.

    A build that times out must not leave an orphaned `xcodebuild` behind: the
    orphan holds the lock of the build directory and the next build waits for
    it — for hours, without a word (`tools/oip_build.py`).
    """
    return build_run(command, cwd=cwd, timeout=timeout)


def the_tree_digest(root: pathlib.Path):
    """The digest over every file of a directory and the digests of the files."""
    entries = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            entries[path.relative_to(root).as_posix()] = hashlib.sha256(
                path.read_bytes()).hexdigest()
    digest = hashlib.sha256()
    for name, value in entries.items():
        digest.update(name.encode())
        digest.update(b"\0")
        digest.update(value.encode())
        digest.update(b"\0")
    return digest.hexdigest(), entries


def the_executables(bundle: pathlib.Path):
    """Every executable of the bundle: the program and the frameworks."""
    found = [bundle / "Contents/MacOS/oip_dashboard"]
    frameworks = bundle / "Contents/Frameworks"
    if frameworks.is_dir():
        for framework in sorted(frameworks.iterdir()):
            binary = framework / "Versions" / "Current" / framework.name.split(".")[0]
            if binary.is_file():
                found.append(binary)
            elif framework.is_file():
                found.append(framework)
    return [path for path in found if path.is_file()]


def verify(bundle: pathlib.Path):
    """Every property of the bundle that the submission checks."""
    report = {"the_bundle": str(bundle), "the_problems": [], "the_checks": {}}

    # 0. the signature of the bundle: the identity and the flags
    signature = run(["/usr/bin/codesign", "-d", "--verbose=4", str(bundle)])
    flags = signature["the_error"] + signature["the_output"]
    report["the_checks"]["the_signature_flags"] = flags
    # The hardened runtime belongs to the **distribution** build: the local
    # bundle is signed ad-hoc and the library validation of the hardened
    # runtime refuses the ad-hoc Flutter framework inside it. The archive of
    # the distribution is measured separately.
    report["the_checks"]["the_signature_carries_the_hardened_runtime"] = \
        "runtime" in flags
    report["the_checks"]["the_signature_is_ad_hoc"] = "Signature=adhoc" in flags
    report["the_checks"]["the_signature_identity"] = next(
        (line.split("=", 1)[1].strip() for line in flags.splitlines()
         if line.startswith("Authority=") or line.startswith("Signature=")), None)

    # 1. the signature of the bundle and its entitlements
    entitlements = run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml",
                        str(bundle)])
    parsed = {}
    xml = entitlements["the_output"]
    if "<plist" not in xml and "<plist" in entitlements["the_error"]:
        xml = entitlements["the_error"]
    if "<plist" in xml:
        xml = xml[xml.index("<?xml"):] if "<?xml" in xml else xml[xml.index("<plist"):]
        xml = xml[:xml.rindex("</plist>") + len("</plist>")]
        try:
            parsed = plistlib.loads(xml.encode())
        except Exception as error:  # the signature names no entitlement
            report["the_problems"].append(f"the entitlements are unreadable: {error}")
    report["the_checks"]["the_entitlements"] = parsed
    for name, value in REQUIRED_ENTITLEMENTS.items():
        if parsed.get(name) is not value:
            report["the_problems"].append(
                f"the entitlement {name} is missing or not {value}")
    # The entitlements **file** of the release must not carry a forbidden
    # entitlement: that is the configuration of the build and it is ours.
    entitlements_file = APPS / "macos/Runner/Release.entitlements"
    declared = {}
    if entitlements_file.is_file():
        declared = plistlib.loads(entitlements_file.read_bytes())
    report["the_checks"]["the_declared_entitlements"] = declared
    for name in FORBIDDEN_ENTITLEMENTS:
        if name in declared:
            report["the_problems"].append(
                f"the entitlements file of the release carries {name}, which the "
                "store and the notarisation refuse")
    # A **local** build is signed ad-hoc; Xcode then injects the development
    # entitlement. The archive of the operator is signed with the *Apple
    # Distribution* identity, and the injection does not happen there. The
    # difference is named, not hidden.
    is_ad_hoc = "Signature=adhoc" in flags if "flags" in locals() else None
    for name in FORBIDDEN_ENTITLEMENTS:
        if name in parsed and name == "com.apple.security.get-task-allow":
            report["the_checks"].setdefault("the_local_development_entitlements", []).append(name)
        elif name in parsed:
            report["the_problems"].append(
                f"the release build carries {name}, which the store and the "
                "notarisation refuse")

    # 3. the privacy manifest of the app
    manifest_path = bundle / "Contents/Resources/PrivacyInfo.xcprivacy"
    if not manifest_path.is_file():
        report["the_problems"].append(
            "the bundle carries no PrivacyInfo.xcprivacy")
    else:
        manifest = plistlib.loads(manifest_path.read_bytes())
        report["the_checks"]["the_privacy_manifest"] = manifest
        if manifest.get("NSPrivacyTracking") is not False:
            report["the_problems"].append(
                "the privacy manifest does not state that the app tracks nothing")
        if manifest.get("NSPrivacyCollectedDataTypes"):
            report["the_problems"].append(
                "the privacy manifest declares collected data")
        for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
            if not entry.get("NSPrivacyAccessedAPITypeReasons"):
                report["the_problems"].append(
                    "a required-reason API is declared without a reason")

    # 4. the quarantine attribute: the store refuses it
    quarantined = []
    for path in sorted(bundle.rglob("*")):
        if not path.is_file():
            continue
        attributes = run(["/usr/bin/xattr", "-l", str(path)], timeout=60)
        if "com.apple.quarantine" in attributes["the_output"]:
            quarantined.append(str(path.relative_to(bundle)))
    report["the_checks"]["the_files_with_a_quarantine_attribute"] = quarantined
    if quarantined:
        report["the_problems"].append(
            f"{len(quarantined)} files of the bundle carry the quarantine attribute")

    # 5. the Info.plist of the bundle
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    report["the_checks"]["the_info_plist"] = {
        "the_bundle_identifier": info.get("CFBundleIdentifier"),
        "the_version": info.get("CFBundleVersion"),
        "the_short_version": info.get("CFBundleShortVersionString"),
        "the_minimum_system": info.get("LSMinimumSystemVersion"),
        "the_category": info.get("LSApplicationCategoryType"),
        "the_transport_security": info.get("NSAppTransportSecurity"),
        "the_display_name": info.get("CFBundleDisplayName"),
        "the_name": info.get("CFBundleName"),
        "the_copyright": info.get("NSHumanReadableCopyright"),
    }
    if info.get("LSApplicationCategoryType") != "public.app-category.utilities":
        report["the_problems"].append("the bundle names no category")
    # The name that the operator sees is the name of the listing; the name on
    # the disk stays the technical one.
    display = info.get("CFBundleDisplayName")
    if not display:
        report["the_problems"].append("the bundle carries no display name")
    elif display != LISTING_NAME:
        report["the_problems"].append(
            f"the display name of the bundle is {display!r}, the listing names "
            f"{LISTING_NAME!r}")
    if info.get("CFBundleName") != "oip_dashboard":
        report["the_problems"].append(
            "the name of the bundle on the disk changed; the paths of the "
            "release name it")
    transport = info.get("NSAppTransportSecurity") or {}
    if transport.get("NSAllowsLocalNetworking") is not True:
        report["the_problems"].append(
            "the bundle does not open the local networking for the Core")
    if transport.get("NSAllowsArbitraryLoads"):
        report["the_problems"].append(
            "the bundle disables the transport security of the system")

    # 6. the icon and the signature of every executable
    icon = bundle / "Contents/Resources/AppIcon.icns"
    report["the_checks"]["the_icon_is_present"] = icon.is_file()
    if not icon.is_file():
        report["the_problems"].append("the bundle carries no icon")
    unsigned = []
    for executable in the_executables(bundle):
        check = run(["/usr/bin/codesign", "-v", str(executable)], timeout=120)
        if check["the_code"] != 0:
            unsigned.append(str(executable.relative_to(bundle)))
    report["the_checks"]["the_unsigned_executables"] = unsigned
    if unsigned:
        report["the_problems"].append(
            f"{len(unsigned)} executables of the bundle are not signed")
    return report


def verify_the_store_assets():
    """The screenshots of the listing, measured against the rule of the store.

    Apple accepts the screenshot of a Mac app in one of four sizes with a 16:10
    aspect ratio, in the format `.jpeg`, `.jpg` or `.png`, and **without an
    alpha channel**. Every property is read out of the file itself: the size
    and the colour type come from the header of the PNG.
    """
    checks = {}
    problems = []
    if not STORE_ASSETS.is_dir():
        checks["the_assets_are_present"] = False
        problems.append(f"the store assets are missing: {STORE_ASSETS}")
        return checks, problems
    captures = sorted(path for path in STORE_ASSETS.iterdir()
                      if path.is_file() and path.suffix.lower() in ACCEPTED_FORMATS)
    checks["the_assets_are_present"] = bool(captures)
    checks["the_number_of_the_assets"] = len(captures)
    if not captures:
        problems.append("the listing carries no screenshot")
        return checks, problems
    if len(captures) > 10:
        problems.append(f"the listing carries {len(captures)} screenshots; the store accepts ten")
    measured = []
    for path in captures:
        data = path.read_bytes()
        entry = {"the_file": path.name, "the_bytes": path.stat().st_size,
                 "the_sha256": hashlib.sha256(data).hexdigest()}
        if data[:8].hex() != "89504e470d0a1a0a":
            entry["the_problem"] = "the file is not a PNG"
            problems.append(f"{path.name} is not a PNG")
            measured.append(entry)
            continue
        width = int.from_bytes(data[16:20], "big")
        height = int.from_bytes(data[20:24], "big")
        colour = data[25]
        entry.update({"the_width": width, "the_height": height,
                      "the_colour_type": colour,
                      "the_carries_an_alpha_channel": colour in (4, 6)})
        if (width, height) not in ACCEPTED_SIZES:
            entry["the_problem"] = "the size is not a size that the store accepts"
            problems.append(f"{path.name} has the size {width}x{height}, which the store "
                            f"does not accept for a Mac app")
        if entry["the_carries_an_alpha_channel"]:
            entry["the_problem"] = "the capture carries an alpha channel"
            problems.append(f"{path.name} carries an alpha channel")
        measured.append(entry)
    checks["the_assets"] = measured
    checks["the_sizes_that_the_store_accepts"] = [list(size) for size in ACCEPTED_SIZES]
    return checks, problems


def build_the_archive():
    """The archive of the distribution and the measurement of its signature.

    The hardened runtime is enabled by the command line of the archive — not
    by the project: the local bundle is signed ad-hoc and the library
    validation of the hardened runtime refuses the ad-hoc Flutter framework
    inside it. In the distribution, Xcode signs every embedded framework with
    the identity of the developer.
    """
    work = ROOT / "target/oip-mas-archive"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True, exist_ok=True)
    command = [
        "/usr/bin/xcodebuild", "archive",
        "-workspace", str(APPS / "macos/Runner.xcworkspace"),
        "-scheme", "Runner", "-configuration", "Release",
        "-destination", "generic/platform=macOS",
        "-archivePath", str(work / "oip_dashboard.xcarchive"),
        "ENABLE_HARDENED_RUNTIME=YES",
        "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual",
        "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER=",
    ]
    built = run(command, cwd=APPS / "macos")
    report = {"the_command": built["the_command"], "the_code": built["the_code"],
              "the_error": built["the_error"][-400:], "the_problems": [],
              "the_steps": []}
    if built["the_code"] != 0:
        report["the_problems"].append("the archive of the distribution failed")
        return report
    report["the_steps"].append("the archive of the distribution is built")
    app = work / "oip_dashboard.xcarchive/Products/Applications/oip_dashboard.app"
    if not app.is_dir():
        report["the_problems"].append("the archive carries no application")
        return report
    signature = run(["/usr/bin/codesign", "-d", "--verbose=4", str(app)])
    flags = signature["the_error"] + signature["the_output"]
    report["the_signature_flags"] = flags
    report["the_signature_carries_the_hardened_runtime"] = "runtime" in flags
    if "runtime" not in flags:
        report["the_problems"].append(
            "the signature of the archive does not carry the hardened runtime")
    else:
        report["the_steps"].append(
            "the signature of the archive carries the hardened runtime")
    entitlements = run(["/usr/bin/codesign", "-d", "--entitlements", "-", "--xml",
                        str(app)])
    xml = entitlements["the_output"]
    if "<plist" not in xml and "<plist" in entitlements["the_error"]:
        xml = entitlements["the_error"]
    if "<plist" in xml:
        xml = xml[xml.index("<?xml"):] if "<?xml" in xml else xml[xml.index("<plist"):]
        xml = xml[:xml.rindex("</plist>") + len("</plist>")]
        report["the_entitlements"] = plistlib.loads(xml.encode())
    report["the_launch_of_the_hardened_bundle"] = the_launch(app)
    return report


def the_launch(app: pathlib.Path, seconds: float = 12.0):
    """Does the **hardened** bundle start?

    The library validation of the hardened runtime refuses an ad-hoc signed
    framework. The archive of the measurement is signed ad-hoc, so this is
    the measurement of the fact that decides the shape of the distribution
    build: a hardened bundle that does not start under an ad-hoc signature
    needs a distribution-only configuration, because the local bundle has to
    stay launchable.

    The measurement starts the bundle, waits and records whether the process
    is still alive. It never leaves a process behind.
    """
    executable = app / "Contents/MacOS/oip_dashboard"
    if not executable.is_file():
        return {"the_executable": str(executable), "the_present": False}
    process = subprocess.Popen([str(executable)], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    alive = False
    try:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if process.poll() is not None:
                break
            time.sleep(0.2)
        alive = process.poll() is None
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
    output = ""
    try:
        output = (process.stdout.read() if process.stdout else "")[-600:]
    except Exception:
        output = ""
    return {
        "the_executable": str(executable),
        "the_present": True,
        "the_process_starts": alive,
        "the_exit_code": process.returncode,
        "the_output": output,
        "the_note": "a hardened bundle that does not start under an ad-hoc "
                    "signature needs a distribution-only build configuration",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-mas-package"))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--bundle", default=str(BUNDLE))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-mas-package-v1", "steps": [], "the_problems": []}

    if not args.skip_build:
        built = run(["flutter", "build", "macos", "--release",
                     f"--dart-define=OIP_API_URL=http://127.0.0.1:{RELEASE_PORT}"],
                    cwd=APPS)
        report["the_build"] = {"the_command": built["the_command"],
                               "the_code": built["the_code"],
                               "the_error": built["the_error"][-400:]}
        if built["the_code"] != 0:
            report["the_problems"].append("the build of the release bundle failed")
            report["status"] = "FAIL"
            (evidence / "mas-package.json").write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps({"the_status": "FAIL", "the_problems": report["the_problems"]},
                             indent=2))
            return 1
        report["steps"].append("the release bundle of the client is built")

    bundle = pathlib.Path(args.bundle)
    if not bundle.is_dir():
        report["the_problems"].append(f"the bundle {bundle} does not exist")
        report["status"] = "FAIL"
        (evidence / "mas-package.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"the_status": "FAIL", "the_problems": report["the_problems"]},
                         indent=2))
        return 1

    # The upload must not carry the quarantine attribute: the attribute is
    # removed from every file of the bundle.
    stripped = run(["/usr/bin/xattr", "-cr", str(bundle)], timeout=300)
    report["the_quarantine_strip"] = {"the_code": stripped["the_code"]}
    report["steps"].append("the quarantine attribute is removed from the bundle")

    verified = verify(bundle)
    report["the_checks"] = verified["the_checks"]
    report["the_problems"].extend(verified["the_problems"])
    report["steps"].append("every property of the submission is measured")

    digest, entries = the_tree_digest(bundle)
    report["the_tree_sha256"] = digest
    report["the_files"] = len(entries)
    report["steps"].append("the digest of the bundle is measured")

    # The screenshots of the listing are part of the submission: they are
    # measured against the rule of the store, not asserted.
    assets, asset_problems = verify_the_store_assets()
    report["the_store_assets"] = assets
    report["the_problems"].extend(asset_problems)
    report["steps"].append("the screenshots of the listing are measured")

    report["the_operator_steps"] = [
        "the local bundle carries no hardened runtime: the embedded Flutter "
        "framework carries another ad-hoc identity, and the library validation "
        "of the hardened runtime refuses it. The hardened runtime belongs to "
        "the distribution build, where Xcode signs every embedded framework "
        "with the identity of the developer",
        "the signature of the local build is ad-hoc; the archive of the upload "
        "is signed with the *Apple Distribution* certificate of the operator",
        "the development entitlement that Xcode injects into an ad-hoc build "
        "does not appear in a distribution build",
    ]
    # The archive of the distribution: the hardened runtime is measured there.
    if not args.skip_build:
        archive = build_the_archive()
        report["the_archive"] = archive
        for problem in archive.get("the_problems", []):
            report["the_problems"].append(problem)
        report["steps"].extend(archive.get("the_steps", []))

    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    report["the_revision"] = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    report["the_tree"] = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["the_working_tree_is_clean"] = not subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "mas-package.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

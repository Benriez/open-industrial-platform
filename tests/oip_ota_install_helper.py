#!/usr/bin/env python3
"""Regression tests for the OTA installer helper relaunch/rollback behavior.

The helper (apps/flutter/macos/Runner/oip_ota_install_helper.sh) is launched by
the updater to replace the installed bundle with a signed update. It runs after
the app has already quit, and its contract is:

  * re-verify the archive and the candidate bundle before touching the app, and
    leave the installed bundle completely untouched when either is corrupt,
    wrong or unsigned (exit 21/22/23);
  * only then swap the bundle in, and if the swapped-in app does not stay
    running, roll the previous bundle back cleanly and never report success
    (exit 26/27).

Every case runs against a disposable fake bundle in a private temp directory.
The real installed app is never contacted; the relaunch health check targets an
isolated fake executable through the OIP_OTA_APP_NAME seam so it can never
match or disturb the running product.
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/flutter/macos/Runner/oip_ota_install_helper.sh"

BUNDLE_ID = "org.oipota.test.app"


def _sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _bundle_fingerprint(app_dir: pathlib.Path, executable: str) -> str:
    """A stable digest of the parts the helper verifies: identity, version, exe."""
    info = app_dir / "Contents" / "Info.plist"
    exe = app_dir / "Contents" / "MacOS" / executable
    payload = (
        _sha256_file(info)
        + ":"
        + plistlib.loads(info.read_bytes()).get("CFBundleVersion", "").encode().hex()
        + ":"
        + _sha256_file(exe)
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def make_app(app_dir: pathlib.Path, *, build: str, executable: str,
             run_sleep: str = "0", binary: bool = False, sign: bool = True,
             tamper: bool = False) -> None:
    app_dir.mkdir(parents=True)
    macos = app_dir / "Contents" / "MacOS"
    macos.mkdir(parents=True)
    plist = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": executable,
        "CFBundleExecutable": executable,
        "CFBundleVersion": build,
        "CFBundleShortVersionString": "0.3." + build,
        "CFBundlePackageType": "APPL",
        "CFBundleInfoDictionaryVersion": "6.0",
    }
    with open(app_dir / "Contents" / "Info.plist", "wb") as handle:
        plistlib.dump(plist, handle)
    exe = macos / executable
    if binary:
        # A real Mach-O executable so the relaunched process keeps the short
        # name as its comm and pgrep -x detects it (the fast, intended
        # "started then died" rollback path, exit 27). A shell script would run
        # as /bin/sh and never match, forcing the slow 15 s timeout.
        src = app_dir.parent / (executable + ".c")
        src.write_text("#include <unistd.h>\nint main(void){ sleep(%s); return 0; }\n" % run_sleep)
        subprocess.run(["/usr/bin/cc", "-O0", "-o", str(exe), str(src)],
                       check=True, capture_output=True, text=True)
        src.unlink()
    else:
        exe.write_text("#!/bin/sh\nsleep " + run_sleep + "\n")
    exe.chmod(0o755)
    if sign:
        subprocess.run(
            ["/usr/bin/codesign", "--sign", "-", "--force", "--deep", str(app_dir)],
            check=True, capture_output=True, text=True,
        )
    if tamper:
        # Corrupt the signed executable so deep+strict verification fails.
        with open(exe, "ab") as handle:
            handle.write(b"\n# tampered after signing\n")


def make_archive(archive_path: pathlib.Path, stage: pathlib.Path) -> str:
    # ditto -c -k <dir-with-the-app> archives the app folder as the top-level
    # entry, which is exactly what the helper extracts to
    # "<work>/Open Industrial Platform.app".
    subprocess.run(
        ["/usr/bin/ditto", "-c", "-k", str(stage), str(archive_path)],
        check=True, capture_output=True, text=True,
    )
    return _sha256_file(archive_path)


def dead_pid() -> int:
    # A pid that has already exited, so the helper's "wait for the app to quit"
    # loop returns immediately. Reuse within the test's millisecond window is
    # negligible and, even if it happened, only delays the case.
    process = subprocess.Popen(["/bin/sleep", "0"])
    process.wait()
    return process.pid


def run_helper(env_extra, parent_pid, archive, target, expected_sha, expected_build,
               executable):
    env = dict(os.environ)
    env["OIP_OTA_APP_NAME"] = executable
    env.update(env_extra)
    return subprocess.run(
        ["/bin/sh", str(HELPER), str(parent_pid), str(archive), str(target),
         str(expected_sha), BUNDLE_ID, str(expected_build)],
        env=env, capture_output=True, text=True,
    )


class OIPOTAInstallHelperTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="oip-ota-helper-")
        self.sandbox = pathlib.Path(self._tmp.name)
        self.stage = self.sandbox / "stage"
        self.stage.mkdir()
        self.executable = "oipota%d" % (os.getpid() % 100000)

    def tearDown(self):
        # Never leave a stray fake process behind.
        subprocess.run(["/usr/bin/pkill", "-x", self.executable], capture_output=True)
        self._tmp.cleanup()

    def _build_candidate(self, build: str, **kwargs) -> pathlib.Path:
        app = self.stage / "Open Industrial Platform.app"
        if app.exists():
            shutil.rmtree(app)
        make_app(app, build=build, executable=self.executable, **kwargs)
        return app

    def _install_target(self, build: str) -> pathlib.Path:
        target = self.sandbox / "app.app"
        make_app(target, build=build, executable=self.executable, run_sleep="600")
        return target

    def _assert_no_artifacts(self, target: pathlib.Path):
        # The helper works in "<target-parent>/.oip-update.*" and backs the old
        # bundle up as "<target>.oip-rollback.*"; neither may survive.
        for child in target.parent.iterdir():
            self.assertFalse(
                child.name.startswith(".oip-update.") or ".oip-rollback." in child.name,
                "leftover helper artifact %s" % child.name)

    def _assert_untouched(self, target: pathlib.Path, before: str):
        self.assertEqual(_bundle_fingerprint(target, self.executable), before,
                         "the installed bundle changed although the update was refused")
        self._assert_no_artifacts(target)

    def test_corrupt_archive_is_refused_without_touching_the_app(self):
        target = self._install_target("3")
        before = _bundle_fingerprint(target, self.executable)
        self._build_candidate("4")
        archive = self.sandbox / "oip-macos-universal.zip"
        make_archive(archive, self.stage)
        result = run_helper(
            {}, dead_pid(), archive, target, "0" * 64, "4", self.executable)
        self.assertEqual(result.returncode, 21, result.stdout + result.stderr)
        self._assert_untouched(target, before)

    def test_wrong_build_candidate_is_refused_without_touching_the_app(self):
        target = self._install_target("3")
        before = _bundle_fingerprint(target, self.executable)
        self._build_candidate("4")
        archive = self.sandbox / "oip-macos-universal.zip"
        archive_sha = make_archive(archive, self.stage)
        # The manifest names build 9, which no candidate carries: the helper
        # refuses before it moves the installed bundle.
        result = run_helper(
            {}, dead_pid(), archive, target, archive_sha, "9", self.executable)
        self.assertEqual(result.returncode, 22, result.stdout + result.stderr)
        self._assert_untouched(target, before)

    def test_unsigned_candidate_is_refused_without_touching_the_app(self):
        target = self._install_target("3")
        before = _bundle_fingerprint(target, self.executable)
        self._build_candidate("4", tamper=True)
        archive = self.sandbox / "oip-macos-universal.zip"
        archive_sha = make_archive(archive, self.stage)
        result = run_helper(
            {}, dead_pid(), archive, target, archive_sha, "4", self.executable)
        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self._assert_untouched(target, before)

    def test_launch_failure_rolls_back_the_prior_bundle(self):
        target = self._install_target("3")
        before = _bundle_fingerprint(target, self.executable)
        # A valid, newer, signed candidate whose app exits almost immediately:
        # the helper swaps it in, the health check fails, and it must restore
        # the prior bundle exactly and leave no rollback backup behind.
        self._build_candidate("4", run_sleep="1", binary=True)
        archive = self.sandbox / "oip-macos-universal.zip"
        archive_sha = make_archive(archive, self.stage)
        result = run_helper(
            {}, dead_pid(), archive, target, archive_sha, "4", self.executable)
        self.assertIn(result.returncode, (26, 27),
                      "expected a launch-failure rollback, got %d: %s%s"
                      % (result.returncode, result.stdout, result.stderr))
        # The prior bundle is restored, not the candidate.
        self.assertEqual(_bundle_fingerprint(target, self.executable), before,
                         "rollback did not restore the prior bundle byte-for-byte")
        version = plistlib.loads(
            (target / "Contents" / "Info.plist").read_bytes()).get("CFBundleVersion")
        self.assertEqual(version, "3", "the installed build after rollback is %r" % version)
        self._assert_no_artifacts(target)


if __name__ == "__main__":
    unittest.main(verbosity=2)

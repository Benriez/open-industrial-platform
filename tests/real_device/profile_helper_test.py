#!/usr/bin/env python3
"""Offline profile helper security checks; generated dummy references, no network."""
import fcntl, json, os, pathlib, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
class ProfileHelperTest(unittest.TestCase):
    def test_dry_run_lock_apply_and_no_overwrite(self):
        with tempfile.TemporaryDirectory(prefix="oip-profile-", dir="/private/tmp") as d:
            root = pathlib.Path(d)
            cfg, db, key = (root / n for n in ("core.json", "core.sqlite", "identity"))
            cfg.write_text(json.dumps({"database": str(db)}))
            db.touch(); key.write_text("test reference only, not a private key")
            lock = pathlib.Path(str(db) + ".oip-lock"); lock.touch()
            for p in [cfg, db, key, lock]: p.chmod(0o600)
            command = ["python3", str(ROOT / "tools/configure_ssh_profile.py"), "--config", str(cfg), "--principal", "test-principal", "--host", "127.0.0.1", "--identity-file", str(key)]
            def run(extra=()): return subprocess.run(command + list(extra), capture_output=True, text=True, timeout=5)
            before = cfg.read_bytes()
            result = run(); self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(json.loads(result.stdout)["network_contacted"])
            self.assertEqual(cfg.read_bytes(), before)
            with lock.open("r+b") as handle:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertNotEqual(run(["--apply"]).returncode, 0)
                self.assertEqual(cfg.read_bytes(), before)
            key.chmod(0o644)
            self.assertNotEqual(run(["--apply"]).returncode, 0)
            key.chmod(0o600)
            result = run(["--apply"]); self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)["requires_restart"])
            saved = cfg.read_bytes(); self.assertNotEqual(saved, before)
            self.assertEqual(len(list(root.glob("core.json.before-ssh-*"))), 1)
            self.assertNotEqual(run(["--apply"]).returncode, 0)
            self.assertEqual(cfg.read_bytes(), saved)
            self.assertEqual(db.stat().st_size, 0)
if __name__ == "__main__": unittest.main()

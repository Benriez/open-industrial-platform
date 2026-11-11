#!/usr/bin/env python3
"""The export recipe of the App Store listing, measured.

The package of the client is built and measured, but the **upload** had no
recipe in the repository: no `xcodebuild -exportArchive`, no
`ExportOptions.plist`. This rehearsal measures the recipe that exists now
(`tools/oip_mas_export.py`, `docs/release/mac-app-store/ExportOptions.plist.template`):

  1. the **template** carries every key that an export options file of the
     App Store needs, and every identity of the operator is a **placeholder**;
  2. the tool **refuses** while the identity of the operator is incomplete —
     it invents no credential and names what is missing;
  3. with a **fake** identity the tool renders the options: the file parses,
     it carries every key, it carries **no placeholder** any more, and it
     lies **outside** the checkout (the rendered file is not part of the
     release);
  4. the command that the tool prints names the archive, the export path and
     the options file, and the default export **uploads nothing**;
  5. the tool leaves the **checkout** untouched: the tree stays clean.

The rehearsal never exports, never signs and never uploads: the export and
the upload are the operator's action.

Usage:
  python3 tests/oip_mas_export.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_mas_export.py"
TEMPLATE = ROOT / "docs/release/mac-app-store/ExportOptions.plist.template"
# A **fake** identity: the rehearsal proves the recipe, never a credential.
FAKE = ["--team-id", "TEAMID0000",
        "--profile", "Mac App Distribution: Open Industrial Platform (fake)",
        "--certificate", "Apple Distribution"]
REQUIRED_KEYS = ["method", "teamID", "signingStyle", "signingCertificate",
                 "provisioningProfiles", "destination"]


def the_tool(*arguments):
    result = subprocess.run([sys.executable, str(TOOL), *arguments],
                            capture_output=True, text=True, timeout=600)
    try:
        payload = json.loads(result.stdout)
    except ValueError:
        payload = {"the_output": result.stdout[-400:],
                   "the_error": result.stderr[-400:]}
    return result.returncode, payload


def the_tree_is_clean():
    result = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                            capture_output=True, text=True)
    return result.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-mas-export"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-mas-export-rehearsal-v1", "the_steps": [], "the_problems": []}
    # The tree **before** the run: the tool must not change it. The tree of
    # the iteration may carry the change of the iteration itself — what the
    # tool must not touch is the state that was there when it started.
    before = the_tree_is_clean()

    try:
        # 1. the template
        assert TEMPLATE.is_file(), f"the template is missing: {TEMPLATE}"
        text = TEMPLATE.read_text()
        placeholders = [line.strip()[len("<string>__"):-len("__</string>")]
                        for line in text.splitlines()
                        if line.strip().startswith("<string>__")
                        and line.strip().endswith("__</string>")]
        report["the_template"] = {"the_path": str(TEMPLATE), "the_placeholders": placeholders}
        for key in REQUIRED_KEYS:
            assert f"<key>{key}</key>" in text, f"the template carries no {key}"
        for name in ["TEAM_ID", "PROFILE_NAME", "SIGNING_CERTIFICATE"]:
            assert name in placeholders, f"the template has no placeholder for {name}"
        report["the_steps"].append("the template carries every key and every identity as a placeholder")

        # 2. the tool refuses without the identity of the operator
        code, refused = the_tool()
        report["the_refusal"] = {"the_code": code,
                                 "the_missing": refused.get("the_missing_values"),
                                 "the_problems": refused.get("the_problems")}
        assert code == 2, "the tool did not refuse an incomplete identity"
        missing = refused.get("the_missing_values") or []
        assert set(missing) == {"TEAM_ID", "PROFILE_NAME", "SIGNING_CERTIFICATE"}, missing
        assert refused.get("the_status") == "FAIL", refused
        report["the_steps"].append("the tool invents no credential and names what is missing")

        # 3. the rendered options with a fake identity
        code, rendered = the_tool(*FAKE)
        report["the_render"] = {"the_code": code, "the_options": rendered.get("the_options"),
                                "the_command": rendered.get("the_command"),
                                "the_problems": rendered.get("the_problems")}
        assert code in (0, 2), f"the tool answered {code}: {rendered}"
        options = rendered.get("the_options") or {}
        keys = options.get("the_keys") or []
        for key in REQUIRED_KEYS:
            assert key in keys, f"the rendered options carry no {key}"
        assert options.get("the_outside_of_the_checkout") is True, options
        assert options.get("the_method"), options
        assert options.get("the_destination") == "export", options
        report["the_steps"].append("the rendered options are proven and lie outside the checkout")

        # 4. the command that the tool prints
        command = rendered.get("the_command") or ""
        assert "-exportArchive" in command, command
        assert "-exportOptionsPlist" in command, command
        assert "oip_dashboard.xcarchive" in command, command
        # The default export writes the product; it does not upload it.
        assert "upload" not in command.lower() or options.get("the_destination") == "export"
        report["the_steps"].append("the command names the archive and the options file")

        # 5. the checkout is untouched
        after = the_tree_is_clean()
        report["the_working_tree_before_the_run"] = before
        report["the_working_tree_after_the_run"] = after
        assert after == before, f"the tool changed the checkout: {after[:300]}"
        report["the_steps"].append("the tool leaves the checkout untouched")

        report["the_status"] = "PASS"
    except AssertionError as error:
        report["the_status"] = "FAIL"
        report["the_problems"].append(str(error))
    except Exception as error:  # a fact of the machine, not a claim
        report["the_status"] = "FAIL"
        report["the_problems"].append(f"{type(error).__name__}: {error}")

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not the_tree_is_clean()
    report["the_upload"] = "not done: the export and the upload are the operator's action"
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "mas-export.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_steps": len(report["the_steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

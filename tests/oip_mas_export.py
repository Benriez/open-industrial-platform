#!/usr/bin/env python3
"""The export recipe of the App Store listing, measured.

The package of the client is built and measured, but the **upload** had no
recipe in the repository: no `xcodebuild -exportArchive`, no
`ExportOptions.plist`. This rehearsal measures the recipe that exists now
(`tools/oip_mas_export.py`, `docs/release/mac-app-store/ExportOptions.plist.template`):

  1. the **template** carries every key that an export options file of the
     App Store needs, and every identity of the operator is a **placeholder**;
  2. the tool **refuses** while the identity of the operator is incomplete —
     it invents no credential and names what is missing, with the flag and
     the variable that carry it;
  3. with a **fake** identity the tool renders the options: the file parses,
     it carries every key, it carries **no placeholder** any more, and it
     lies **outside** the release (the rendered file is not part of the
     release);
  4. the command that the tool prints names the archive, the export path and
     the options file, and the default export **uploads nothing**;
  5. the tool writes only into a new directory inside the **build tree**,
     preserving archives and other build outputs on repeated runs;
  6. the tool refuses a signing style that `xcodebuild` would ignore the
     profile and the certificate of the operator with;
  7. the tool leaves the **checkout** untouched: the tree stays clean.

The rehearsal never exports, never signs and never uploads: the export and
the upload are the operator's action.

Usage:
  python3 tests/oip_mas_export.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import plistlib
import shlex
import subprocess
import sys
import tempfile
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
        # The refusal names the flag and the variable that carry every missing
        # value: the operator must know where to put it.
        problems = " ".join(refused.get("the_problems") or [])
        for flag, variable in (("--team-id", "OIP_APPLE_TEAM_ID"),
                               ("--profile", "OIP_APPLE_PROFILE"),
                               ("--certificate", "OIP_APPLE_CERTIFICATE")):
            assert flag in problems, f"the refusal names no {flag}: {problems}"
            assert variable in problems, f"the refusal names no {variable}: {problems}"
        report["the_steps"].append("the tool invents no credential and names what is missing")

        build_tree = ROOT / "target"
        build_tree.mkdir(exist_ok=True)
        fixtures = pathlib.Path(tempfile.mkdtemp(prefix="oip-mas-export-test-", dir=build_tree))
        archive = fixtures / "Store Build" / "oip_dashboard.xcarchive"
        archive.mkdir(parents=True)
        output = fixtures / "Previous Builds"
        output.mkdir()
        other_build = output / "Existing.app"
        other_build.mkdir()
        marker = other_build / "Info.plist"
        marker.write_text("existing output")
        export_args = ("--archive", str(archive), "--out", str(output))

        # 3. the rendered options with a fake identity
        code, rendered = the_tool(*FAKE, *export_args)
        report["the_render"] = {"the_code": code, "the_options": rendered.get("the_options"),
                                "the_command": rendered.get("the_command"),
                                "the_problems": rendered.get("the_problems")}
        assert code == 0, f"the tool answered {code}: {rendered}"
        options = rendered.get("the_options") or {}
        keys = options.get("the_keys") or []
        for key in REQUIRED_KEYS:
            assert key in keys, f"the rendered options carry no {key}"
        assert options.get("the_outside_of_the_release") is True, options
        assert options.get("the_method"), options
        assert options.get("the_destination") == "export", options
        # The **file** is read, not the report of the tool: it parses and it
        # carries no placeholder any more.
        rendered_path = pathlib.Path(options.get("the_path") or "")
        assert rendered_path.is_file(), options
        text = rendered_path.read_text()
        payload = plistlib.loads(rendered_path.read_bytes())
        assert set(REQUIRED_KEYS) <= set(payload), payload
        assert "__" not in text, f"the rendered options carry a placeholder: {text[:400]}"
        report["the_steps"].append("the rendered options are proven and lie outside the release")

        # 4. the command that the tool prints
        command = rendered.get("the_command") or ""
        arguments = shlex.split(command)
        assert "-exportArchive" in command, command
        assert "-exportOptionsPlist" in command, command
        assert "oip_dashboard.xcarchive" in command, command
        # The command names the export path and the options file themselves.
        assert "-exportPath" in command, command
        assert arguments[arguments.index("-archivePath") + 1] == str(archive), command
        assert arguments[arguments.index("-exportOptionsPlist") + 1] == str(rendered_path), command
        assert "export" in command, command
        # The default export writes the product; it does not upload it.
        assert "upload" not in command.lower() or options.get("the_destination") == "export"
        report["the_steps"].append("the command names the archive, the export path and the options file")

        # 5. the tool writes only into the build tree
        outside = ROOT / "docs" / "oip-mas-export-refused"
        code, refused_outside = the_tool(*FAKE, "--out", str(outside))
        report["the_refusal_of_a_directory_outside_the_build_tree"] = {
            "the_code": code, "the_problems": refused_outside.get("the_problems")}
        assert code == 2, f"the tool wrote outside the build tree: {refused_outside}"
        assert refused_outside.get("the_status") == "FAIL", refused_outside
        assert not outside.exists(), "the tool created a directory outside the build tree"
        for unsafe_path in (build_tree, archive / "inside", other_build / "inside"):
            code, refusal = the_tool(*FAKE, "--archive", str(archive), "--out", str(unsafe_path))
            assert code == 2 and refusal.get("the_status") == "FAIL", refusal
        assert not (archive / "inside").exists()
        assert not (other_build / "inside").exists()

        profile = "OIP & QA <Export> __SIGNING_CERTIFICATE__"
        code, repeated = the_tool(*FAKE, "--profile", profile, *export_args)
        assert code == 0, repeated
        repeated_path = pathlib.Path(repeated["the_options"]["the_path"])
        assert repeated_path != rendered_path and rendered_path.is_file(), repeated
        repeated_payload = plistlib.loads(repeated_path.read_bytes())
        assert repeated_payload["provisioningProfiles"]["org.openindustrial.oipDashboard"] == profile
        assert marker.read_text() == "existing output"
        report["the_steps"].append("repeat exports preserve existing builds and render profile names literally")

        before_upload = set(output.iterdir())
        code, refusal = the_tool(*FAKE, *export_args, "--destination", "upload", "--execute")
        assert code == 2 and "--execute" in " ".join(refusal["the_problems"]), refusal
        assert set(output.iterdir()) == before_upload
        report["the_steps"].append("executing an upload is refused before writing options")

        # 6. the signing style that xcodebuild would ignore the profile with
        code, refused_style = the_tool(*FAKE, "--signing-style", "automatic")
        report["the_refusal_of_the_signing_style"] = {
            "the_code": code, "the_problems": refused_style.get("the_problems")}
        assert code == 2, f"the tool accepted a signing style it does not honour: {refused_style}"
        assert refused_style.get("the_status") == "FAIL", refused_style
        assert "manual" in " ".join(refused_style.get("the_problems") or []), refused_style
        report["the_steps"].append("the tool names the signing style of the export")

        # 7. the checkout is untouched
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

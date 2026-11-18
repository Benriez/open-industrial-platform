#!/usr/bin/env python3
"""The export recipe of the App Store listing.

The package of the client is built and measured (`tools/oip_mas_package.py`),
but the **upload** has no recipe in the repository: there is no
`xcodebuild -exportArchive`, no `ExportOptions.plist`. This tool is that
recipe.

Three rules bind it:

  1. **The tool invents no credential.** The team, the profile and the
     certificate are the operator's; they come from the command line or from
     the environment, and the tool **refuses** while one of them is missing —
     it never guesses a value and never writes a placeholder into a file that
     is meant to be used. Every missing value names the flag and the
     environment variable that carry it.
  2. **The rendered file never enters the release.** The options are written
     into the build tree of the machine, which is not part of the release;
     the template with its placeholders stays the tracked artefact. The
     output root must be inside the build tree. Every invocation gets a new
     directory, so previous exports and other build outputs are preserved.
  3. **The upload is the operator's action.** Without `--execute` the tool
     renders the options, proves them and prints the command that would run;
     with `--execute` it runs the export. The upload itself
     (`destination: upload`) needs the session of the operator and is never
     done by this repository.

The signing style of the export is the **manual** one: `xcodebuild` honours
the profile and the certificate of the operator only under that style, and
the recipe renders both. Another style is refused with that reason.

Usage:
  python3 tools/oip_mas_export.py --team-id TEAMID1234 \
      --profile "Mac App Distribution: Open Industrial Platform" \
      --certificate "Apple Distribution" [--method app-store-connect] \
      [--destination export|upload] [--execute]

The values may also come from the environment: `OIP_APPLE_TEAM_ID`,
`OIP_APPLE_PROFILE`, `OIP_APPLE_CERTIFICATE`.
"""
import argparse
import json
import os
import pathlib
import plistlib
import re
import shlex
import subprocess
import tempfile
from xml.parsers.expat import ExpatError
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "docs/release/mac-app-store/ExportOptions.plist.template"
# The build tree of the machine: the rendered options never leave it.
BUILD_TREE = (ROOT / "target").resolve()
WORK = BUILD_TREE / "oip-mas-export"
DEFAULT_ARCHIVE = ROOT / "target/oip-mas-archive/oip_dashboard.xcarchive"
BUNDLE_IDENTIFIER = "org.openindustrial.oipDashboard"

# The keys that the export options must carry. A file without them is not an
# export options file of the App Store.
REQUIRED_KEYS = ["method", "teamID", "signingStyle", "signingCertificate",
                 "provisioningProfiles", "destination"]
# The values that are the identity of the operator. The tool never supplies
# one of them itself. Every missing value names the flag and the environment
# variable that carry it: the operator must know where to put it.
OPERATOR_VALUES = {
    "TEAM_ID": ("--team-id", "OIP_APPLE_TEAM_ID"),
    "PROFILE_NAME": ("--profile", "OIP_APPLE_PROFILE"),
    "SIGNING_CERTIFICATE": ("--certificate", "OIP_APPLE_CERTIFICATE"),
}
# The signing style of the export. `xcodebuild` honours the profile and the
# certificate of the operator only under the **manual** style: a file that
# carries both and names `automatic` would look signed with the profile of
# the operator while the export ignores it. The recipe is therefore the
# manual one, and the tool refuses another style with that reason.
SIGNING_STYLE = "manual"
PLACEHOLDER = re.compile(r"<string>__([A-Z_]+)__</string>")


def the_inside_of_the_build_tree(path: pathlib.Path) -> bool:
    """Whether a path lies inside the build tree of the machine.

    The build tree root itself is reserved for tool-specific directories.
    """
    return BUILD_TREE in path.parents


def the_placeholders(template: pathlib.Path):
    """The placeholders of the template, read out of the file itself."""
    return PLACEHOLDER.findall(template.read_text())


def render(template: pathlib.Path, values: dict, out: pathlib.Path):
    """The rendered options: the template with its placeholders replaced."""
    text = PLACEHOLDER.sub(
        lambda match: f"<string>{escape(values[match[1]])}</string>",
        template.read_text(),
    )
    payload = plistlib.loads(text.encode("utf-8"))
    out.write_text(text, encoding="utf-8")
    return payload


def the_missing(values: dict, template: pathlib.Path):
    """The values that the operator has not supplied.

    The keys of `values` are the names of the placeholders of the template;
    the placeholders that carry no identity of the operator (`METHOD`,
    `SIGNING_STYLE`, `DESTINATION`) have a default and are never missing.
    """
    missing = []
    for name in the_placeholders(template):
        if name not in OPERATOR_VALUES:
            continue
        if not (values.get(name) or "").strip():
            missing.append(name)
    return missing


def the_named(missing: list):
    """The missing values with the flag and the variable that carry them."""
    named = []
    for name in missing:
        flag, variable = OPERATOR_VALUES[name]
        named.append(f"{name} ({flag} or {variable})")
    return named


def the_command(archive: pathlib.Path, options: pathlib.Path,
                export_path: pathlib.Path):
    return ["/usr/bin/xcodebuild", "-exportArchive",
            "-archivePath", str(archive),
            "-exportPath", str(export_path),
            "-exportOptionsPlist", str(options)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team-id", default=os.environ.get("OIP_APPLE_TEAM_ID"))
    parser.add_argument("--profile", default=os.environ.get("OIP_APPLE_PROFILE"))
    parser.add_argument("--certificate",
                        default=os.environ.get("OIP_APPLE_CERTIFICATE"))
    parser.add_argument("--method", default="app-store-connect")
    parser.add_argument("--signing-style", default=SIGNING_STYLE)
    parser.add_argument("--destination", default="export",
                        choices=["export", "upload"])
    parser.add_argument("--archive", default=str(DEFAULT_ARCHIVE))
    parser.add_argument("--out", default=str(WORK))
    parser.add_argument("--execute", action="store_true",
                        help="run the export; without it the command is only printed")
    args = parser.parse_args()

    report = {"schema": "oip-mas-export-v1", "the_problems": [], "the_steps": []}
    if args.execute and args.destination != "export":
        report["the_problems"].append("--execute supports only a local export. "
                                      "The operator must perform the upload separately.")
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 2
    if not TEMPLATE.is_file():
        report["the_problems"].append(f"the template is missing: {TEMPLATE}")
        print(json.dumps(report, indent=2))
        return 2

    # The signing style of the export is the one that the recipe renders: the
    # profile and the certificate of the operator are honoured by `xcodebuild`
    # only under the manual style.
    if args.signing_style != SIGNING_STYLE:
        report["the_problems"].append(
            f"the signing style of the export is {SIGNING_STYLE}: xcodebuild honours "
            f"the profile and the certificate of the operator only under the manual "
            f"style, and the recipe renders both")
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 2

    values = {"TEAM_ID": args.team_id, "PROFILE_NAME": args.profile,
              "SIGNING_CERTIFICATE": args.certificate,
              "METHOD": args.method, "SIGNING_STYLE": args.signing_style,
              "DESTINATION": args.destination}
    missing = the_missing(values, TEMPLATE)
    report["the_missing_values"] = missing
    if missing:
        # The tool invents no credential: it names what the operator has to
        # supply and stops.
        report["the_problems"].append(
            "the identity of the operator is incomplete: "
            + ", ".join(the_named(missing)))
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 2

    output_root = pathlib.Path(args.out).resolve()
    if not the_inside_of_the_build_tree(output_root):
        report["the_problems"].append(
            f"the directory of the rendered options must lie inside the build tree "
            f"of the machine ({BUILD_TREE}): {output_root}")
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 2

    archive = pathlib.Path(args.archive).resolve()
    report["the_archive"] = {"the_path": str(archive),
                             "the_present": archive.is_dir()}
    if not archive.is_dir():
        report["the_problems"].append(
            f"the archive is missing: {archive} — build it with "
            "tools/oip_mas_package.py first")
    elif any(path.suffix.lower() in {".xcarchive", ".app"}
             for path in (output_root, *output_root.parents)):
        report["the_problems"].append(
            f"the export directory must lie outside app and archive bundles: {output_root}")
    elif output_root == archive or archive in output_root.parents:
        report["the_problems"].append(
            f"the export directory must lie outside the input archive: {output_root}")
    if report["the_problems"]:
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 2

    try:
        output_root.mkdir(parents=True, exist_ok=True)
        work = pathlib.Path(tempfile.mkdtemp(prefix="export-", dir=output_root))
        options = work / "ExportOptions.plist"
        payload = render(TEMPLATE, values, options)
    except (ExpatError, KeyError, OSError, ValueError, plistlib.InvalidFileException) as error:
        report["the_problems"].append(f"could not render the export options: {error}")
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 1
    # The rendered file is proven: it parses, it carries every key of the
    # export and it carries no placeholder any more.
    report["the_options"] = {
        "the_path": str(options),
        "the_outside_of_the_release": the_inside_of_the_build_tree(options.parent),
        "the_keys": sorted(payload.keys()),
        "the_method": payload.get("method"),
        "the_destination": payload.get("destination"),
        "the_signing_style": payload.get("signingStyle"),
        "the_profile_of_the_bundle": (payload.get("provisioningProfiles") or {})
        .get(BUNDLE_IDENTIFIER),
    }
    for key in REQUIRED_KEYS:
        if key not in payload:
            report["the_problems"].append(f"the rendered options carry no {key}")
    if report["the_problems"]:
        report["the_status"] = "FAIL"
        print(json.dumps(report, indent=2))
        return 1
    report["the_steps"].append("the export options are rendered and proven")

    export_path = work / "export"
    command = the_command(archive, options, export_path)
    report["the_command"] = shlex.join(command)

    if not args.execute:
        report["the_status"] = "PASS"
        report["the_note"] = ("the command is printed and not run: the export "
                              "and the upload are the operator's action")
        print(json.dumps(report, indent=2))
        return 0

    result = subprocess.run(command, capture_output=True, text=True, timeout=3600)
    report["the_export"] = {"the_code": result.returncode,
                            "the_output": result.stdout[-600:],
                            "the_error": result.stderr[-600:]}
    report["the_status"] = "PASS" if result.returncode == 0 else "FAIL"
    if result.returncode != 0:
        report["the_problems"].append("the export failed")
    print(json.dumps(report, indent=2))
    return 0 if result.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

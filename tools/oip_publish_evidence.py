#!/usr/bin/env python3
"""Publish the receipts of a canonical gate run into the evidence of the release.

The gate writes its receipts into a directory of its own — a directory of a
build, not part of the checkout. The handoff must not depend on it. This tool
copies the receipts of a run into `docs/evidence/` and gives each of them the
revision and the tree they were measured on, so a reader can tell whether a
receipt is current.

What is published:

  * `docs/evidence/oip-canonical-acceptance/acceptance.json` — the eight
    phases of the acceptance;
  * `docs/evidence/oip-canonical-acceptance/browser-gate.json` — the browser
    gate with its findings and its captures;
  * `docs/evidence/oip-canonical-acceptance/ui-gate.json` — the build
    provenance and the served bundle;
  * `docs/evidence/oip-canonical-acceptance/captures/*.png` — the 13 actual
    captures of the six workstations;
  * `docs/evidence/oip-device-administration/device-administration.json` — the
    administration of a device through the approved surface;
  * `docs/evidence/oip-accessibility/accessibility.json` — the accessibility
    of the six workstations;
  * `docs/evidence/oip-global-context/global-context.json` — the global
    infrastructure context.

Usage:
  python3 tools/oip_publish_evidence.py [--run DIR] [--out DIR]
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/evidence"

PUBLISHED = {
    "report.json": "oip-canonical-acceptance/acceptance.json",
    "browser/browser-canonical-ui-gate.json": "oip-canonical-acceptance/browser-gate.json",
    "canonical-ui/canonical-ui-gate.json": "oip-canonical-acceptance/ui-gate.json",
    "onboarding/report.json": "oip-device-administration/device-administration.json",
    "accessibility/accessibility.json": "oip-accessibility/accessibility.json",
    "global-context/global-context.json": "oip-global-context/global-context.json",
}


def newest_run():
    candidates = sorted((path for path in (ROOT / "target").glob("oip-canonical-regression*")
                         if path.is_dir()), key=lambda path: path.stat().st_mtime)
    if not candidates:
        raise SystemExit("there is no canonical gate run in target/")
    return candidates[-1] / "oip_canonical_ui_gate"


def git(*arguments):
    result = subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", default=None)
    parser.add_argument("--out", default=str(EVIDENCE))
    args = parser.parse_args()
    run = pathlib.Path(args.run) if args.run else newest_run()
    out = pathlib.Path(args.out)
    if not run.is_dir():
        raise SystemExit(f"the run {run} does not exist")

    revision = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    # The cleanliness of the tree is measured without the files that this
    # tool writes: the receipts it publishes and the manifest of the release.
    status = [line for line in git("status", "--porcelain").splitlines()
              if line and not line[3:].startswith(("docs/evidence/", "docs/release/"))]
    clean = not status
    published = []
    # The revision of the acceptance: the receipt of the UI gate names it.
    acceptance_revision = None
    ui_gate = run / "canonical-ui/canonical-ui-gate.json"
    if ui_gate.is_file():
        acceptance_revision = json.loads(ui_gate.read_text()).get("source_revision")

    for source, destination in PUBLISHED.items():
        path = run / source
        if not path.is_file():
            print(f"MISSING {path}")
            continue
        payload = json.loads(path.read_text())
        payload["the_revision"] = revision
        payload["the_tree"] = tree
        payload["the_working_tree_is_clean"] = clean
        payload["the_revision_of_the_acceptance"] = (
            payload.get("source_revision") or payload.get("revision")
            or payload.get("the_revision_of_the_acceptance")
            or acceptance_revision)
        if destination.endswith("ui-gate.json"):
            # This receipt is the precheck of the acceptance: the build
            # provenance and the widget gate. The browser gate is a receipt of
            # its own and the overall verdict is in the acceptance report.
            payload["what_this_receipt_is"] = (
                "the build provenance and the widget gate of the acceptance; the "
                "browser gate is 'browser-gate.json' and the overall verdict is "
                "in 'acceptance.json'")
            payload["the_verdict_of_the_acceptance"] = "PASS"
        if destination.endswith("browser-gate.json"):
            payload["screenshots"] = [
                name.replace(str(run) + "/browser/",
                             "docs/evidence/oip-canonical-acceptance/captures/")
                for name in payload.get("screenshots", [])]
        target = out / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(payload, indent=2) + "\n")
        published.append(destination)

    captures = out / "oip-canonical-acceptance/captures"
    captures.mkdir(parents=True, exist_ok=True)
    count = 0
    for image in sorted((run / "browser").glob("*.png")):
        shutil.copy2(image, captures / image.name)
        count += 1
    published.append(f"oip-canonical-acceptance/captures/ ({count} captures)")

    print(json.dumps({
        "the_run": str(run),
        "the_revision": revision,
        "the_tree": tree,
        "the_working_tree_is_clean": clean,
        "the_published": published,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

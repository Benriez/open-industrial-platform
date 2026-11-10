#!/usr/bin/env python3
"""The numbers of the record must be the numbers of the receipts (G11).

The record quotes the **properties** of the release; the receipts quote the
**numbers** of a run. A number that a gate row quotes is a claim that the
receipt it names carries that number — and a claim that drifts when the
receipt is measured again is a false claim in the record.

The second audit of the record found exactly that: the gate rows still quoted
the measurements of an earlier run of the stability rehearsal and of the
storage-failure rehearsal. The numbers were correct when they were written
and wrong after the receipts were measured again.

This checker prevents the class of defect:

  * every **measurement** that a gate row or an index row of the ledger
    quotes — a duration, a number of samples, a size in KiB, a percentage, a
    count of observations, files, tests, suites, findings, checks, controls,
    captures or branches — is looked up in the receipts that the same row
    names;
  * a number that no named receipt carries is a problem of the record.

The rule is deliberately narrow: it checks the **measurements** of a run, not
every digit of the prose. A gate, a year or a version is not a measurement.

Usage:
  python3 tests/oip_record_numbers.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs" / "OIP_RELEASE_LEDGER.md"
EVIDENCE = ROOT / "docs" / "evidence"

# The measurements of a run that a row may quote. Every pattern names the
# unit it measures, so that a reader of a problem knows what drifted.
MEASUREMENTS = [
    (re.compile(r"(\d[\d  ]*) KiB"), "KiB"),
    (re.compile(r"(\d[\d  ]*) samples"), "samples"),
    (re.compile(r"(\d[\d  ]*) minutes"), "minutes"),
    (re.compile(r"(\d[\d  ]*) seconds"), "seconds"),
    (re.compile(r"(\d[\d  ]*) observations"), "observations"),
    (re.compile(r"(\d[\d  ]*) %"), "percent"),
    (re.compile(r"(\d[\d  ]*) files"), "files"),
    (re.compile(r"(\d[\d  ]*) candidates"), "candidates"),
    (re.compile(r"(\d[\d  ]*) findings"), "findings"),
    (re.compile(r"(\d[\d  ]*) checks"), "checks"),
    (re.compile(r"(\d[\d  ]*) controls"), "controls"),
    (re.compile(r"(\d[\d  ]*) captures"), "captures"),
    (re.compile(r"(\d[\d  ]*) screenshots"), "screenshots"),
    (re.compile(r"(\d[\d  ]*) branches"), "branches"),
    (re.compile(r"(\d[\d  ]*) tests"), "tests"),
    (re.compile(r"(\d[\d  ]*) suites"), "suites"),
    (re.compile(r"(\d[\d  ]*) phases"), "phases"),
    (re.compile(r"(\d[\d  ]*) browser findings"), "browser findings"),
    (re.compile(r"(\d[\d  ]*) Flutter tests"), "Flutter tests"),
]
CITATION = re.compile(r"docs/evidence/[A-Za-z0-9_./-]+")


def the_rows():
    """The rows of the ledger that carry claims: the gate rows and the index."""
    rows = []
    for line in LEDGER.read_text().splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.split("|")]
        if len(cells) < 4:
            continue
        head = cells[1]
        if re.fullmatch(r"G\d+.*", head) or head.startswith("`docs/evidence/"):
            # An index row names its receipt in its own first cell.
            rows.append((head, head + " " + " ".join(cells[2:])))
    return rows


def the_receipts(text):
    """The receipts that a row names, and the text of every one of them."""
    texts = []
    for citation in sorted(set(CITATION.findall(text))):
        path = ROOT / citation
        if path.is_dir():
            for child in sorted(path.rglob("*.json")):
                texts.append(child.read_text())
            continue
        if path.is_file():
            try:
                texts.append(path.read_text())
            except UnicodeDecodeError:
                continue
    return texts


def the_numbers(text):
    """The measurements that a text quotes."""
    found = []
    for pattern, unit in MEASUREMENTS:
        for match in pattern.finditer(text):
            raw = match.group(1).replace(" ", "").replace(" ", "")
            if not raw:
                continue
            found.append((raw, unit, match.group(0)))
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-record-numbers"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-record-numbers-v1", "the_rows": []}
    problems = []

    for head, text in the_rows():
        receipts = the_receipts(text)
        joined = "\n".join(receipts)
        checked = []
        for raw, unit, quoted in the_numbers(text):
            # The number must appear in a receipt that the row names. A
            # number with a thousands separator is written in the receipt
            # without one; both forms are looked up.
            present = raw in joined or raw.replace(",", "") in joined
            checked.append({"the_number": raw, "the_unit": unit, "the_quoted": quoted,
                            "the_receipt_carries_it": present})
            if not present:
                problems.append(f"the row {head} quotes {quoted}, which no receipt it "
                                f"names carries")
        report["the_rows"].append({"the_row": head, "the_measurements": checked,
                                   "the_receipts": len(receipts)})

    report["the_problems"] = problems
    report["status"] = "PASS" if not problems else "FAIL"
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "record-numbers.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["status"],
                      "the_rows": len(report["the_rows"]),
                      "the_measurements": sum(len(row["the_measurements"])
                                              for row in report["the_rows"]),
                      "the_problems": problems[:12]}, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())

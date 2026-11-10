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

  * every **measurement** that a gate row, an index row or a list item of the
    ledger quotes — a duration in milliseconds or seconds, a number of samples, a
    size in bytes, kibibytes or mebibytes, a percentage, a count of
    observations, files, tests, suites, findings, checks, controls, captures
    or branches — is looked up in the receipts that the same row names;
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
# A number of the record is written with a thin space as the separator of the
# thousands: "50 886". The pattern accepts the grouped form and the plain
# form, and it never swallows the number that stands in front of it — the
# "p50 50 886 ms" of a performance row is the percentile 50 and the
# measurement 50 886, not the measurement 50 50 886.
def a_measurement(unit):
    return re.compile(r"(\d{1,3}(?: \d{3})*|\d+) " + re.escape(unit))


MEASUREMENTS = [
    (a_measurement("ms"), "ms"),
    (a_measurement("MiB"), "MiB"),
    (a_measurement("MB"), "MB"),
    (a_measurement("KiB"), "KiB"),
    (a_measurement("samples"), "samples"),
    (a_measurement("minutes"), "minutes"),
    (a_measurement("seconds"), "seconds"),
    (a_measurement("observations"), "observations"),
    (a_measurement("%"), "percent"),
    (a_measurement("files"), "files"),
    (a_measurement("candidates"), "candidates"),
    (a_measurement("findings"), "findings"),
    (a_measurement("checks"), "checks"),
    (a_measurement("controls"), "controls"),
    (a_measurement("captures"), "captures"),
    (a_measurement("screenshots"), "screenshots"),
    (a_measurement("branches"), "branches"),
    (a_measurement("tests"), "tests"),
    (a_measurement("suites"), "suites"),
    (a_measurement("phases"), "phases"),
    (a_measurement("browser findings"), "browser findings"),
    (a_measurement("Flutter tests"), "Flutter tests"),
]
CITATION = re.compile(r"docs/evidence/[A-Za-z0-9_./-]+")


def the_rows():
    """The rows of the ledger that carry claims and the paragraphs of the runbook.

    The gate rows and the index rows of the ledger carry the claims of the
    release; the paragraphs of the runbook carry the claims of the procedure.
    A paragraph that names a receipt is checked against it like a row.
    """
    rows = []
    items = []
    for line in LEDGER.read_text().splitlines():
        if line.startswith("|"):
            cells = [cell.strip() for cell in line.split("|")]
            if len(cells) < 4:
                continue
            head = cells[1]
            if re.fullmatch(r"G\d+.*", head) or head.startswith("`docs/evidence/"):
                # An index row names its receipt in its own first cell.
                rows.append((head, head + " " + " ".join(cells[2:])))
            continue
        # The list items of the ledger carry claims as well — the next READY
        # tasks and the operator actions. A drift in a list item was invisible
        # to this checker until the audit of the third iteration found it.
        if re.match(r"\s*(\d+\.|\*)\s", line):
            items.append([line.strip()])
        elif items:
            items[-1].append(line.strip())
    for number, item in enumerate(items, start=1):
        text = " ".join(item)
        if CITATION.search(text):
            rows.append((f"the item {number}", text))
    runbook = ROOT / "docs/runbooks/operations.md"
    if runbook.is_file():
        for number, paragraph in enumerate(the_paragraphs(runbook.read_text()), start=1):
            if CITATION.search(paragraph):
                rows.append((f"the runbook §{number}", paragraph))
    return rows


def the_paragraphs(text):
    """The paragraphs of a document: the blocks between the empty lines."""
    blocks = []
    current = []
    for line in text.splitlines():
        if line.strip():
            current.append(line.strip())
        elif current:
            blocks.append(" ".join(current))
            current = []
    if current:
        blocks.append(" ".join(current))
    return blocks


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

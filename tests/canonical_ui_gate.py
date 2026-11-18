#!/usr/bin/env python3
"""Canonical UI gate: current build, working-tree provenance, widgets and browser.

The complete verdict requires the compiled bundle, the widget gate, the managed
browser gate and the technical visual comparison. Local partial runs are always
labelled PARTIAL; --allow-partial only controls their process exit code.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'tools'))
from oip_build import run as build_run

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPS = ROOT / 'apps/flutter'
BUILD_COMMAND = [
    'flutter', 'build', 'web', '--release', '--web-renderer', 'canvaskit',
    '--no-web-resources-cdn', '--pwa-strategy=none',
]
REQUIRED_MARKERS = [
    'Alle berechtigten Infrastrukturen',
    'Einstellungen',
    'INFRASTRUCTURE COMMAND CENTER',
]
FORBIDDEN_MARKERS = [
    'OIP / 005 UI',
    'Deine Infrastruktur. Ein Bild.',
    'Erfasste Geräte',
    'Erreichbare Geräte',
    'Temperatur M-01',
    'Temperatur · M-01',
]


def sha256(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def git(*args, env=None):
    return subprocess.check_output(
        ['git', '-C', str(ROOT), *args], text=True,
        stderr=subprocess.DEVNULL, timeout=60, env=env).strip()


def working_tree_hash():
    """Hash the actual worktree through a temporary index, never the real one."""
    with tempfile.TemporaryDirectory(prefix='oip-canonical-ui-index-') as directory:
        env = dict(os.environ, GIT_INDEX_FILE=str(pathlib.Path(directory) / 'index'))
        git('read-tree', 'HEAD', env=env)
        git('add', '-A', env=env)
        return git('write-tree', env=env)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--web-dir', default=str(APPS / 'build/web'))
    ap.add_argument('--base-url', default=None)
    ap.add_argument('--login-code', default=None)
    ap.add_argument('--ipc-socket', default=None,
                    help='mint a fresh one-use code right before the browser gate')
    ap.add_argument('--ipc-credential', default=None)
    ap.add_argument('--server-bin', default=str(ROOT / 'target/debug/oip-server'))
    ap.add_argument('--out', default=str(ROOT / 'target/oip-canonical-ui-gate'))
    ap.add_argument('--skip-build', action='store_true')
    ap.add_argument('--skip-browser', action='store_true')
    ap.add_argument('--skip-widget', action='store_true')
    ap.add_argument('--allow-partial', action='store_true')
    a = ap.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    receipt = {
        'schema': 'oip-canonical-ui-gate-v2',
        'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'source_revision': git('rev-parse', 'HEAD'),
        'source_tree': working_tree_hash(),
        'source_worktree': str(ROOT),
        'source_dirty': bool(git('status', '--porcelain')),
        'baseline_document': 'docs/design/OIP_CANONICAL_UI_BASELINE.md',
        'handoff_manifest': 'docs/design/OIP_UI_2027_HANDOFF_MANIFEST.json',
        'operator_visual_approval': 'VISUAL_PENDING_OPERATOR_ACCEPTANCE',
        'build_skipped': a.skip_build,
        'checks': [],
        'verdict': 'PASS',
    }

    def record(name, ok, detail=None):
        receipt['checks'].append({'check': name, 'ok': bool(ok), 'detail': detail})
        if not ok:
            receipt['verdict'] = 'FAIL'

    # 1. Build the exact current source. An old build is never accepted silently.
    if not a.skip_build:
        # The build runs in its own process group: a build that is stopped
        # must not leave an orphan behind that holds the lock of the next
        # build (`tools/oip_build.py`).
        result = build_run(BUILD_COMMAND, cwd=str(APPS), timeout=1800)
        (out / 'build.log').write_text(result['the_output'] + result['the_error'])
        receipt['build_command'] = BUILD_COMMAND
        record('current source web release build', result['the_code'] == 0,
               ' '.join(BUILD_COMMAND))

    # 2. Bundle provenance and legacy markers.
    web = pathlib.Path(a.web_dir)
    bundle = web / 'main.dart.js'
    if bundle.is_file():
        digest = sha256(bundle)
        receipt['bundle_sha256'] = digest
        receipt['bundle_bytes'] = bundle.stat().st_size
        receipt['bundle_path'] = str(bundle)
        text = bundle.read_bytes().decode('utf-8', 'ignore')
        for marker in REQUIRED_MARKERS:
            record(f'bundle carries approved marker {marker}', marker in text)
        for marker in FORBIDDEN_MARKERS:
            record(f'bundle has no legacy marker {marker}', marker not in text)
    else:
        record('web release exists', False, str(bundle))

    # 3. The served bundle is byte-identical to the local build.
    if a.base_url:
        try:
            import urllib.request
            served = urllib.request.urlopen(a.base_url.rstrip('/') + '/main.dart.js', timeout=60).read()
            receipt['served_bundle_sha256'] = hashlib.sha256(served).hexdigest()
            record('served bundle equals the local build',
                   receipt.get('served_bundle_sha256') == receipt.get('bundle_sha256'))
        except Exception as error:
            record('served bundle readable', False, str(error))

    # 4. Rendered widget contracts.
    if not a.skip_widget:
        result = subprocess.run(
            ['flutter', 'test'], cwd=str(APPS), capture_output=True,
            text=True, timeout=1800)
        widget_log = result.stdout + result.stderr
        (out / 'widget-gate.log').write_text(widget_log)
        # The runner writes "+356 ~1: All tests passed!" — the count of the
        # skipped tests stands between the count and the colon, so the pattern
        # must not require the colon directly after the number.
        passed = re.search(r'\+(\d+)[^:\n]*: All tests passed!', widget_log)
        failed = re.search(r'\+(\d+)[^:\n]*: Some tests failed', widget_log)
        receipt['flutter_tests_passed'] = int(passed.group(1)) if passed else None
        receipt['flutter_tests_failed'] = 0 if passed else (int(failed.group(1)) if failed else None)
        skipped = re.search(r'\+(\d+)\s+~(\d+): All tests passed!', widget_log)
        receipt['flutter_tests_skipped'] = int(skipped.group(2)) if skipped else None
        record('full Flutter widget/unit and design gate', result.returncode == 0,
               'flutter test (includes canonical_ui_gate_test.dart and all preserved expert workflows)')

    # 5. Managed browser contracts and actual 1440/1920 captures.
    browser_executed = bool(a.base_url and not a.skip_browser)
    receipt['browser_gate_executed'] = browser_executed
    if browser_executed:
        env = dict(os.environ)
        module = env.get('PLAYWRIGHT_MODULE') or str(APPS / 'test/node_modules/playwright/index.mjs')
        if not pathlib.Path(module).is_absolute():
            module = str(ROOT / module)
        env['PLAYWRIGHT_MODULE'] = module
        code = a.login_code
        if not code and a.ipc_socket and a.ipc_credential:
            minted = subprocess.run([a.server_bin, '--browser-login',
                                     '--ipc-socket', a.ipc_socket,
                                     '--ipc-credential', a.ipc_credential],
                                    capture_output=True, text=True, timeout=60)
            if minted.returncode != 0:
                record('one-use browser login code minted', False, minted.stderr[-500:])
            else:
                code = json.loads(minted.stdout)['login_code']
                receipt['browser_login_code_minted'] = True
        # Keep browser evidence in its own initially empty directory. The gate
        # already writes build/widget receipts to `out`; passing `out` directly
        # makes the browser harness reject every otherwise valid full run.
        browser_out = out / 'browser'
        browser_out.mkdir(exist_ok=True)
        command = ['node', str(APPS / 'test/browser_canonical_ui_gate.mjs'),
                   a.base_url, str(browser_out.resolve())]
        if code:
            env['OIP_BROWSER_LOGIN_CODE'] = code
        result = subprocess.run(command, cwd=str(APPS), env=env,
                                capture_output=True, text=True, timeout=1800)
        (out / 'browser-gate.log').write_text(result.stdout + result.stderr)
        browser_receipt = browser_out / 'browser-canonical-ui-gate.json'
        receipt['browser_gate'] = json.loads(browser_receipt.read_text()) \
            if browser_receipt.is_file() else None
        record('browser gate', result.returncode == 0, 'browser_canonical_ui_gate.mjs')

        visual = subprocess.run(
            [sys.executable, str(ROOT / 'tests/canonical_ui_visual.py'),
             '--actual-root', str(browser_out.resolve()), '--out', str(out / 'visual-comparison.json')],
            cwd=str(ROOT), capture_output=True, text=True, timeout=120)
        (out / 'visual-gate.log').write_text(visual.stdout + visual.stderr)
        receipt['visual_comparison'] = json.loads((out / 'visual-comparison.json').read_text()) \
            if (out / 'visual-comparison.json').is_file() else None
        record('technical visual shell comparisons', visual.returncode == 0,
               '1440x900 and 1920x1080 stable-shell crops')

    complete = not a.skip_build and not a.skip_widget and browser_executed
    receipt['complete'] = complete
    if receipt['verdict'] != 'FAIL':
        receipt['verdict'] = 'PASS' if complete else 'PARTIAL'
    receipt['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    (out / 'canonical-ui-gate.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({
        'verdict': receipt['verdict'],
        'complete': complete,
        'source_revision': receipt['source_revision'],
        'source_tree': receipt['source_tree'],
        'bundle_sha256': receipt.get('bundle_sha256'),
        'served_bundle_sha256': receipt.get('served_bundle_sha256'),
        'checks': len(receipt['checks']),
        'failed': [c['check'] for c in receipt['checks'] if not c['ok']],
    }, indent=2))
    if receipt['verdict'] == 'PASS' or (a.allow_partial and receipt['verdict'] == 'PARTIAL'):
        return 0
    return 1


if __name__ == '__main__':
    sys.exit(main())

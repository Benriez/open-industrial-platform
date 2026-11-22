import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import canonical_regression as regression


class CanonicalRegressionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.evidence = pathlib.Path(directory.name)
        self.case = {
            'name': 'fixture', 'script': 'fixture.py', 'timeout': 10,
            'reports': ['report.json'],
        }

    def run_case(self, contents=None):
        def harness(command, *, env, **_):
            if contents is not None:
                (pathlib.Path(env['OIP_EVIDENCE_DIR']) / 'report.json').write_text(contents)
            return subprocess.CompletedProcess(command, 0, '', '')

        with patch.object(regression.subprocess, 'run', side_effect=harness):
            return regression.run_case(self.case, self.evidence)

    def test_requires_fresh_passing_evidence(self):
        self.assertEqual(self.run_case()['status'], 'FAIL')
        report = self.evidence / 'fixture' / 'report.json'
        report.write_text('{"status": "PASS"}')
        os.utime(report, (1, 1))
        self.assertEqual(self.run_case()['status'], 'FAIL')
        for contents in ('broken JSON', '[]', '{"results": []}', '{"verdict": "PARTIAL"}'):
            with self.subTest(contents=contents):
                self.assertEqual(self.run_case(contents)['status'], 'FAIL')
        self.assertEqual(self.run_case('{"status": "PASS"}')['status'], 'PASS')

    def test_unknown_case_is_rejected(self):
        result = subprocess.run([
            sys.executable, regression.__file__, '--only', 'typo',
            '--evidence', str(self.evidence),
        ], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.evidence / 'canonical-regression.json').exists())

    def test_blocked_case_yields_a_partial_run(self):
        blocked = {'name': self.case['name'], 'status': 'BLOCKED'}
        with patch.object(regression, 'CASES', [self.case]), \
                patch.object(regression, 'run_case', return_value=blocked), \
                patch.object(sys, 'argv', [regression.__file__, '--evidence', str(self.evidence)]):
            self.assertEqual(regression.main(), 2)
        summary = json.loads((self.evidence / 'canonical-regression.json').read_text())
        self.assertEqual(summary['status'], 'PARTIAL')


if __name__ == '__main__':
    unittest.main()

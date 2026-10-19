#!/usr/bin/env python3
"""Exercise the Pages validation command against isolated publication states."""
import copy
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]


class SiteReleaseGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='chronoframe-site-gate-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        (cls.root / 'script').mkdir()
        shutil.copy(REPOSITORY / 'script/check_site.py', cls.root / 'script')
        shutil.copytree(REPOSITORY / 'site', cls.root / 'site')
        cls.manifest = cls.root / 'site/assets/product-proof.json'
        cls.original = json.loads(cls.manifest.read_text())
        workflow = (REPOSITORY / '.github/workflows/pages.yml').read_text()
        step = re.search(r'^      - name: Verify site artifact\n        run: (.+)$',
                         workflow, re.MULTILINE)
        if step is None:
            raise AssertionError('Cannot find the Pages artifact validation step')
        cls.deployment_command = shlex.split(step.group(1))

    def setUp(self):
        self.proof = copy.deepcopy(self.original)
        self.proof['owner_publication_approval'] = {
            'recorded_on': '2026-10-18',
            'website_before_public_app': True,
            'temporary_app_store_link_mismatch_accepted': True,
            'reason': 'Isolated test approval',
            'evidence': 'Unit test fixture; not a production approval',
        }

    def run_check(self, command):
        self.manifest.write_text(json.dumps(self.proof))
        return subprocess.run(command, cwd=self.root, capture_output=True, text=True)

    def test_draft_check_allows_held_proof(self):
        self.proof['publication_status'] = 'held_for_public_release_verification'
        result = self.run_check(['python3', 'script/check_site.py'])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deployment_command_rejects_held_proof(self):
        self.proof['publication_status'] = 'held_for_public_release_verification'
        result = self.run_check(self.deployment_command)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('RELEASE HELD', result.stderr)

    def test_deployment_command_accepts_recorded_owner_approval(self):
        self.proof['publication_status'] = 'owner_approved_prelaunch'
        result = self.run_check(self.deployment_command)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_deployment_command_rejects_missing_owner_approval(self):
        self.proof['publication_status'] = 'owner_approved_prelaunch'
        self.proof.pop('owner_publication_approval', None)
        result = self.run_check(self.deployment_command)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('requires recorded owner approval', result.stderr)


if __name__ == '__main__':
    unittest.main()

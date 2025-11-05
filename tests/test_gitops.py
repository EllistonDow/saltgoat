import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from modules.lib import gitops


class GitOpsDriftTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        self._orig_root = gitops.REPO_ROOT
        gitops.REPO_ROOT = self.repo
        self._orig_env = os.environ.get("SALTGOAT_UNIT_TEST")
        os.environ["SALTGOAT_UNIT_TEST"] = "1"
        self._run_git(["init"])
        self._run_git(["config", "user.name", "SaltGoat"])
        self._run_git(["config", "user.email", "saltgoat@example.com"])
        (self.repo / "README.md").write_text("# Demo\n", encoding="utf-8")
        self._run_git(["add", "README.md"])
        self._run_git(["commit", "-m", "init"])

    def tearDown(self) -> None:
        gitops.REPO_ROOT = self._orig_root
        if self._orig_env is None:
            os.environ.pop("SALTGOAT_UNIT_TEST", None)
        else:
            os.environ["SALTGOAT_UNIT_TEST"] = self._orig_env
        self.tmp.cleanup()

    def _run_git(self, args: list[str]) -> None:
        subprocess.run(["git"] + args, cwd=self.repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_clean_repo_has_no_drift(self) -> None:
        report = gitops.detect_drift()
        self.assertFalse(report.has_drift)
        self.assertEqual(report.working_changes, [])
        self.assertEqual(report.untracked, [])

    def test_reports_untracked_and_modified_files(self) -> None:
        (self.repo / "README.md").write_text("# Demo updated\n", encoding="utf-8")
        (self.repo / "new.txt").write_text("hello\n", encoding="utf-8")
        report = gitops.detect_drift()
        self.assertTrue(report.has_drift)
        self.assertIn("README.md", report.working_changes[0])
        self.assertIn("new.txt", report.untracked)


if __name__ == "__main__":
    unittest.main()

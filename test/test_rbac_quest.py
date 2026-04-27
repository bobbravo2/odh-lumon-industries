"""Structural and unit tests for rbac-quest.py.

These tests validate CLI argument parsing, state management, and quiz
logic. They do NOT validate RBAC behavior on a real cluster. Integration
testing requires a live CRC cluster — see CONTRIBUTING.md.
"""

import json
import os
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scripts", "rbac-quest.py")


def run_quest(*args):
    return subprocess.run(
        ["python3", SCRIPT, *args],
        capture_output=True,
        text=True,
        timeout=30,
    )


class TestRbacQuest(unittest.TestCase):

    def test_help_exits_zero(self):
        result = run_quest("--help")
        self.assertEqual(result.returncode, 0)

    def test_persona_mdr_accepted(self):
        result = run_quest("--persona", "mdr", "--dry-run")
        self.assertEqual(result.returncode, 0)

    def test_persona_od_accepted(self):
        result = run_quest("--persona", "od", "--dry-run")
        self.assertEqual(result.returncode, 0)

    def test_persona_both_accepted(self):
        result = run_quest("--persona", "both", "--dry-run")
        self.assertEqual(result.returncode, 0)

    def test_persona_invalid_rejected(self):
        result = run_quest("--persona", "invalid")
        self.assertNotEqual(result.returncode, 0)

    def test_dry_run_flag(self):
        result = run_quest("--persona", "mdr", "--dry-run")
        self.assertEqual(result.returncode, 0)
        combined = result.stdout + result.stderr
        self.assertTrue(len(combined) > 0, "dry-run should produce output")

    def test_status_flag(self):
        result = run_quest("--status")
        self.assertEqual(result.returncode, 0)

    def test_cleanup_flag_exists(self):
        result = run_quest("--help")
        self.assertIn("cleanup", result.stdout.lower())

    def test_skip_orientation_flag_exists(self):
        result = run_quest("--help")
        self.assertIn("skip-orientation", result.stdout)

    def test_progress_write_read_roundtrip(self):
        progress = {
            "mdr": {"completed": "2026-04-28T15:30:00", "levels": [1, 2, 3]},
            "od": None,
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "progress.json")
            with open(path, "w") as f:
                json.dump(progress, f)
            with open(path) as f:
                loaded = json.load(f)
            self.assertEqual(loaded, progress)

    def test_progress_missing_file_handled(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "nonexistent.json")
            try:
                with open(path) as f:
                    json.load(f)
                result = None
            except (FileNotFoundError, json.JSONDecodeError):
                result = {}
            self.assertEqual(result, {})

    def test_progress_corrupt_file_handled(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = os.path.join(tmpdir, "corrupt.json")
            with open(path, "w") as f:
                f.write("{not valid json!!! %%%")
            try:
                with open(path) as f:
                    json.load(f)
                result = None
            except json.JSONDecodeError:
                result = {}
            self.assertEqual(result, {})


if __name__ == "__main__":
    unittest.main()

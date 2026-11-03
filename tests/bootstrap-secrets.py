"""Run with Python 3, sops, age-keygen, ssh-to-age, and ssh-keygen on PATH."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/bootstrap-secrets.sh"


class BootstrapSecretsTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.root / "host")],
            check=True,
        )
        # Only the SSH transport is mocked; encryption and editing use real SOPS.
        tools = self.root / "bin"
        tools.mkdir()
        ssh = tools / "ssh"
        ssh.write_text('#!/bin/sh\ncat "$BOOTSTRAP_TEST_HOST_KEY"\n')
        ssh.chmod(0o700)
        self.env = dict(
            os.environ,
            PATH=str(tools) + os.pathsep + os.environ["PATH"],
            BOOTSTRAP_TEST_HOST_KEY=str(self.root / "host.pub"),
            SOPS_AGE_KEY_FILE=str(self.root / "local-age-key"),
            SOPS_EDITOR="true",
        )
        self.secrets = self.root / "secrets/test.json"

    def bootstrap(self):
        return subprocess.run(
            ["bash", str(SCRIPT), "test", "root@example.test"],
            cwd=self.root, env=self.env, capture_output=True, text=True,
        )

    def decrypt(self):
        return json.loads(subprocess.check_output(
            ["sops", "--decrypt", str(self.secrets)], env=self.env, text=True,
        ))

    def test_empty_store_and_unchanged_editor_succeed(self):
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.decrypt(), {})
        recipients = json.loads(self.secrets.read_text())["sops"]["age"]
        self.assertEqual(len(recipients), 2)
        original = self.secrets.read_bytes()
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.secrets.read_bytes(), original)

    def test_add_secret_and_preserve_existing_recipients(self):
        self.assertEqual(self.bootstrap().returncode, 0)
        original = json.loads(self.secrets.read_text())["sops"]["age"]
        editor = self.root / "editor"
        editor.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "with open(sys.argv[1], 'w') as f:\n"
            "    json.dump({'api-key': 'test-only-credential'}, f)\n"
        )
        editor.chmod(0o700)
        self.env["SOPS_EDITOR"] = str(editor)
        result = self.bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.decrypt(), {"api-key": "test-only-credential"})
        self.assertNotIn("test-only-credential", self.secrets.read_text())
        self.assertEqual(json.loads(self.secrets.read_text())["sops"]["age"], original)
        self.env["SOPS_EDITOR"] = "false"
        self.assertNotEqual(self.bootstrap().returncode, 0)
        self.assertEqual(self.decrypt(), {"api-key": "test-only-credential"})


if __name__ == "__main__":
    unittest.main()

"""Run with python3 tests/deploy.py; all Nix/SSH operations are mocked."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/deploy.sh"
SYSTEM = "/nix/store/" + "a" * 32 + "-nixos-system-testvps"


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        tools = self.root / "bin"
        tools.mkdir()
        executable = tools / "tool"
        executable.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["DEPLOY_TEST_LOG"], "a") as f:
    f.write(json.dumps([tool, *args]) + "\\n")
operation = "auth" if tool == "ssh" and args[-1] == "true" else (
    "activate" if tool == "ssh" else "build" if "build" in args else "copy")
if os.environ.get("DEPLOY_TEST_FAIL") == operation:
    sys.exit(7)
if operation == "build":
    if "--out-link" in args:
        pathlib.Path(args[args.index("--out-link") + 1]).symlink_to(os.environ["DEPLOY_TEST_SYSTEM"])
    print(os.environ["DEPLOY_TEST_SYSTEM"])
''')
        executable.chmod(0o700)
        for name in ["nix", "ssh"]:
            (tools / name).symlink_to(executable)
        self.log = self.root / "calls.jsonl"
        self.env = dict(
            os.environ,
            PATH=str(tools) + os.pathsep + os.environ["PATH"],
            DEPLOY_TEST_LOG=str(self.log),
            DEPLOY_TEST_SYSTEM=SYSTEM,
        )

    def deploy(self, *args):
        result = subprocess.run(
            ["bash", str(SCRIPT), *args], env=self.env,
            cwd=self.root, capture_output=True, text=True,
        )
        self.calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result

    def test_local_default_and_cleanup(self):
        result = self.deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in self.calls], ["ssh", "nix", "nix", "ssh"])
        build, copy, activate = self.calls[1:]
        self.assertIn("build", build)
        self.assertNotIn("--store", build)
        link = Path(build[build.index("--out-link") + 1])
        self.assertFalse(link.parent.exists())
        self.assertIn("--no-check-sigs", copy)
        self.assertIn("--use-substitutes", copy)
        self.assertNotIn("--from", copy)
        self.assertEqual(copy[copy.index("--to") + 1], "ssh-ng://admin@vps")
        self.assertIn("sudo /run/current-system/sw/bin/nixos-rebuild", activate[-1])
        self.assertIn("--store-path '" + SYSTEM + "'", activate[-1])

    def test_remote_builder_streams_directly_to_target(self):
        self.env["NIX_SSHOPTS"] = "-p 2222"
        result = self.deploy("admin@example.test", "vps", "ssh-ng://builder@zenbox")
        self.assertEqual(result.returncode, 0, result.stderr)
        build, copy = self.calls[1:3]
        self.assertEqual(build[build.index("--store") + 1], "ssh-ng://builder@zenbox")
        self.assertIn("--eval-store", build)
        self.assertNotIn("--out-link", build)
        self.assertEqual(copy[copy.index("--from") + 1], "ssh-ng://builder@zenbox")
        self.assertEqual(copy[copy.index("--to") + 1], "ssh-ng://admin@example.test")
        self.assertEqual(self.calls[0][1:3], ["-p", "2222"])

    def test_just_recipe_defaults_to_local_building(self):
        result = subprocess.run(
            ["just", "--justfile", str(SCRIPT.parents[1] / "justfile"),
             "deploy", "admin@example.test", "vps"],
            env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        self.assertIn("build", calls[1])
        self.assertNotIn("--store", calls[1])

    def test_root_activation_has_no_sudo(self):
        result = self.deploy("root@example.test", "vps", "zenbox")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("sudo", self.calls[-1][-1])
        self.assertEqual(self.calls[1][self.calls[1].index("--store") + 1], "ssh-ng://zenbox")

    def test_on_target_bootstrap_skips_copy(self):
        result = self.deploy("admin@example.test", "vps", "target")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls), 3)
        self.assertEqual(self.calls[1][self.calls[1].index("--store") + 1], "ssh-ng://admin@example.test")
        self.assertFalse(any("copy" in call for call in self.calls))

    def test_failures_stop_before_activation(self):
        for failure in ["auth", "build", "copy"]:
            with self.subTest(failure=failure):
                self.log.unlink(missing_ok=True)
                self.env["DEPLOY_TEST_FAIL"] = failure
                self.assertNotEqual(self.deploy().returncode, 0)
                self.assertFalse(any("switch" in call[-1] for call in self.calls))

    def test_activation_failure_is_reported(self):
        self.env["DEPLOY_TEST_FAIL"] = "activate"
        self.assertEqual(self.deploy().returncode, 7)

    def test_invalid_configuration_fails_before_ssh(self):
        self.assertNotEqual(self.deploy("admin@vps", "bad;name").returncode, 0)
        self.assertEqual(self.calls, [])

    def test_invalid_system_path_is_never_activated(self):
        self.env["DEPLOY_TEST_SYSTEM"] = "/nix/store/invalid'; touch unexpected"
        self.assertNotEqual(self.deploy().returncode, 0)
        self.assertEqual(len(self.calls), 2)


if __name__ == "__main__":
    unittest.main()

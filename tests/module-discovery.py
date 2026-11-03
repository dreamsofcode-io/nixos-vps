"""Run with python3 tests/module-discovery.py; requires the local Nix daemon."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ModuleDiscoveryTests(unittest.TestCase):
    def evaluate(self, expression, **variables):
        return json.loads(subprocess.check_output(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            cwd=ROOT, env=dict(os.environ, **variables), text=True,
        ))

    def test_discovery_filters_and_orders_entries(self):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch).resolve()
            for name in ["z.nix", "a.nix", "default.nix", "README.md", "draft.nix.bak"]:
                (directory / name).write_text("{}")
            (directory / "nested").mkdir()
            (directory / "nested/default.nix").write_text("{}")
            (directory / "ignored").mkdir()
            (directory / "ignored/module.nix").write_text("{}")
            (directory / "link.nix").symlink_to(directory / "a.nix")
            result = self.evaluate('''
              let discover = import ./lib/import-directory.nix;
              in map (path: builtins.baseNameOf (toString path))
                (discover (builtins.toPath (builtins.getEnv "DISCOVERY_DIRECTORY")))
            ''', DISCOVERY_DIRECTORY=str(directory))
            self.assertEqual(result, ["a.nix", "nested", "z.nix"])

    def test_new_modules_load_without_editing_imports(self):
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch).resolve()
            # Copy only Nix source, excluding this checkout's server credentials.
            for path in ROOT.rglob("*.nix"):
                relative = path.relative_to(ROOT)
                if ".git" in relative.parts or relative == Path("settings.nix"):
                    continue
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
            shutil.copy2(ROOT / "flake.lock", root / "flake.lock")
            (root / "settings.nix").write_text('''{
              hostname = "vps";
              sshKeys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA test"];
              hashedPassword = "$6$test$test";
              access = "public";
              tailscale.enable = false;
              cloudflared = { enable = false; tunnelId = ""; };
            }''')
            (root / "modules/discovery-test.nix").write_text(
                '{ ... }: { networking.domain = "auto-import.test"; }'
            )
            (root / "services/discovery-test.nix").write_text('''{pkgs, ...}: {
              systemd.services.discovery-test = {
                wantedBy = ["multi-user.target"];
                serviceConfig.ExecStart = "${pkgs.coreutils}/bin/true";
              };
            }''')
            (root / "services/nested-test").mkdir()
            (root / "services/nested-test/default.nix").write_text(
                '{ ... }: { environment.variables.DISCOVERY_TEST = "loaded"; }'
            )
            (root / "services/ignored.nix.bak").write_text('throw "Must not load"')
            result = self.evaluate('''
              let
                flake = builtins.getFlake ("path:" + builtins.getEnv "DISCOVERY_FLAKE");
                config = flake.nixosConfigurations.vps.config;
              in {
                builds = builtins.isString config.system.build.toplevel.drvPath;
                domain = config.networking.domain;
                service = config.systemd.services.discovery-test.wantedBy;
                nested = config.environment.variables.DISCOVERY_TEST;
                baseModule = config.custom.networking.access;
                secretPath = flake.inputs.nixpkgs.lib.hasSuffix
                  "/secrets/vps.json" (toString config.sops.defaultSopsFile)
                  && !(flake.inputs.nixpkgs.lib.hasSuffix
                    "/modules/secrets/vps.json" (toString config.sops.defaultSopsFile));
              }
            ''', DISCOVERY_FLAKE=str(root))
            self.assertEqual(result, {
                "builds": True, "domain": "auto-import.test",
                "service": ["multi-user.target"], "nested": "loaded",
                "baseModule": "public", "secretPath": True,
            })


if __name__ == "__main__":
    unittest.main()

# Run without building Linux packages:
# nix eval --impure --json --expr 'import ./tests/admin-access.nix { flake = builtins.getFlake ("path:" + toString ./.); }'
{ flake }:
let
  lib = flake.inputs.nixpkgs.lib;
  validHash = "$6$test$test";
  validKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA test";
  evaluates = hash: keys:
    (builtins.tryEval (
      (flake.nixosConfigurations.vps.extendModules {
        modules = [{
          services.tailscale.enable = lib.mkForce false;
          services.cloudflared.enable = lib.mkForce false;
          custom.networking.access = lib.mkForce "public";
          users.users.admin.hashedPassword = lib.mkForce hash;
          users.users.admin.openssh.authorizedKeys.keys = lib.mkForce keys;
        }];
      }).config.system.build.toplevel.drvPath
    )).success;
  results = {
    configured = evaluates validHash [validKey];
    missingPassword = !(evaluates null [validKey]);
    emptyPassword = !(evaluates "" [validKey]);
    blankPassword = !(evaluates "   " [validKey]);
    lockedPassword = !(evaluates "!" [validKey]);
    missingKeys = !(evaluates validHash []);
    emptyKey = !(evaluates validHash [""]);
    blankKey = !(evaluates validHash ["   "]);
    bothMissing = !(evaluates "" []);
  };
in
assert lib.assertMsg (lib.all (result: result) (builtins.attrValues results))
  "Admin access assertion regression tests failed";
results

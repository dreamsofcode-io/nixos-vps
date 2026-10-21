{
  description = "A NixOS VPS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, sops-nix, ... }:
  let
    mkVps = hostname: extraModules: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sops-nix.nixosModules.sops
        { networking.hostName = hostname; }
        ./configuration.nix
      ] ++ extraModules;
    };
  in {
    nixosConfigurations = {
      vps = mkVps "vps" [];
      # Add another VPS with optional per-server settings:
      # vps2 = mkVps "vps2" [ { time.timeZone = "Europe/London"; } ];
    };
  };
}

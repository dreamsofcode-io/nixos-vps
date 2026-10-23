{
  description = "A NixOS VPS configuration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, sops-nix, ... }:
  let
    mkVps = settings: extraModules: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sops-nix.nixosModules.sops
        ({ lib, ... }: {
          networking.hostName = lib.mkDefault settings.hostname;
          users.users.admin = {
            openssh.authorizedKeys.keys = lib.mkDefault settings.sshKeys;
            hashedPassword = lib.mkDefault settings.hashedPassword;
          };
          custom.networking.access = lib.mkDefault settings.access;
          services.tailscale.enable = lib.mkDefault settings.tailscale.enable;
          services.cloudflared = {
            enable = lib.mkDefault settings.cloudflared.enable;
            tunnelId = lib.mkDefault settings.cloudflared.tunnelId;
          };
        })
        ./configuration.nix
      ] ++ extraModules;
    };
  in {
    nixosConfigurations = {
      vps = mkVps (import ./settings.nix) [];
      # Copy settings.nix to hosts/vps2.nix for another server:
      # vps2 = mkVps (import ./hosts/vps2.nix) [ { time.timeZone = "Europe/London"; } ];
    };
  };
}

{ config, pkgs, ... }:
{
  # Created by `just bootstrap`; each VPS has its own encrypted file.
  sops.defaultSopsFile = ../. + "/secrets/${config.networking.hostName}.json";
  sops.defaultSopsFormat = "json";

  environment.systemPackages = [pkgs.sops];
}

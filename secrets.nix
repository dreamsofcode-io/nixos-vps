{ pkgs, ... }:
{
  # Set defaultSopsFile when adding the first encrypted secrets file.
  # sops.defaultSopsFile = ./secrets/vps.json;
  sops.defaultSopsFormat = "json";

  environment.systemPackages = [pkgs.sops];
}

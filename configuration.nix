{ ... }:
let
  sshKeys = [
  ];
in {
  imports = [
    ./vps_configuration.nix
  ];

  users.users.admin = {
    isNormalUser = true;
    description = "Admin account for VPS";
    extraGroups = ["wheel"];
    hashedPassword = "";

    openssh.authorizedKeys.keys = sshKeys;
  };
}

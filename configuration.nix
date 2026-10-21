{ ... }:
let
  sshKeys = [
  ];
in {
  imports = [
    ./vps_configuration.nix
  ];

  services.openssh.settings = {
    PermitRootLogin = "no";
    AllowUsers = ["admin"];
    AuthenticationMethods = "publickey";
    PubkeyAuthentication = true;
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitEmptyPasswords = false;
    X11Forwarding = false;
  };

  users.users.admin = {
    isNormalUser = true;
    description = "Admin account for VPS";
    extraGroups = ["wheel"];
    hashedPassword = "";

    openssh.authorizedKeys.keys = sshKeys;
  };
}

{ ... }:
let
  sshKeys = [
  ];
in {
  imports = [
    ./vps_configuration.nix
    ./secrets.nix
    ./containers.nix
    ./services/tailscale.nix
    ./services/cloudflared.nix
  ];

  services.tailscale.enable = true;

  services.cloudflared = {
    enable = false;
    # Set your tunnel UUID before enabling.
    tunnelId = "";
  };

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

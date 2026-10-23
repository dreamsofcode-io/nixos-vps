{...}: {
  imports = [
    ./vps_configuration.nix
    ./secrets.nix
    ./containers.nix
    ./networking.nix
    ./services/tailscale.nix
    ./services/cloudflared.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];

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
  };
}

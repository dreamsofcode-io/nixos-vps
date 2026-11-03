{config, lib, ...}: {
  imports = [
    ./vps_configuration.nix
    ./secrets.nix
    ./containers.nix
    ./networking.nix
    ./services/tailscale.nix
    ./services/cloudflared.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  # Admin already manages the system through sudo. Trust it to import build outputs.
  # A trusted Nix user has root-equivalent privileges without a sudo password.
  nix.settings.trusted-users = ["admin"];

  assertions = [
    {
      assertion = let hash = config.users.users.admin.hashedPassword;
        in hash != null && builtins.match ".*[^[:space:]].*" hash != null
          && !(builtins.elem hash ["!" "!!" "*"]);
      message = "Set a non-empty admin password hash in settings.nix (hashedPassword) before deploying.";
    }
    {
      assertion = lib.any
        (key: builtins.match ".*[^[:space:]].*" key != null)
        config.users.users.admin.openssh.authorizedKeys.keys;
      message = "Set at least one non-empty admin SSH public key in settings.nix (sshKeys) before deploying.";
    }
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
  };
}

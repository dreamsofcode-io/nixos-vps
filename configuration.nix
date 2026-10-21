{...}: let
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

  # Enable Tailscale. Requires setting up an auth key and adding it to nix-sops
  services.tailscale.enable = false;

  # Enable Cloudflared. Please check documentation for how to configure.
  services.cloudflared = {
    enable = false;
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

  # Generate a hashed password using the below commmand
  # nix run 'nixpkgs#mkpasswd' -- --method=yescrypt
  users.users.admin = {
    isNormalUser = true;
    description = "Admin account for VPS";
    extraGroups = ["wheel"];
    hashedPassword = "";

    openssh.authorizedKeys.keys = sshKeys;
  };
}

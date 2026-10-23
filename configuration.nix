{lib, ...}: {
  imports = [
    ./vps_configuration.nix
    ./secrets.nix
    ./containers.nix
    ./networking.nix
    ./services/tailscale.nix
    ./services/cloudflared.nix
  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Switch to "tailscale" after confirming access over Tailscale.
  # Applies to host services; container forwarding is configured separately.
  custom.networking.access = lib.mkDefault "public";

  # Enable Tailscale. Requires setting up an auth key and adding it to nix-sops
  services.tailscale.enable = lib.mkDefault false;

  # Enable Cloudflared. Please check documentation for how to configure.
  services.cloudflared = {
    enable = lib.mkDefault false;
    tunnelId = lib.mkDefault "";
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
  };
}

{
  hostname = "vps";

  sshKeys = [
    # Add your public SSH key before deploying, for example:
    # "ssh-ed25519 AAAA... you@your-machine"
  ];

  # Generate with: nix run nixpkgs#mkpasswd -- --method=yescrypt
  hashedPassword = "";

  # Use "tailscale" only after verifying SSH access over Tailscale.
  # Restricts host services; container forwarding is configured separately.
  access = "public";

  # Requires a tailscale-auth-key entry in the encrypted secrets file.
  tailscale.enable = false;

  # Requires a cloudflared-<tunnelId>.json entry in the encrypted secrets file.
  cloudflared = {
    enable = false;
    tunnelId = "";
  };
}

{ config, lib, ... }:
{
  options.custom.networking.access = lib.mkOption {
    type = lib.types.enum ["public" "tailscale"];
    default = "public";
    description = ''
      Public preserves normal service firewall rules. Tailscale restricts host
      services to the tailnet, allowing all host ports on the Tailscale interface.
      This policy does not restrict forwarded container traffic or custom firewall rules.
    '';
  };

  config = lib.mkIf (config.custom.networking.access == "tailscale") {
    assertions = [
      {
        assertion = config.services.tailscale.enable;
        message = "custom.networking.access = tailscale requires services.tailscale.enable = true.";
      }
    ];

    services.openssh.openFirewall = lib.mkForce false;

    networking.firewall = {
      enable = lib.mkForce true;
      # Override ports opened by other services on public interfaces.
      allowedTCPPorts = lib.mkForce [];
      allowedTCPPortRanges = lib.mkForce [];
      allowedUDPPorts = lib.mkForce [config.services.tailscale.port];
      allowedUDPPortRanges = lib.mkForce [];
      interfaces = lib.mkForce {};
      trustedInterfaces = lib.mkForce ["lo" config.services.tailscale.interfaceName];
      allowPing = lib.mkForce false;
    };
  };
}

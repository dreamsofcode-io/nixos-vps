{ config, lib, ... }:
let
  cfg = config.services.cloudflared;
  secretName = "cloudflared-${cfg.tunnelId}.json";
in {
  options.services.cloudflared.tunnelId = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "UUID of the Cloudflare Tunnel to run on this VPS.";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.tunnelId != "";
        message = "Set services.cloudflared.tunnelId before enabling Cloudflare Tunnel.";
      }
    ];

    # Store the tunnel credentials JSON as a string under this SOPS secret name.
    sops.secrets.${secretName} = {
      restartUnits = ["cloudflared-tunnel-${cfg.tunnelId}.service"];
    };

    services.cloudflared.tunnels.${cfg.tunnelId} = {
      credentialsFile = config.sops.secrets.${secretName}.path;
      default = lib.mkDefault "http_status:404";
      # Add routes with services.cloudflared.tunnels.<tunnelId>.ingress.
    };
  };
}

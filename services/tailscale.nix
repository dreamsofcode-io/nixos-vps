{ config, lib, ... }:
{
  config = lib.mkIf config.services.tailscale.enable {
    # Requires an encrypted tailscale-auth-key entry in sops.defaultSopsFile.
    sops.secrets.tailscale-auth-key = {
      restartUnits = ["tailscaled-autoconnect.service"];
    };

    services.tailscale = {
      openFirewall = true;
      authKeyFile = config.sops.secrets.tailscale-auth-key.path;
      extraUpFlags = ["--hostname=${config.networking.hostName}"];
      extraSetFlags = ["--hostname=${config.networking.hostName}"];
    };
  };
}

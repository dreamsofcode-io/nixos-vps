# NixOS VPS

A starting configuration for a NixOS VPS, with optional Tailscale and Cloudflare Tunnel integration.

## Table of contents

1. [Setup](#setup)
2. [Deploying a service](#deploying-a-service)
3. [Managing secrets](#managing-secrets)
4. [Enabling Tailscale](#enabling-tailscale)
5. [Cloudflare Tunnel](#cloudflare-tunnel)
6. [Local building on macOS](#local-building-on-macos)
7. [Building on a separate machine](#building-on-a-separate-machine)
8. [Trusted builds](#trusted-builds)

## Setup

### Requirements

On your local machine, you need:

- **Nix**, with `nix-command` and `flakes` enabled. Nix can be installed on any
  standard Linux distribution; your local machine does not need to run NixOS.
  On **macOS**, follow the
  [Lix installation instructions](https://lix.systems/install/). Lix provides
  the `nix` command used throughout this guide.
- **just**, to run the bootstrap and deployment recipes. With Nix installed,
  you can start a shell containing it by running `nix shell nixpkgs#just`.
  Run the guide's `just` commands from that shell.
- **Git**, **Bash**, and an **SSH client**, plus SSH access to your VPS.
- A terminal editor available through `EDITOR` or `SOPS_EDITOR` for managing
  secrets, for example `export EDITOR=nano`.

Check that Nix and just are available:

```sh
nix --version
just --version
```

The bootstrap recipe obtains SOPS and the age tools through Nix; you do not
need to install them separately. Deployment builds through your local Nix
installation by default. This flake targets `x86_64-linux`: native x86_64 Linux
can build directly; macOS or ARM Linux needs a suitable Linux VM, emulation,
or a configured Nix builder. To build on a separate Linux machine instead,
pass its SSH address as the third deployment argument, such as
`just deploy admin@vps vps zenbox`. See [Building on a separate machine](#building-on-a-separate-machine).

### 1. Obtain a NixOS instance

You need a VPS running NixOS. For the Hostinger VPS used in the video, visit
[hostinger.com/dreamsofcode](https://hostinger.com/dreamsofcode) and select NixOS
as the operating system when provisioning your server.

Use coupon code `DREAMSOFCODE` at checkout for 10% off.

Once the server is ready, note its public IP address and confirm that you can
connect using the SSH credentials configured during provisioning.

The included `vps_configuration.nix` targets the Hostinger NixOS template on
an x86_64 VPS. If you use another provider, adapt the boot, storage, and network
settings to match your instance before deploying this configuration.

### 2. Prepare your configuration

Clone the repository on your local machine:

```sh
git clone https://github.com/dreamsofcode-io/nixos-vps.git
cd nixos-vps
```

Run the remaining commands from this directory unless noted otherwise.

Edit `settings.nix` before deploying. This is the main place to configure your server:

- Add your public SSH key to `sshKeys`. For example, copy the contents of
  `~/.ssh/id_ed25519.pub` into a quoted entry in that list. Use your public
  key (`.pub`), never your private key. The list starts empty; add your key
  before deploying so you can log in as `admin`.
- Generate an admin password hash with
  `nix run nixpkgs#mkpasswd -- --method=yescrypt` and put the result in
  `hashedPassword`. Do not leave it empty. You will use this
  password for sudo; SSH login uses your key.
- Set `hostname`. The examples below use `"vps"`.
- Keep `access = "public"` until you have confirmed that
  Tailscale is connected and you can SSH through it.

The build fails unless the admin account has both a non-empty password hash and
at least one non-empty SSH public key. Whitespace-only values and the locked
password markers `!`, `!!`, and `*` do not satisfy these requirements.

### 3. Bootstrap secrets

Bootstrap an encrypted secrets file for every VPS before its first deployment,
even if you are not enabling Tailscale or Cloudflare Tunnel yet:

```sh
just bootstrap vps root@x.x.x.x
```

Replace `x.x.x.x` with your VPS's public IP address. Use an account that already
exists on the server; `root` is shown for an initial deployment. If `admin`
already exists, use `admin@x.x.x.x` instead. Verify the SSH host fingerprint
when connecting for the first time.

The first argument is `hostname` from `settings.nix`. Bootstrap uses it to
name `secrets/vps.json`; it does not evaluate the NixOS configuration.

The command creates or reuses a local age key at
`${XDG_CONFIG_HOME:-~/.config}/sops/age/keys.txt` (or `SOPS_AGE_KEY_FILE`, if set),
reads the VPS's public SSH host key, and opens SOPS in your editor. New secrets
files are encrypted for both your local age key and the VPS host key. Keep a
backup of your local private age key outside this repository.

New files start as an empty JSON object (`{}`). Leave it empty if you do not
have secrets to add yet, or add JSON entries for your applications. Close the
editor to finish; making no changes is valid.

If you are enabling an optional service now, add its credentials too:

- `tailscale-auth-key`: your Tailscale auth key as a JSON string.
- `cloudflared-<tunnel-uuid>.json`: the tunnel credentials JSON encoded as a
  JSON string, with `<tunnel-uuid>` matching `cloudflared.tunnelId` in `settings.nix`.

Save and close the editor, then set `tailscale.enable = true` or
`cloudflared.enable = true` in `settings.nix` as needed. Stage the encrypted file
so the Git-backed flake includes it:

```sh
git add secrets/vps.json
```

Running bootstrap again edits the existing file without changing its encryption
recipients. Keep this file as the server's secrets store and add credentials as
you deploy services; see [Managing secrets](#managing-secrets).

### 4. Deploy

Once the server has the `admin` account and your SSH key installed, deploy with:

```sh
just deploy admin@x.x.x.x
```

This builds the `vps` flake configuration through your local Nix installation,
copies its runtime closure to the VPS, and activates it there with sudo. Enter
the admin account's sudo password when prompted. The flake configuration name
stays `vps` even if you change `hostname` in `settings.nix`.

The transfer uses `ssh-ng` and cache substitution to reduce copying over SSH.
The configuration trusts `admin` to import the selected builder's unsigned
outputs; see [Trusted builds](#trusted-builds). Activation runs the VPS's own
`nixos-rebuild` with `--no-reexec` and the already-built system path.

For the first deployment, if only root access is available, use:

```sh
just deploy root@x.x.x.x
```

This creates the configured `admin` account and disables future root SSH logins.
Keep your existing session open and verify that you can connect as `admin`
before closing it. Subsequent deployments should use `admin@x.x.x.x`.

After the first deployment, reboot the VPS to boot into the newly installed
kernel. Deployment activates the configuration, but the running kernel does
not change until a reboot. Once you have verified SSH access as `admin`, run:

```sh
ssh -t admin@x.x.x.x 'sudo reboot'
```

The SSH connection will close. Wait for the instance to restart, then reconnect:

```sh
ssh admin@x.x.x.x
uname -r
```

Use the Tailscale address instead if public SSH access is disabled. Reboot
after future kernel updates as well to start using the updated kernel.

To add another server, copy `settings.nix` to `hosts/vps2.nix` and customize
its hostname, SSH keys, password hash, and services. Add this entry to
`nixosConfigurations` in `flake.nix`:

```nix
vps2 = mkVps (import ./hosts/vps2.nix) [];
```

Each server uses `secrets/<hostname>.json`. Bootstrap secrets using that server's
hostname and SSH address. To deploy it, pass its flake configuration name second:

```sh
just deploy admin@x.x.x.x vps2
```

Stage any new Nix modules or encrypted secrets files before deploying. Builds
include changes to tracked files even when they have not yet been committed.

## Deploying a service

After setup, define services in Nix and run `just deploy` to apply changes.
The examples below are alternatives: each runs a web server on
`127.0.0.1:8080`. Choose one, or assign different ports if using both.

### Docker

Replace the contents of `containers.nix` with:

```nix
{ ... }: {
  virtualisation.oci-containers = {
    backend = "docker";
    containers.web = {
      image = "nginx:stable";
      ports = ["127.0.0.1:8080:80"];
    };
  };
}
```

NixOS enables Docker and creates `docker-web.service` to run the container.
For your own application, replace the image and container port, and add persistent
volumes if it stores data. You can use `backend = "podman"` instead; its unit is
named `podman-web.service`.

### systemd

For a process running directly on the host, add a service inside the module body
in `configuration.nix`. Add `pkgs` to that module's arguments:

```nix
{ config, lib, pkgs, ... }: {
  # Keep the existing imports and configuration here.

  systemd.services.example-web = {
    description = "Example web server";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python -m http.server 8080 --bind 127.0.0.1";
      DynamicUser = true;
      StateDirectory = "example-web";
      WorkingDirectory = "/var/lib/example-web";
      Restart = "on-failure";
    };
  };
}
```

Replace the example command with your application's executable and arguments.
Prefer a built-in NixOS service module when your application has one; it usually
handles users, directories, and service configuration for you.

### Apply and inspect changes

Stage any new module files, then deploy using your current SSH address:

```sh
just deploy admin@x.x.x.x
ssh admin@x.x.x.x 'curl http://127.0.0.1:8080'
```

To inspect the Docker example on the VPS:

```sh
sudo systemctl status docker-web.service
sudo journalctl -u docker-web.service -n 50 --no-pager
```

Use `example-web.service` for the systemd example. Both examples listen only on
localhost. To reach them from your local machine during development:

```sh
ssh -L 8080:127.0.0.1:8080 admin@x.x.x.x
```

Open `http://127.0.0.1:8080` locally while that connection is open. To publish the
application, follow [Cloudflare Tunnel](#cloudflare-tunnel).

## Managing secrets

Setup creates `secrets/<hostname>.json`, encrypted for your local age key and the
VPS's SSH host key. Keep application passwords, API tokens, and service
credentials here. Nix contains secret names and runtime paths; secret values
stay in SOPS until they are decrypted on the VPS.

### Add or edit secrets

Reopen the server's secrets file using the same bootstrap command:

```sh
just bootstrap vps admin@x.x.x.x
```

Use your configured hostname and current SSH address, including the Tailscale
address if public access is disabled. Add entries without removing existing
ones. For example:

```json
{
  "api-key": "YOUR_APPLICATION_API_KEY",
  "app-env": "API_KEY=YOUR_APPLICATION_API_KEY\n"
}
```

These illustrate two ways to supply credentials; use the format your application
expects. SOPS encrypts the values when you save. Only the encrypted file belongs
in Git; do not put plaintext credentials in Nix files or container `environment`.

### Give a service access to a secret

For an existing systemd service called `my-app`, add this inside the module body
in `configuration.nix` (which already accepts `config`):

```nix
sops.secrets.api-key = {
  restartUnits = ["my-app.service"];
};

systemd.services.my-app.serviceConfig.LoadCredential =
  "api-key:${config.sops.secrets.api-key.path}";
```

SOPS decrypts the value to `/run/secrets/api-key`, readable only by root by
default. systemd gives the service its own credential file at
`$CREDENTIALS_DIRECTORY/api-key`. Configure the application to read that file;
`LoadCredential` does not create an environment variable containing the value.
The service restarts when the secret changes.

For an existing Docker container called `my-app`, use the `app-env` entry as an
environment file. Declare it in `configuration.nix`:

```nix
sops.secrets.app-env = {
  restartUnits = ["docker-my-app.service"];
};

virtualisation.oci-containers.containers.my-app.environmentFiles = [
  config.sops.secrets.app-env.path
];
```

The container must already have an image configured in `containers.nix`. Docker
loads the decrypted file as environment variables when it starts the container.
For Podman, use `podman-my-app.service` in `restartUnits` instead.

Stage the encrypted file and deploy to apply new declarations or changed values:

```sh
git add secrets/vps.json
just deploy admin@x.x.x.x
```

### Keep access to your secrets

Back up `${XDG_CONFIG_HOME:-~/.config}/sops/age/keys.txt` (or your custom
`SOPS_AGE_KEY_FILE`) outside the repository. It lets you edit and recover secrets
if the VPS is lost. An encrypted secrets file alone is not enough to recover them.
Bootstrap preserves existing encryption recipients; replacing the VPS or changing
keys requires explicitly updating recipients with SOPS. When rotating a service
credential, update its value in the editor, save, and deploy again.

## Enabling Tailscale

Tailscale is optional. The examples below assume setup is complete and you can
SSH as `admin`. Replace `vps` with your configured hostname when editing secrets.

Install Tailscale on your local machine and connect it to your tailnet. Create
an auth key in the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys).
For one persistent VPS, use a non-ephemeral, single-use key. See
[Tailscale's auth key documentation](https://tailscale.com/docs/features/access-control/auth-keys)
for key options and device approval requirements.

Open your encrypted secrets file:

```sh
just bootstrap vps admin@x.x.x.x
```

Add the auth key as a top-level JSON entry, preserving any existing secrets:

```json
{
  "tailscale-auth-key": "YOUR_TAILSCALE_AUTH_KEY"
}
```

In `settings.nix`, change the existing settings to:

```nix
tailscale.enable = true;
access = "public";
```

Stage the encrypted file and deploy:

```sh
git add secrets/vps.json
just deploy admin@x.x.x.x
ssh admin@x.x.x.x 'tailscale status; tailscale ip -4'
```

Approve the device in the Tailscale console if your tailnet requires it. From
your local machine, test SSH using the returned Tailscale IP:

```sh
ssh admin@100.x.y.z
```

This uses ordinary OpenSSH over Tailscale and the public key in `settings.nix`;
it does not enable Tailscale SSH. Your tailnet policy must allow the connection.

After this works, you can change `access = "tailscale"` and deploy through the
Tailscale IP:

```sh
just deploy admin@100.x.y.z
```

Open a new SSH connection through Tailscale to verify access. Future deploy and
bootstrap commands should use the Tailscale address, or the server's MagicDNS
name if enabled. This mode closes public host-service ports and trusts the
Tailscale interface; it does not restrict forwarded container traffic or
prevent Cloudflare Tunnel from publishing an application.

## Cloudflare Tunnel

Cloudflare Tunnel is optional and can be enabled after setup.

This module uses a **locally managed tunnel** with a credentials JSON file,
not a dashboard-managed tunnel token. You need a domain on Cloudflare. Follow
[Cloudflare's locally managed tunnel guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/)
to authorize your account and create a tunnel. On your local machine:

```sh
nix shell nixpkgs#cloudflared nixpkgs#jq
cloudflared tunnel login
cloudflared tunnel create vps
```

Record the tunnel UUID and credentials file path printed by the command.
Encode that file as a JSON string for SOPS (replace the example path):

```sh
jq -Rs . "$HOME/.cloudflared/TUNNEL_UUID.json"
```

Run `just bootstrap vps admin@x.x.x.x` and add a top-level entry named
`cloudflared-TUNNEL_UUID.json`, replacing `TUNNEL_UUID` with the real UUID.
Paste the entire quoted output from `jq` as its value. Preserve existing
entries. Only the SOPS-encrypted file belongs in Git; keep the original tunnel
credentials and account certificate outside the repository.

Update the existing block in `settings.nix`:

```nix
cloudflared = {
  enable = true;
  tunnelId = "TUNNEL_UUID";
};
```

Add a route inside the module body in `configuration.nix`, using the same UUID:

```nix
services.cloudflared.tunnels."TUNNEL_UUID".ingress = {
  "app.example.com" = "http://127.0.0.1:8080";
};
```

Replace the hostname and upstream address with your application. It must
already be running on the VPS at that address. Without ingress routes, the
tunnel's default response is HTTP 404.

Create the DNS route from your local machine:

```sh
cloudflared tunnel route dns TUNNEL_UUID app.example.com
```

Stage the encrypted secrets and deploy using your current SSH address:

```sh
git add secrets/vps.json
just deploy admin@x.x.x.x
```

Use the Tailscale address instead if you have restricted host access. Visit
`https://app.example.com` to check the application. This publishes the app;
configure application authentication or Cloudflare Access if it should be private.
To inspect tunnel logs, run this on the VPS with your real UUID:

```sh
sudo journalctl -u cloudflared-tunnel-TUNNEL_UUID.service -n 50 --no-pager
```

## Local building on macOS

Nix on macOS cannot natively build the Linux system used by this VPS. You need a
Linux VM or a separate Linux builder that supports **`x86_64-linux`**. Intel Macs
can virtualize that architecture directly. Apple Silicon normally runs an
`aarch64-linux` VM, so it also needs x86_64 emulation or translation; an ARM Linux
VM alone is not enough.

### Set up a nix-darwin Linux builder

[nix-darwin provides `nix.linux-builder`](https://github.com/nix-darwin/nix-darwin/blob/master/modules/nix/linux-builder.nix)
to manage a local Linux builder VM and register it with your Mac's Nix daemon.
This requires an existing nix-darwin setup that manages Nix (`nix.enable = true`);
follow the [upstream builder prerequisites](https://github.com/NixOS/nixpkgs/blob/master/doc/packages/darwin-builder.section.md).

First, add this to **your Mac's nix-darwin configuration**, keeping the builder's
default configuration for its initial bootstrap:

```nix
nix.linux-builder.enable = true;
```

Apply your Mac's configuration with its usual command, for example:

```sh
sudo darwin-rebuild switch --flake /path/to/your/mac-config#YOUR_MAC_NAME
```

On an Intel Mac, the default builder supports `x86_64-linux`. On Apple Silicon,
get the default ARM Linux builder running first, then add these options to your
Mac's configuration and apply it again:

```nix
nix.linux-builder.systems = ["aarch64-linux" "x86_64-linux"];
nix.linux-builder.config.boot.binfmt.emulatedSystems = ["x86_64-linux"];
```

This advertises x86_64 support to the Mac's Nix daemon and enables emulation
inside the Linux VM. Merely adding `x86_64-linux` to the advertised systems does
not enable emulation. Keep the initial bootstrap separate from this customization
so the default builder can build the customized VM.

### Verify and deploy

From this repository on your Mac, run a small Linux build that cannot be
substituted from a cache:

```sh
nix build --impure --no-link --print-build-logs --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  in pkgs.runCommand "linux-builder-check" { allowSubstitutes = false; }
    "uname -m | tee $out"
'
```

The build log should print `x86_64`. Once that succeeds, use:

```sh
just deploy admin@x.x.x.x
```

Leave the builder argument as its default, `local`: your Mac's Nix daemon sends
Linux derivations to the registered VM and receives the outputs into its local
store. Deployment then transfers the completed system to the VPS and activates
it there. Emulated builds may be slower than a native x86_64 Linux builder; you
can select a separate machine such as `zenbox` using the next section instead.

## Building on a separate machine

By default, `just deploy` builds through your local Nix installation. Local
builds use the local store and any builders configured with Nix. The build must
support this flake's `x86_64-linux` target. A native x86_64 Linux machine can build
directly; macOS or ARM Linux needs a compatible Linux VM, configured builder,
or emulation. Deployment does not automatically configure cross-compilation or
fall back to the VPS when local building is unavailable.

To select a separate builder, install Nix with `nix-command` and `flakes` enabled
on an x86_64 Linux machine and verify SSH access from your local machine:

```sh
ssh zenbox 'uname -m; nix --version'
```

Pass its SSH address as the third argument, after the deployment target and
flake configuration name:

```sh
# Build on zenbox for the first deployment.
just deploy root@x.x.x.x vps zenbox

# Build on zenbox for later deployments.
just deploy admin@x.x.x.x vps zenbox

# Explicitly choose local building (the default).
just deploy admin@x.x.x.x vps local
```

The builder can be `user@builder.example.com` or an `ssh-ng://` store URL.
The builder account needs access to its Nix store and permission to accept the
build inputs. Nix's remote-store permission errors must be resolved on that
builder before it can be used. Both the builder and the VPS must be reachable
from your local machine.

With an explicit remote builder, intermediate outputs stay on that builder.
Only the completed system's runtime closure is streamed through your local
machine to the VPS. Cache substitution reduces the paths transferred, and no
local Linux build is required.

For recovery or a one-time trust bootstrap on an existing VPS, you can explicitly
build on the deployment target:

```sh
just deploy admin@x.x.x.x vps target
```

This is an opt-in fallback; normal local and separate-builder deployments do not
build on the VPS. Reboot and check SSH access after kernel changes as described
in [Setup](#setup).

## Trusted builds

This configuration adds `admin` to `nix.settings.trusted-users`, alongside
`root`. Deployment can therefore import the selected builder's unsigned outputs
as `admin`, then use sudo for activation. There is no signing-key setup.

**A trusted Nix user has root-equivalent privileges without a sudo password.**
Use this account only for server administration, and select only builders you
trust to produce the server's system. SSH authenticates the connection and
protects the transfer; it does not verify whether a build is safe to run.

The copy command uses `--no-check-sigs` for that deployment only. Global
signature checking remains enabled for normal Nix operations. This setting
does not change SSH authentication or grant other users Nix trust.

### Initial and existing VPS instances

For the first deployment, use the provisioned `root` account, which Nix already
trusts:

```sh
just deploy root@x.x.x.x
# Or, from macOS or another machine without a configured Linux builder:
just deploy root@x.x.x.x vps zenbox
```

That deployment creates `admin` and installs its Nix trust configuration.
Subsequent local or separate-builder deployments can use `admin`.

If an existing VPS predates this change and root SSH is already disabled, apply
this configuration once with the explicit on-target fallback:

```sh
just deploy admin@x.x.x.x vps target
```

The system is built on the target, so no unsigned runtime outputs need to be
imported before trust is installed. Afterward, return to your local machine or
separate builder for builds. Signing keys can be added later if you need a
workflow that keeps the deployment account outside `trusted-users`.

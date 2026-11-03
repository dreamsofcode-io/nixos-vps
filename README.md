# NixOS VPS

A starting configuration for a NixOS VPS, with optional Tailscale and Cloudflare Tunnel integration.

## Requirements

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
- A terminal editor available through `EDITOR` or `SOPS_EDITOR` if you plan
  to bootstrap secrets, for example `export EDITOR=nano`.

Check that Nix and just are available:

```sh
nix --version
just --version
```

The bootstrap recipe obtains SOPS and the age tools through Nix; you do not
need to install them separately. Builds run on the VPS, so your local machine
does not need to build Linux packages itself.

## Instructions

### 1. Obtain a NixOS instance

You need a VPS running NixOS. For the Hostinger VPS used in the video, visit
[hostinger.com/dreamsofcode](https://hostinger.com/dreamsofcode) and select NixOS
as the operating system when provisioning your server.

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

### 3. Bootstrap secrets

If you plan to enable Tailscale or Cloudflare Tunnel, run:

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

In the editor, add the entries needed by the services you intend to enable:

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
recipients. If both services remain disabled, you can skip secrets bootstrapping.

### 4. Deploy

Once the server has the `admin` account and your SSH key installed, deploy with:

```sh
just deploy admin@x.x.x.x
```

This builds the `vps` flake configuration on the VPS and activates it. The recipe
uses the `ssh-ng` store protocol and remote cache substitution with
`--use-substitutes` to reduce copying over SSH. It also uses `--no-reexec` so
macOS does not try to execute the Linux rebuild tool. The flake configuration
name stays `vps` even if you change `hostname` in `settings.nix`.
Enter the admin account's sudo password when prompted.

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

## Building on a separate machine

The machine running `just` evaluates the configuration; the build host produces
the Linux system, and the deployment target receives and activates it. By default,
the VPS is both the build host and deployment target. Your local machine can run
macOS or have a different CPU architecture because it does not build the system.

To use a faster builder, install Nix with `nix-command` and `flakes` enabled on a
Linux machine and verify SSH access from your local machine:

```sh
ssh zenbox 'uname -m; nix --version'
```

This flake targets `x86_64-linux`, so use an x86_64 Linux builder. An ARM Linux
machine or Mac needs an x86_64 Linux VM or configured emulation to build this
target; selecting it with `--build-host` does not enable cross-compilation.

Pass the builder's SSH address as the third argument, after the deployment target
and flake configuration name:

```sh
# Initial deployment: build on zenbox, activate on the VPS.
just deploy root@x.x.x.x vps zenbox

# Later deployments: use the admin account on the VPS.
just deploy admin@x.x.x.x vps zenbox
```

The builder can also be addressed as `user@builder.example.com`. Both hosts must
be reachable over SSH from your local machine. The builder account needs access
to its Nix store; the target account needs root access or sudo for activation.
The recipe uses cache substitution on both hosts and transfers the remaining
build outputs through your local machine. It does not activate the VPS
configuration on the builder.

A separate builder's outputs may require signatures from a key trusted by the
target's Nix store. For repeated use, configure signing on the builder and add
its public signing key to the target's `nix.settings.trusted-public-keys`.
If deployment stops with “lacks a signature by a trusted key”, and you trust the
authenticated builder, you can instead allow the specific copy once:

```sh
# Use the complete /nix/store/...-nixos-system-... path printed by deployment.
nix copy --no-check-sigs --from ssh-ng://zenbox \
  --to ssh-ng://root@x.x.x.x /nix/store/SYSTEM_PATH
just deploy root@x.x.x.x vps zenbox
```

This override applies only to that copy. For an admin target, arrange signing
and trust before deployment, or perform the import through an authorized root
session. Keep the documented reboot and SSH checks after activation.

## Optional services

The examples below assume you have completed the first deployment and can SSH
as `admin`. Before that deployment, use your provisioned account instead.
Replace `vps` with your configured hostname when bootstrapping secrets.

### Tailscale

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

### Cloudflare Tunnel

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

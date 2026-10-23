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

Run the following commands from this repository's directory on your local machine.

Before deploying:

- Add your public SSH key to `users.users.admin.openssh.authorizedKeys.keys`
  in your server's entry in `flake.nix`. For example, copy the contents of
  `~/.ssh/id_ed25519.pub` into a quoted entry in that list. Use your public
  key (`.pub`), never your private key. The list starts empty; add your key
  before deploying so you can log in as `admin`.
- Generate an admin password hash with
  `nix run nixpkgs#mkpasswd -- --method=yescrypt` and put the result in
  `users.users.admin.hashedPassword`. Do not leave it empty. You will use this
  password for sudo; SSH login uses your key.
- Set your server's hostname in `flake.nix`. The examples below use `vps`.
- Keep `custom.networking.access = "public"` until you have confirmed that
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

The first argument is the hostname set in `flake.nix`. Bootstrap uses it to
name `secrets/vps.json`; it does not evaluate the NixOS configuration.

The command creates or reuses a local age key at
`${XDG_CONFIG_HOME:-~/.config}/sops/age/keys.txt` (or `SOPS_AGE_KEY_FILE`, if set),
reads the VPS's public SSH host key, and opens SOPS in your editor. New secrets
files are encrypted for both your local age key and the VPS host key. Keep a
backup of your local private age key outside this repository.

In the editor, add the entries needed by the services you intend to enable:

- `tailscale-auth-key`: your Tailscale auth key as a JSON string.
- `cloudflared-<tunnel-uuid>.json`: the tunnel credentials JSON encoded as a
  JSON string, with `<tunnel-uuid>` matching `services.cloudflared.tunnelId`.

Save and close the editor, then enable the corresponding services in your
configuration. Stage the encrypted file so the Git-backed flake includes it:

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

This builds the `vps` configuration on the VPS and activates it. Enter the
admin account's sudo password when prompted.

For the first deployment, if only root access is available, use:

```sh
just deploy root@x.x.x.x
```

This creates the configured `admin` account and disables future root SSH logins.
Keep your existing session open and verify that you can connect as `admin`
before closing it. Subsequent deployments should use `admin@x.x.x.x`.

To deploy another configuration defined in `flake.nix`, pass its name second:

```sh
just deploy admin@x.x.x.x vps2
```

Stage any new Nix modules or encrypted secrets files before deploying. Builds
include changes to tracked files even when they have not yet been committed.

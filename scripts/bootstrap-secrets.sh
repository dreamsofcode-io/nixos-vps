#!/usr/bin/env bash
set -euo pipefail

hostname="$1"
target="${2:-admin@$hostname}"
key_file="${3:-${SOPS_AGE_KEY_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt}}"
# Match networking.hostName; no NixOS configuration evaluation is needed.
[[ "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || { echo 'Invalid hostname' >&2; exit 1; }
secrets_file="secrets/$hostname.json"

# Authenticate with SSH instead of trusting an unauthenticated ssh-keyscan.
ssh_options=()
[[ -z "${NIX_SSHOPTS:-}" ]] || read -r -a ssh_options <<< "$NIX_SSHOPTS"
server_recipient=$(ssh "${ssh_options[@]}" "$target" 'cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age)

umask 077
if [[ ! -e "$key_file" ]]; then
    mkdir -p "$(dirname "$key_file")"
    age-keygen -o "$key_file"
fi
local_recipient=$(age-keygen -y "$key_file")
export SOPS_AGE_KEY_FILE="$key_file"
mkdir -p secrets

echo 'Enter service secrets as JSON: tailscale-auth-key for Tailscale,'
echo 'and cloudflared-<tunnel-uuid>.json (a JSON string) for Cloudflare Tunnel.'
if [[ -e "$secrets_file" ]]; then
    # Existing files retain their recipients; never overwrite or rekey silently.
    sops "$secrets_file"
else
    sops --age "$local_recipient,$server_recipient" "$secrets_file"
fi

echo "Secrets saved to $secrets_file. Stage this encrypted file before deploying."

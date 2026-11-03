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

if [[ ! -e "$secrets_file" ]]; then
    # Start with an empty store so services can be configured later.
    printf '{}\n' | sops --encrypt --input-type json --output-type json \
        --age "$local_recipient,$server_recipient" --output "$secrets_file" /dev/stdin
fi

echo 'Add secrets as JSON entries, or leave the empty object for later.'
echo 'Optional service keys: tailscale-auth-key and cloudflared-<tunnel-uuid>.json.'
# Existing files retain their recipients; never overwrite or rekey silently.
status=0
sops "$secrets_file" || status=$?
# SOPS returns 200 when the editor closes without changes, including an empty store.
if [[ "$status" != 0 && "$status" != 200 ]]; then
    exit "$status"
fi

echo "Secrets saved to $secrets_file. Stage this encrypted file before deploying."

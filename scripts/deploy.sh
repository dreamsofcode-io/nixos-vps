#!/usr/bin/env bash
set -euo pipefail

target="${1:-admin@vps}"
name="${2:-vps}"
builder="${3:-local}"
[[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid configuration name' >&2; exit 1; }
ssh_options=()
[[ -z "${NIX_SSHOPTS:-}" ]] || read -r -a ssh_options <<< "$NIX_SSHOPTS"

# Authenticate before starting a potentially lengthy build.
ssh "${ssh_options[@]}" "$target" true
flake_path=".#nixosConfigurations.$name.config.system.build.toplevel"
deploy_tmp=$(mktemp -d)
trap 'rm -rf -- "$deploy_tmp"' EXIT
copy_options=()
if [[ "$builder" == local ]]; then
    # Keep the output rooted until transfer and activation finish.
    if ! system_path=$(nix --extra-experimental-features 'nix-command flakes' build \
        "$flake_path" --out-link "$deploy_tmp/system" --print-out-paths --no-update-lock-file); then
        echo 'Local builds need x86_64-linux support. Use a Linux VM, configured Nix builders, or pass a remote builder as the third argument.' >&2
        exit 1
    fi
else
    [[ "$builder" != target ]] || builder="$target"
    [[ "$builder" == *://* ]] || builder="ssh-ng://$builder"
    system_path=$(nix --extra-experimental-features 'nix-command flakes' build \
        --eval-store auto --store "$builder" --no-link --print-out-paths \
        --no-update-lock-file "$flake_path")
    copy_options=(--from "$builder")
fi
[[ "$system_path" =~ ^/nix/store/[a-z0-9]{32}-[a-zA-Z0-9+._=-]+$ ]] || { echo 'Builder returned an invalid system store path.' >&2; exit 1; }

# The selected builder is trusted to produce this system. Only this copy skips
# signatures; the target daemon must trust the SSH account (admin or root).
if [[ "$builder" != "ssh-ng://$target" ]]; then
    if ! nix --extra-experimental-features nix-command copy --use-substitutes \
        --no-check-sigs "${copy_options[@]}" --to "ssh-ng://$target" "$system_path"; then
        echo 'Transfer failed. The target SSH account must be a trusted Nix user. For an existing VPS, see the trusted-builds bootstrap instructions.' >&2
        exit 1
    fi
fi

privilege="sudo "
[[ "$target" != root@* ]] || privilege=""
# Activate on the VPS: the system path is already present there. sudo may prompt.
ssh "${ssh_options[@]}" -t "$target" \
    "${privilege}/run/current-system/sw/bin/nixos-rebuild switch --no-reexec --store-path '$system_path'"

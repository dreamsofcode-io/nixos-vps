default:
    @just --list

# Create or edit secrets encrypted for your local age key and the VPS host key.
[positional-arguments]
bootstrap hostname="vps" target="" key_file="":
    #!/usr/bin/env bash
    set -euo pipefail
    exec nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . \
        nixpkgs#age nixpkgs#ssh-to-age nixpkgs#sops \
        --command bash scripts/bootstrap-secrets.sh "$1" "$2" "$3"

# Build on the VPS or a separate builder and activate on the VPS, prompting for sudo.
[positional-arguments]
deploy target="admin@vps" name="vps" builder="":
    #!/usr/bin/env bash
    set -euo pipefail
    target="$1"
    name="$2"
    builder="${3:-$target}"
    [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid configuration name' >&2; exit 1; }
    sudo_options=()
    if [[ "$target" != root@* ]]; then
        sudo_options=(--sudo --ask-sudo-password)
    fi
    exec nix --extra-experimental-features 'nix-command flakes' run --inputs-from . \
        nixpkgs#nixos-rebuild-ng -- switch --flake ".#$name" --use-substitutes --no-reexec \
        --build-host "ssh-ng://$builder" --target-host "ssh-ng://$target" "${sudo_options[@]}"

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

# Build locally by default, or select a remote builder; activate on the VPS with sudo.
[positional-arguments]
deploy target="admin@vps" name="vps" builder="local":
    bash scripts/deploy.sh "$1" "$2" "$3"

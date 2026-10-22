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

# Build on the target VPS and activate it, prompting for sudo authentication.
[positional-arguments]
deploy name="vps" target="":
    #!/usr/bin/env bash
    set -euo pipefail
    name="$1"
    target="${2:-admin@$name}"
    [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid configuration name' >&2; exit 1; }
    exec nix --extra-experimental-features 'nix-command flakes' run --inputs-from . \
        nixpkgs#nixos-rebuild-ng -- switch --flake ".#$name" \
        --build-host "$target" --target-host "$target" --sudo --ask-sudo-password

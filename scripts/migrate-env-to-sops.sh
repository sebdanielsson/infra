#!/bin/sh
# Convert a stack's dotenvx-encrypted .env into a sops+age encrypted .env.sops.
#
# Prerequisites:
#   - dotenvx and sops on PATH
#   - DOTENV_PRIVATE_KEY exported (the dotenvx private key for docker/ envs)
#   - .sops.yaml at the repo root with the real age recipient
#
# Usage: DOTENV_PRIVATE_KEY=... ./scripts/migrate-env-to-sops.sh docker/<stack>
set -eu

dir="${1:?usage: migrate-env-to-sops.sh docker/<stack>}"
[ -f "$dir/.env" ] || { echo "error: $dir/.env not found" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

dotenvx decrypt -f "$dir/.env" --stdout \
  | grep -v '^DOTENV_PUBLIC_KEY' \
  | grep -v '^#/' > "$tmp"

sops --input-type dotenv --output-type dotenv --encrypt "$tmp" > "$dir/.env.sops"
git rm -q "$dir/.env"

echo "Wrote $dir/.env.sops and removed $dir/.env from git"

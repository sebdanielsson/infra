#!/bin/sh
# Run a command with the values from one or more sops-encrypted dotenv files
# exported into its environment. Decrypted values never touch disk.
#
# Requires sops on PATH and SOPS_AGE_KEY or SOPS_AGE_KEY_FILE set.
# Usage: sops-run.sh <file.sops> [<file.sops> ...] -- <command> [args...]
set -eu

files=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    break
  fi
  files="$files $1"
  shift
done

if [ -z "$files" ] || [ $# -eq 0 ]; then
  echo "usage: sops-run.sh <file.sops>... -- <command> [args...]" >&2
  exit 2
fi

for f in $files; do
  plain="$(sops --input-type dotenv --output-type dotenv --decrypt "$f")"
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    case "$val" in
      \"*\") val="${val#\"}" val="${val%\"}" ;;
    esac
    export "$key=$val"
  done <<EOF
$plain
EOF
done

exec "$@"

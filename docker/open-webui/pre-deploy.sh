#!/bin/sh
# Arcane GitOps pre-deploy hook: decrypt this project's secrets.
# Runner image: ghcr.io/sebdanielsson/sops-runner:v3.13.2 (sops as uid 65532)
# Hook env:     SOPS_AGE_KEY_FILE=/run/secrets/age.key
# Extra mount:  /docker/secrets/age.key:/run/secrets/age.key:ro
set -eu
umask 077
# Clear any stale .env first (e.g. root-owned from an older runner); the
# runner matches the workspace owner so unlink+recreate always works.
rm -f .env
sops --input-type dotenv --output-type dotenv --decrypt .env.sops > .env

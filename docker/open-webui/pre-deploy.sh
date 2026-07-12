#!/bin/sh
# Arcane GitOps pre-deploy hook: decrypt this project's secrets.
# Runner image: ghcr.io/getsops/sops:v3.13.2-alpine
# Hook env:     SOPS_AGE_KEY_FILE=/run/secrets/age.key
# Extra mount:  /docker/secrets/age.key:/run/secrets/age.key:ro
set -eu
umask 077
# Unlink before writing: the runner is root with all capabilities dropped,
# so recreating is more robust than truncating if ownership ever drifts.
rm -f .env
sops --input-type dotenv --output-type dotenv --decrypt .env.sops > .env.tmp
mv .env.tmp .env

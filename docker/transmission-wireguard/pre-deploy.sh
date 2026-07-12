#!/bin/sh
# Arcane GitOps pre-deploy hook: decrypt this project's secrets and render
# wg0.conf into the workspace, where compose bind-mounts it into the
# wireguard container (Arcane rejects named volumes as extra-mount sources).
# Runner image: ghcr.io/sebdanielsson/sops-runner:v3.13.2 (sops as uid 65532)
# Hook env:     SOPS_AGE_KEY_FILE=/run/secrets/age.key
# Extra mount:  /docker/secrets/age.key:/run/secrets/age.key:ro
set -eu
umask 077
# Clear any stale .env first (e.g. root-owned from an older runner); the
# runner matches the workspace owner so unlink+recreate always works.
rm -f .env
sops --input-type dotenv --output-type dotenv --decrypt .env.sops > .env
. ./.env

# The container init may re-own the bind-mounted file, and docker creates
# a directory here if compose ever starts before the file exists;
# unlink+recreate handles both.
rm -rf wg0.conf
cat > wg0.conf <<EOF
[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = 10.2.0.2/32
DNS = 10.2.0.1
PostUp = ip -4 route add 192.168.1.0/24 via 172.100.0.1; ip -4 route add 100.0.0.0/8 via 172.100.0.1; ping -c 2 ${WG_ENDPOINT} > /dev/null || true
PreDown = ip -4 route delete 192.168.1.0/24; ip -4 route delete 100.0.0.0/8;

[Peer]
PublicKey = ${WG_PUBLIC_KEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_ENDPOINT}
EOF
chmod 600 wg0.conf

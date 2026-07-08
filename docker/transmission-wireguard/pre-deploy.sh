#!/bin/sh
# Arcane GitOps pre-deploy hook: decrypt this project's secrets and render
# wg0.conf into the wireguard_confs volume (mounted at /out).
# Runner image: ghcr.io/getsops/sops:v3.11.0-alpine
# Hook env:     SOPS_AGE_KEY_FILE=/run/secrets/age.key
# Extra mounts: /docker/secrets/age.key:/run/secrets/age.key:ro
#               wireguard_confs:/out:rw
set -eu
sops --input-type dotenv --output-type dotenv --decrypt .env.sops > .env
. ./.env

cat > /out/wg0.conf <<EOF
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
chmod 640 /out/wg0.conf

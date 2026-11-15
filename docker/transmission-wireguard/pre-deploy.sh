#!/bin/sh
# Arcane GitOps pre-deploy hook: decrypt this project's secrets and render
# wg0.conf into the workspace, where compose bind-mounts it into the
# wireguard container (Arcane rejects named volumes as extra-mount sources).
# Runner image: Arcane default, ARCANE_LIFECYCLE_DEFAULT_RUNNER_IMAGE in docker/arcane/compose.yaml
# Hook env:     SOPS_AGE_KEY_FILE=/run/secrets/age.key
# Extra mount:  /docker/secrets/age.key:/run/secrets/age.key:ro
set -eu
umask 077
# Unlink before writing: the runner is root with all capabilities dropped,
# so recreating is more robust than truncating if ownership ever drifts.
rm -f .env
sops --input-type dotenv --output-type dotenv --decrypt .env.sops > .env.tmp
mv .env.tmp .env
. ./.env

# Compose only recreates a container when its config changes, and the
# bind-mounted anacrolix source isn't part of that config. Pass a hash of it
# as an environment variable so a code change rebuilds and restarts it.
if [ -d anacrolix ]; then
  src_hash=$(find anacrolix -type f | sort | xargs sha256sum | sha256sum | cut -c1-16)
  echo "ANACROLIX_SRC_HASH=${src_hash}" >> .env
fi

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

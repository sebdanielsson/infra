# Migrating Docker stacks to Arcane GitOps

Moves all app stacks from Ansible-managed deployments to Arcane [git-synced
projects](https://getarcane.app/docs/features/projects#sync-from-git) with
[pre-deploy lifecycle hooks](https://getarcane.app/docs/guides/gitops-lifecycle-hooks)
decrypting secrets, and replaces dotenvx with sops + age.

Not migrated: `arcane` (deployed by Ansible as bootstrap), `plausible`
(excluded), and the `state: absent` stacks (traefik, prometheus-grafana,
etlegacy, minecraft).

## How it fits together

- Each stack keeps its `docker/<stack>/` directory. Secrets live in a
  committed, sops+age-encrypted `.env.sops`; the plaintext `.env` is
  gitignored and only ever exists at deploy time.
- Arcane pulls the stack directory from git (`syncDirectory: true`) and, for
  stacks with secrets, runs the committed `pre-deploy.sh` in a sops runner
  container before every deploy. The hook decrypts `.env.sops` to `.env` in
  the workspace, which compose then uses for `${VAR}` interpolation.
- transmission-wireguard's hook additionally renders `wg0.conf` from env
  values into the `wireguard_confs` named volume — no config file in git or
  on the host filesystem.
- One age keypair: the public key is the recipient in `.sops.yaml`; the
  private key is the `SOPS_AGE_KEY` GitHub Actions secret (backed up in the
  password manager) and is provisioned to `/docker/secrets/age.key` by the
  playbooks.
- Renovate keeps updating image tags in git; auto-sync redeploys running
  projects a few minutes after merge.

## Phase 1 — keys (local machine)

Requires: `age` and `sops`.

```sh
age-keygen -o arcane.agekey            # prints the public key (age1...)
```

1. Put the **public** key in `.sops.yaml`, replacing `AGE_RECIPIENT_PLACEHOLDER`.
2. Store the private key as a GitHub Actions secret and in your password
   manager:

   ```sh
   grep AGE-SECRET-KEY arcane.agekey | gh secret set SOPS_AGE_KEY
   ```

3. Keep `arcane.agekey` out of git (gitignored) — you need it locally for
   `sops edit`.

## Phase 2 — convert secrets (before merging this branch)

*(Executed — kept for the record. All dotenvx files, including the ansible
env files and CI secrets, have since been converted; `migrate-env-to-sops.sh`
was removed once nothing was left to migrate.)*

```sh
export DOTENV_PRIVATE_KEY=<docker env decryption key>
export SOPS_AGE_KEY_FILE=$PWD/arcane.agekey

./scripts/migrate-env-to-sops.sh docker/arcane        # REQUIRED before merge
./scripts/migrate-env-to-sops.sh docker/pocket-id
./scripts/migrate-env-to-sops.sh docker/open-webui
./scripts/migrate-env-to-sops.sh docker/minio
./scripts/migrate-env-to-sops.sh docker/transmission-wireguard
```

Add the WireGuard values (previously CI secrets `WG_*`) to transmission's env:

```sh
sops edit --input-type dotenv --output-type dotenv docker/transmission-wireguard/.env.sops
```

```dotenv
WG_PRIVATE_KEY="..."
WG_PUBLIC_KEY="..."
WG_ENDPOINT="..."
```

Commit, merge the PR. The playbook run then installs sops on the host,
writes `/docker/secrets/age.key`, and redeploys Arcane from `.env.sops`.

## Phase 3 — Arcane setup (UI)

1. **Git credential**: Settings → Git, add a read-only credential for
   `sebdanielsson/infra` (fine-grained PAT, Contents: read). The repository
   name configured here must match `gitRepo` in the import file.
2. **Import projects**: Projects → Git Sync → import
   [`arcane-gitops-import.json`](./arcane-gitops-import.json).
3. **Hooks** for the four secret-bearing projects (pocket-id, open-webui,
   minio, transmission-wireguard):

   | Setting      | Value                                          |
   | ------------ | ---------------------------------------------- |
   | Script path  | `pre-deploy.sh`                                |
   | Runner image | `ghcr.io/getsops/sops:v3.13.2-alpine`          |
   | Network      | `none`                                         |
   | Environment  | `SOPS_AGE_KEY_FILE=/run/secrets/age.key`       |
   | Extra mounts | `/docker/secrets/age.key:/run/secrets/age.key:ro` |

   transmission-wireguard needs one extra mount on top:
   `wireguard_confs:/out:rw`, and the volume created once on the host:
   `docker volume create wireguard_confs`.

## Phase 4 — cutover

Sync one project at a time; each first deploy recreates the containers under
the same compose project name (data volumes persist).

1. `nginx` — pilot: no secrets, but verifies git sync, `syncDirectory`, and
   that the workspace lands under `/docker` (required for its relative
   `./default.conf` bind mount).
2. `media-stack`, `termix`, `portainer` — no secrets.
3. `minio`, `open-webui` — verifies the hook + sops path.
4. `pocket-id` — brief IdP downtime while it recreates.
5. `transmission-wireguard` — verify with
   `docker exec wireguard wg show` and a torrent IP check.

Verify during the pilot (docs don't pin these down):

- Git-sync workspaces must materialize under `PROJECTS_DIRECTORY` (`/docker`)
  so relative bind mounts resolve on the host. *(Confirmed during the pilot:
  staging dirs are created directly under `/docker`.)*
- Hook working directory should be the workspace root (`pre-deploy.sh` and
  `.env.sops` paths assume it).
- Extra mounts must accept a named volume source (`wireguard_confs:/out:rw`).

Found during the pilot: Arcane's app worker runs as uid 65532 (distroless
nonroot), so `/docker` and every managed project dir must be writable by it
or syncs fail with `permission denied` on the staging dir. The hogsmeade
playbook enforces this with `/tmp` semantics — `/docker` is `root:65532`
mode `1775` (group write + sticky bit), so the worker can create staging
dirs and workspaces but cannot remove or replace the root-owned
`/docker/arcane` and `/docker/secrets`; each managed project dir is owned
by `65532`. The worker has no business reading the age key — hook runner
containers get it from the docker daemon instead.

## Phase 5 — cleanup

- On hogsmeade: delete the orphaned Ansible-era stack dirs (`/docker/<stack>`
  for everything except `arcane` and Arcane's own workspaces). The playbooks
  remove `/docker/.env.keys` and `/usr/local/bin/dotenvx` automatically.
- Once the sops-based workflow has run green: delete the
  `DOTENV_PRIVATE_KEY` and `DOTENV_PRIVATE_KEY_CI` GitHub Actions secrets
  and the local `.env.keys` / `ansible/.env.keys` files.
- Rotate the Tailscale OAuth client (`TS_CLIENTID`/`TS_CLIENTSECRET` in
  `.env.ci.sops`): the retired dotenvx ciphertext remains in git history of
  a public repo, so treat the old values as exposed once their key leaves
  the GitHub secret store.

## Optional follow-up

Replace `linuxserver/wireguard` with Gluetun (`ghcr.io/qdm12/gluetun`):
env-var-only config would remove the rendered `wg0.conf`, the `wireguard_confs`
volume, the `PostUp`/`PreDown` route commands (via
`FIREWALL_OUTBOUND_SUBNETS=192.168.1.0/24,100.64.0.0/10`), and the static-IP
`wgnet` network, and adds a built-in kill switch.

## Disaster recovery

Rebuild host → restore `/mnt/dockerdata` (Docker data-root, includes
`arcane_data`) → run the playbook. Arcane comes back with all git-sync
config in its database; projects re-pull from GitHub and hooks re-decrypt
secrets from the repo. Log in with the local admin account first if
pocket-id isn't running yet, and start it from Arcane. The two secrets that
must survive outside the host: the age private key (`SOPS_AGE_KEY` GitHub
secret + password manager) and the Arcane DB's `ENCRYPTION_KEY` (already in
`docker/arcane/.env.sops` in git).

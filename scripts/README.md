# Scripts

## migrate-env-to-sops.sh

Converts a docker stack's dotenvx-encrypted `.env` into a sops+age encrypted
`.env.sops` and removes the old file from git. See
[guides/arcane-gitops-migration.md](../guides/arcane-gitops-migration.md).

```sh
DOTENV_PRIVATE_KEY=... ./scripts/migrate-env-to-sops.sh docker/<stack>
```

## bootstrap-macos.sh

Used for bootstraping a new Mac. Prepares it for configuration using Ansible, installs 1Password and Homebrew.

To run it:

```sh
curl -L https://raw.githubusercontent.com/sebdanielsson/infra/refs/heads/main/scripts/bootstrap-macos.sh -o bootstrap-macos.sh
chmod +x bootstrap-macos.sh
./bootstrap-macos.sh
```

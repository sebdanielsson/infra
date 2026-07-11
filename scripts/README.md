# Scripts

## sops-run.sh

Runs a command with the values from one or more sops-encrypted dotenv files
exported into its environment — decrypted values never touch disk. Used by
the run-playbook workflow and for local playbook runs. Requires `sops` on
PATH and `SOPS_AGE_KEY` or `SOPS_AGE_KEY_FILE` set.

```sh
./scripts/sops-run.sh ansible/.env.sops ansible/.env.hogsmeade.sops -- env
```

## bootstrap-macos.sh

Used for bootstraping a new Mac. Prepares it for configuration using Ansible, installs 1Password and Homebrew.

To run it:

```sh
curl -L https://raw.githubusercontent.com/sebdanielsson/infra/refs/heads/main/scripts/bootstrap-macos.sh -o bootstrap-macos.sh
chmod +x bootstrap-macos.sh
./bootstrap-macos.sh
```

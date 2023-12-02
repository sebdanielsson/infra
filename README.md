# infra

GitOps all the things!

## Usage

Run Ansible group playbook

```sh
op run --env-file=.env -- ansible-playbook -i ./inventory.yml ./proxmox_nodes.yml
```

Run Ansible playbook for the host hogsmeade

```sh
op run --env-file=.env -- ansible-playbook -i ./inventory.yml ./hogsmeade.yml
```

Run Ansible playbook for sebastian-mba

```sh
export OP_SERVICE_ACCOUNT_TOKEN=<service-account-token>
ansible-playbook sebastian-mba.yml
```

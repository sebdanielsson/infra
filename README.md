# infra

GitOps all the things!

## Usage

Run Ansible group playbook

```sh
op run --env-file=.env -- ansible-playbook -i ./inventory.yml ./proxmox_nodes.yml
```

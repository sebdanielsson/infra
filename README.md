# infra

This repository contains Ansible playbooks, Docker Compose configurations, and Terraform configurations for managing infrastructure across multiple environments.

## Prerequisites

- Git
- Python
- [1Password CLI](https://developer.1password.com/docs/cli/get-started/) (for credential management)

## Setup Instructions

### 1. Clone the Repository

```sh
git clone https://github.com/sebdanielsson/infra.git
cd infra
```

### 2. Create and Activate Virtual Environment

```sh
python3 -m venv venv
source venv/bin/activate
```

### 3. Install Python Dependencies

```sh
pip install --upgrade pip
pip install -r ansible/requirements.txt --force-reinstall
```

### 4. Install Ansible Collections and Roles

```sh
cd ansible
ansible-galaxy install -r requirements.yml --force
cd ..
```

### 5. Verify Installation

```sh
ansible --version
ansible-lint --version
yamllint --version
```

## Running the playbooks

### Configuration

Before running playbooks, ensure you have:

1. **1Password CLI configured** with access to the required credentials
2. **SSH access** to target hosts configured
3. **Inventory file** (`ansible/inventory.yml`) updated with your hosts
4. **Group variables** in `ansible/group_vars/` configured for your environment

### Available Playbooks

#### Individual Host Playbooks

**Hogsmeade Host:**

```sh
dotenvx run -f .env -f .env.hogsmeade -- ansible-playbook -i ./inventory.yml ./hogsmeade.yml
```

**Flightradar Host:**

```sh
dotenvx run -f .env -f .env.flightradar -- ansible-playbook -i ./inventory.yml ./flightradar.yml
```

**Home Gateway (ER-X):**

```sh
dotenvx run -f .env -f .env.home-gateway -- ansible-playbook -i ./inventory.yml ./home-gateway.yml
```

**MacBook (sebastian-mba):**

```sh
dotenvx run -f .env -- ansible-playbook sebastian-mba.yml --ask-become-pass
```

### Dry Run (Check Mode)

To test playbooks without making changes, add the `--check` flag:

```sh
dotenvx run -f .env -f .env.hogsmeade -- ansible-playbook -i ./inventory.yml ./hogsmeade.yml --check
```

### Verbose Output

For detailed execution information, use verbose flags:

```sh
cd ansible
dotenvx run -f .env -f .env.hogsmeade -- ansible-playbook -i ./inventory.yml ./hogsmeade.yml -v   # verbose
dotenvx run -f .env -f .env.hogsmeade -- ansible-playbook -i ./inventory.yml ./hogsmeade.yml -vv  # more verbose
dotenvx run -f .env -f .env.hogsmeade -- ansible-playbook -i ./inventory.yml ./hogsmeade.yml -vvv # debug
```

## Docker Services

The `docker/` directory contains Docker Compose configurations for various services. Each service has its own directory with a `compose.yaml` file.

### Available Services

- **Media Services:** Jellyfin, Sonarr, Radarr, Prowlarr, Transmission
- **Infrastructure:** Traefik, Portainer, Prometheus/Grafana, Nginx
- **Applications:** Open-WebUI, Plausible, Pocket-ID, Ombi
- **Gaming:** Minecraft, ET: Legacy
- **Storage:** MinIO
- **Monitoring:** Watchtower

### Running Docker Services

Navigate to the service directory and use Docker Compose:

```sh
cd docker/jellyfin
docker compose up -d
```

## Terraform

The `terraform/` directory contains Terraform configurations for cloud infrastructure, primarily Cloudflare DNS management.

### Initialize and Apply

```sh
cd terraform
terraform init
terraform plan
terraform apply
```

## Development and Testing

### Linting

**Ansible Lint:**

```sh
cd ansible
ansible-lint
```

**YAML Lint:**

```sh
cd ansible
yamllint .
```

### Testing Playbooks

1. **Use check mode** to validate syntax and logic without making changes
2. **Start with a single host** using `--limit hostname`
3. **Use tags** to run specific tasks: `--tags "docker,security"`

## Troubleshooting

### Common Issues

1. **Virtual environment not activated:** Ensure you've activated the venv before running commands
2. **Missing dependencies:** Re-run `pip install -r ansible/requirements.txt --force-reinstall`
3. **Ansible collections missing:** Re-run `ansible-galaxy install -r ansible/requirements.yml --force`
4. **SSH connection issues:** Verify SSH key authentication and host connectivity

### Debug Commands

```sh
# Test Ansible connectivity
cd ansible
ansible all -m ping -i ./inventory.yml

# Check inventory
ansible-inventory --list -i ./inventory.yml

# Test 1Password integration
op whoami
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## Security Notes

- Sensitive data is managed through 1Password CLI integration
- SSH keys should be properly configured for target hosts
- Review playbooks in check mode before applying changes
- Keep dependencies up to date for security patches

## License

See the [LICENSE](LICENSE) file for details.

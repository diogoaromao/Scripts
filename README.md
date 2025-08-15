# Scripts

A collection of utility scripts for infrastructure automation and deployment.

## Proxmox LXC Container Setup

### `scripts/proxmox/create-lxc-docker-portainer.sh`

Automated script for creating Proxmox LXC containers with Docker and Portainer pre-installed. Designed for hosting .NET Web API applications in staging and production environments.

**Features:**
- Auto-assigns lowest available container ID (starting from 100)
- Installs Docker CE and Docker Compose
- Sets up Portainer with auto-generated admin password
- Creates organized deployment directories for staging/production
- Includes systemd services for auto-start
- Provides Docker Compose template for .NET APIs

**Usage:**

**Option 1: Run directly from GitHub**
```bash
# Download and run in one command
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/create-lxc-docker-portainer.sh | bash -s -- -n myapi-staging -p myapi

# Or download, review, and execute
wget https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/create-lxc-docker-portainer.sh
chmod +x create-lxc-docker-portainer.sh
./create-lxc-docker-portainer.sh -n myapi-staging -p myapi
```

**Option 2: Local usage**
```bash
# Make executable
chmod +x scripts/proxmox/create-lxc-docker-portainer.sh

# Staging environment
./scripts/proxmox/create-lxc-docker-portainer.sh -n myapi-staging -e staging -p myapi

# Production environment
./scripts/proxmox/create-lxc-docker-portainer.sh -n myapi-prod -e production -p myapi
```

**Parameters:**
- `-n, --name`: Container name (required)
- `-e, --env`: Environment type (staging/production)
- `-p, --project`: Project name for organization
- `-i, --id`: Container ID (auto-assigned if not specified)
- `-m, --memory`: Memory in MB (default: 2048)
- `-c, --cores`: CPU cores (default: 2)
- `-d, --disk`: Disk size (default: 8G)
- `-t, --template`: Container template (default: ubuntu-22.04-standard)
- `-s, --storage`: Storage location (default: local)
- `-b, --bridge`: Network bridge (default: vmbr0)

**What it creates:**
- LXC container with Docker and Portainer
- Portainer accessible on port 9000 (HTTP) and 9443 (HTTPS)
- Deployment directories: `/opt/deployments/staging` and `/opt/deployments/production`
- Docker Compose template for .NET API deployments
- Auto-start services for container and Portainer

**Requirements:**
- Proxmox VE host
- Ubuntu 22.04 LXC template available
- Sufficient resources on the Proxmox host

**Setting Root Password:**
The script will automatically prompt you to set the root password during setup. You'll enter the container shell where you should run:
```bash
passwd root
```
Then type `exit` to return to the host.

You can also set the password manually later:
```bash
# Replace 100 with your container ID
pct set 100 --password

# Or change password directly
pct exec 100 -- passwd root

# Or enter the container and change password manually
pct enter 100
passwd root
```

**Getting Portainer Admin Password:**
The script generates a secure admin password for Portainer:
```bash
# Replace 100 with your container ID
pct exec 100 -- cat /root/portainer_admin_password.txt
```
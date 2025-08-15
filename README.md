# Scripts

A collection of utility scripts for infrastructure automation and deployment.

## Proxmox LXC Container Setup

### `create-lxc-docker-portainer.sh`

Automated script for creating Proxmox LXC containers with Docker and Portainer pre-installed. Designed for hosting .NET Web API applications in staging and production environments.

**Features:**
- Auto-assigns lowest available container ID (starting from 100)
- Installs Docker CE and Docker Compose
- Sets up Portainer with auto-generated admin password
- Creates organized deployment directories for staging/production
- Includes systemd services for auto-start
- Provides Docker Compose template for .NET APIs

**Usage:**
```bash
# Make executable
chmod +x create-lxc-docker-portainer.sh

# Basic usage
./create-lxc-docker-portainer.sh -n myapi-staging -e staging -p myapi

# Production environment with more resources
./create-lxc-docker-portainer.sh -n myapi-prod -e production -p myapi -m 4096 -c 4 -d 16G
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
- `-s, --storage`: Storage location (default: local-lvm)
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
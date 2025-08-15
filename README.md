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

**Option 1: Local Usage**

**Step 1: Create LXC Container**
```bash
# Make executable
chmod +x scripts/proxmox/create-lxc-docker-portainer.sh

# Create container
./scripts/proxmox/create-lxc-docker-portainer.sh -n myapi-staging -p myapi

# Set root password when prompted in the next steps
pct exec <CONTAINER_ID> -- passwd root
```


**Option 2: Run Directly from GitHub**

**Step 1: Create LXC Container**
```bash
# Download and run in one command (replace myapi-staging and myapi with your values)
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/create-lxc-docker-portainer.sh | bash -s -- -n myapi-staging -p myapi

# Alternative: Download, review, and execute
wget https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/create-lxc-docker-portainer.sh
chmod +x create-lxc-docker-portainer.sh
./create-lxc-docker-portainer.sh -n myapi-staging -p myapi

# Set root password when prompted in the next steps
pct exec <CONTAINER_ID> -- passwd root
```


**Parameters:**

- `-n, --name`: Container name (required)
- `-p, --project`: Project name for organization

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
After the script completes, set the root password:
```bash
# Replace 100 with your container ID
pct exec 100 -- passwd root
```

Alternative methods:
```bash
# Use Proxmox password command
pct set 100 --password

# Or enter the container manually
pct enter 100
passwd root
```

**Setting Up GitHub Actions Deployment:**

For Portainer API deployment, configure these 6 repository secrets in GitHub:

1. **DOCKER_USERNAME**: Your Docker Hub username
2. **DOCKER_PASSWORD**: Your Docker Hub password/token
3. **PORTAINER_URL**: Public hostname on cloudflared tunnel (including protocol, excluding port)
4. **PORTAINER_USERNAME**: Your Portainer admin username
5. **PORTAINER_PASSWORD**: Your Portainer admin password
6. **PORTAINER_ENDPOINT_ID**: Go to 'Home', click 'local' container, check URL after #! for the ID


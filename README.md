# Scripts

A collection of utility scripts for infrastructure automation and deployment.

## Proxmox LXC Container Setup

### `scripts/proxmox/create-lxc-docker-portainer.sh`

Automated script for creating Proxmox LXC containers with Docker and Portainer pre-installed. Designed for CI/CD deployments via Portainer API.

**Features:**
- Auto-assigns lowest available container ID (starting from 100)
- Installs Docker CE and Docker Compose
- Sets up Portainer with auto-generated admin password
- Includes systemd services for auto-start
- Ready for GitHub Actions CI/CD via Portainer API

**Usage:**

**Option 1: Local Usage**

**Step 1: Create LXC Container**
```bash
# Make executable
chmod +x scripts/proxmox/create-lxc-docker-portainer.sh

# Create container
./scripts/proxmox/create-lxc-docker-portainer.sh -n myapi-staging

# Set root password when prompted in the next steps
pct exec <CONTAINER_ID> -- passwd root
```


**Option 2: Run Directly from GitHub**

**Step 1: Create LXC Container**
```bash
# Download and run in one command (replace myapi-staging with your value)
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/create-lxc-docker-portainer.sh | bash -s -- -n myapi-staging

# Alternative: Download, review, and execute
wget https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/create-lxc-docker-portainer.sh
chmod +x create-lxc-docker-portainer.sh
./create-lxc-docker-portainer.sh -n myapi-staging

# Set root password when prompted in the next steps
pct exec <CONTAINER_ID> -- passwd root
```


**Parameters:**

- `-n, --name`: Container name (required)

**What it creates:**

- LXC container with Docker and Portainer
- Portainer accessible on port 9000 (HTTP) and 9443 (HTTPS)
- Auto-start services for container and Portainer
- Ready for Portainer API deployments

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

**Example GitHub Actions workflow:** [deploy-to-portainer.yml](https://github.com/diogoaromao/Budget/blob/main/.github/workflows/deploy-to-portainer.yml)


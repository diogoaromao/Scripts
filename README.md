# Scripts

A collection of utility scripts for infrastructure automation and deployment.

## Proxmox LXC Container Setup

### `scripts/proxmox/create-lxc-docker-portainer.sh`

Automated script for creating Proxmox LXC containers with Docker and Portainer pre-installed. Designed for hosting .NET Web API applications in staging and production environments.

### `scripts/proxmox/setup-lxc-ssh-deploy.sh`

Secondary script for setting up SSH access and deploy user for GitHub Actions CI/CD. Run this after the main script and setting the root password.

**Features (Main Script):**
- Auto-assigns lowest available container ID (starting from 100)
- Installs Docker CE and Docker Compose
- Sets up Portainer with auto-generated admin password
- Creates organized deployment directories for staging/production
- Includes systemd services for auto-start
- Provides Docker Compose template for .NET APIs

**Features (SSH Setup Script):**
- Creates dedicated `deploy` user with Docker access for CI/CD
- Generates SSH key pair automatically
- Adds public key to container and configures SSH server
- Tests SSH connection to verify setup
- Sets proper permissions for deployment directories

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

**Step 2: Set Up SSH Access (After setting root password)**
```bash
# Make executable
chmod +x scripts/proxmox/setup-lxc-ssh-deploy.sh

# Set up SSH and deploy user
./scripts/proxmox/setup-lxc-ssh-deploy.sh -i <CONTAINER_ID>
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

**Step 2: Set Up SSH Access (After setting root password)**
```bash
# Download and run SSH setup script
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/proxmox/setup-lxc-ssh-deploy.sh | bash -s -- -i <CONTAINER_ID>
```

**Parameters:**

*Main Script:*
- `-n, --name`: Container name (required)
- `-p, --project`: Project name for organization

*SSH Setup Script:*
- `-i, --id`: Container ID (required)

**What it creates:**

*Main Script:*
- LXC container with Docker and Portainer
- Portainer accessible on port 9000 (HTTP) and 9443 (HTTPS)
- Deployment directories: `/opt/deployments/staging` and `/opt/deployments/production`
- Docker Compose template for .NET API deployments
- Auto-start services for container and Portainer

*SSH Setup Script:*
- `deploy` user with Docker access and SSH setup
- SSH key pair generated at `~/.ssh/portainer_deploy`
- SSH server configured for key-based authentication
- SSH connection tested and verified
- Proper ownership of deployment directories

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

After running the SSH setup script, you only need to:

1. Get the private key content:
```bash
cat ~/.ssh/portainer_deploy
```

2. Copy the entire output (including `-----BEGIN` and `-----END` lines) and add it to your GitHub repository secrets as `SSH_PRIVATE_KEY`

The SSH setup script automatically handles:
- SSH key pair generation
- Adding public key to the container
- Testing the SSH connection


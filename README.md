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
- Sets up SSH access for GitHub Actions deployment
- Configures SSH server for key-based authentication
- Sets proper permissions for deployment directories

**Usage:**

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
- SSH server configured for key-based authentication
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

The SSH setup script will guide you through this process, but here are the manual steps:

1. Generate SSH key pair on your local machine:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/portainer_deploy -C "github-actions-deployment"
```

2. Add the public key to the container:
```bash
# Replace 100 with your container ID
cat ~/.ssh/portainer_deploy.pub | pct exec 100 -- tee -a /home/deploy/.ssh/authorized_keys
```

3. Test SSH connection:
```bash
# Replace IP_ADDRESS with your container's IP
ssh -i ~/.ssh/portainer_deploy deploy@IP_ADDRESS
```

4. Add the private key to your GitHub repository secrets as `SSH_PRIVATE_KEY`

**Getting Portainer Admin Password:**
The script generates a secure admin password for Portainer:
```bash
# Replace 100 with your container ID
pct exec 100 -- cat /root/portainer_admin_password.txt
```
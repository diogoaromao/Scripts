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

## GitHub Actions Workflow Generator

### `scripts/github/generate-workflow.sh`

Automated script for generating GitHub Actions workflows that deploy separate API and Web applications to Portainer via API. Based on a proven template with path filtering, SHA-based tagging, and environment-specific deployments.

**Features:**
- Interactive prompt for solution name
- Generates complete CI/CD workflow with build and deploy stages
- Path-based change detection (only builds what changed)
- SHA-based Docker image tagging
- Separate staging and production environments
- Portainer API integration for deployments

**Usage:**

**Run directly from GitHub (from your solution root):**
```bash
# Interactive mode
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.sh | bash

# With solution name
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.sh | bash -s -- -s "myproject"
```

**Local usage:**
```bash
# Make executable
chmod +x scripts/github/generate-workflow.sh

# Interactive mode (run from solution root)
./scripts/github/generate-workflow.sh

# Non-interactive mode
./scripts/github/generate-workflow.sh -s "myproject"
```

**Parameters:**
- `-s, --solution`: Solution name (e.g., 'inab', 'budget', 'ecommerce')

**What it creates:**
- `.github/workflows/deploy.yml` in your current directory
- Complete workflow with build jobs for API and Web
- Staging deployment jobs (API: port 3001, Web: port 3002)
- Production deployment jobs (API: port 3000, Web: port 3003)

**Expected project structure:**
```
YourSolution/
├── src/
│   ├── YOURSOLUTION.Api/
│   │   └── Dockerfile.api
│   └── yoursolution.web/
│       └── Dockerfile.web
└── .github/
    └── workflows/
        └── deploy.yml  (generated)
```

**Generated workflow includes:**
- Path filtering: Only builds API or Web when their files change
- Docker image names: `{solution}-api` and `{solution}-web`
- Container names: `{solution}-staging`, `{solution}-web-staging`, etc.
- SHA-based tagging for reliable deployments
- Environment-specific configurations

**Requirements:**
- Docker Hub account for image storage
- Portainer instance accessible via API
- Project structure matching the expected layout above
- Same 6 GitHub repository secrets as listed above


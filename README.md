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

### `scripts/github/generate-workflow.sh` (Bash)

Automated script for generating GitHub Actions workflows that deploy separate API and Web applications to Portainer via API. Based on a proven template with path filtering, SHA-based tagging, and environment-specific deployments.

### `scripts/github/generate-workflow.ps1` (PowerShell)

PowerShell version of the workflow generator for native Windows execution without WSL requirement.

**Features:**
- Interactive prompt for solution name
- Generates complete CI/CD workflow with build and deploy stages
- Path-based change detection (only builds what changed)
- SHA-based Docker image tagging
- Separate staging and production environments
- Portainer API integration for deployments

**Usage:**

**Run directly from GitHub (from your solution root):**

*Linux/macOS/WSL:*
```bash
# Interactive mode
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.sh | bash

# With solution name
curl -sSL https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.sh | bash -s -- -s "myproject"
```

*Windows PowerShell (native):*
```powershell
# Interactive mode
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.ps1" -OutFile "temp-workflow.ps1"; .\temp-workflow.ps1; Remove-Item temp-workflow.ps1

# With solution name
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.ps1" -OutFile "temp-workflow.ps1"; .\temp-workflow.ps1 -SolutionName "myproject"; Remove-Item temp-workflow.ps1
```

*Windows PowerShell (via bash):*
```powershell
# Interactive mode
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.sh" -OutFile "temp-workflow.sh"; bash temp-workflow.sh; Remove-Item temp-workflow.sh

# With solution name
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/diogoaromao/Scripts/main/scripts/github/generate-workflow.sh" -OutFile "temp-workflow.sh"; bash temp-workflow.sh -s "myproject"; Remove-Item temp-workflow.sh
```

**Local usage:**

*Bash version:*
```bash
# Make executable
chmod +x scripts/github/generate-workflow.sh

# Interactive mode (run from solution root)
./scripts/github/generate-workflow.sh

# Non-interactive mode
./scripts/github/generate-workflow.sh -s "myproject"
```

*PowerShell version:*
```powershell
# Interactive mode (run from solution root)
.\scripts\github\generate-workflow.ps1

# Non-interactive mode
.\scripts\github\generate-workflow.ps1 -SolutionName "myproject"
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

## .NET Project Creator

### `Create-DotNetProject.ps1`

PowerShell script that creates a complete .NET solution matching the [INAB project structure](https://github.com/diogoaromao/INAB). Creates a modern .NET 9 Web API with Vue.js frontend, pre-configured with essential NuGet packages and proper directory structure.

**Features:**
- Interactive solution name prompt
- Creates .NET 9 Web API project with modern architecture
- Vue.js 3 frontend with TypeScript support
- Pre-installs essential NuGet packages (ErrorOr, FluentValidation, MediatR, etc.)
- Generates proper directory structure for clean architecture
- Docker support with Dockerfile.api
- Multiple environment configurations (Development, Production, Staging)

**Usage:**

```powershell
# Interactive mode (prompts for solution name)
.\Create-DotNetProject.ps1

# Non-interactive mode
.\Create-DotNetProject.ps1 -SolutionName "MyProject"

# Download and run
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/diogoaromao/Scripts/main/Create-DotNetProject.ps1" -OutFile "Create-DotNetProject.ps1"; .\Create-DotNetProject.ps1
```

**Parameters:**
- `-SolutionName`: Name for the solution (e.g., 'INAB', 'MyAPI', 'ECommerce')

**What it creates:**
```
YourSolution/
├── YourSolution.sln
├── src/
│   ├── YourSolution.Api/           # .NET 9 Web API
│   │   ├── Contracts/VideoGames/
│   │   ├── Data/
│   │   ├── Entities/
│   │   ├── Errors/VideoGames/
│   │   ├── Features/VideoGames/
│   │   ├── Properties/
│   │   ├── Dockerfile.api
│   │   ├── Program.cs
│   │   └── appsettings.*.json
│   └── yoursolution.web/           # Vue.js 3 with TypeScript
│       ├── src/
│       ├── public/
│       ├── .vscode/
│       └── package.json
├── tests/                          # Ready for test projects
├── .github/workflows/              # Ready for CI/CD
└── .idea/                          # JetBrains Rider support
```

**Installed NuGet Packages:**
- ErrorOr v2.0.1 - Functional error handling
- FluentValidation - Input validation
- MediatR - CQRS pattern implementation
- Microsoft.AspNetCore.OpenApi - OpenAPI/Swagger
- Microsoft.EntityFrameworkCore.InMemory - EF Core with in-memory database
- Scalar.AspNetCore - Modern API documentation

**Requirements:**
- .NET 9 SDK installed
- Node.js and npm (for Vue.js project creation)
- PowerShell execution policy allowing script execution

**Next Steps After Creation:**
1. Build the solution: `dotnet build`
2. Run the API: `dotnet run --project src\YourSolution.Api`
3. Run the web app: `cd src\yoursolution.web && npm run dev`
4. Use the GitHub workflow generator above to add CI/CD


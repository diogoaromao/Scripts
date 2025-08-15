#!/bin/bash

# Proxmox LXC Container Setup Script with Docker and Portainer
# Creates a generic LXC container for .NET Web API deployment environments

set -e

# Default values
DEFAULT_TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
DEFAULT_STORAGE="local"
DEFAULT_MEMORY=2048
DEFAULT_CORES=2
DEFAULT_DISK="8G"
DEFAULT_BRIDGE="vmbr0"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates a Proxmox LXC container with Docker and Portainer for .NET Web API deployment.

OPTIONS:
    -n, --name NAME         Container name (required)
    -e, --env ENV          Environment type (staging/production) - used in hostname
    -p, --project PROJECT  Project name for organization
    -i, --id ID            Container ID (auto-assigned if not specified, starting from 100)
    -t, --template TEMPLATE Container template (default: $DEFAULT_TEMPLATE)
    -s, --storage STORAGE   Storage location (default: $DEFAULT_STORAGE)
    -m, --memory MEMORY     Memory in MB (default: $DEFAULT_MEMORY)
    -c, --cores CORES       CPU cores (default: $DEFAULT_CORES)
    -d, --disk DISK         Disk size (default: $DEFAULT_DISK)
    -b, --bridge BRIDGE     Network bridge (default: $DEFAULT_BRIDGE)
    -h, --help             Show this help message

EXAMPLES:
    # Create staging environment for MyAPI project
    $0 -n myapi-staging -e staging -p myapi

    # Create production environment with specific resources
    $0 -n myapi-prod -e production -p myapi -m 4096 -c 4 -d 16G

EOF
}

# Function to get next available LXC ID starting from 100
get_next_id() {
    local start_id=${1:-100}
    local id=$start_id
    
    print_status "Checking for available container ID starting from $start_id..."
    
    while pct status $id >/dev/null 2>&1; do
        print_status "Container ID $id already exists, checking next..."
        ((id++))
    done
    
    print_status "Found available container ID: $id"
    echo $id
}


# Parse command line arguments
CONTAINER_NAME=""
ENVIRONMENT=""
PROJECT=""
CONTAINER_ID=""
TEMPLATE="$DEFAULT_TEMPLATE"
STORAGE="$DEFAULT_STORAGE"
MEMORY="$DEFAULT_MEMORY"
CORES="$DEFAULT_CORES"
DISK="$DEFAULT_DISK"
BRIDGE="$DEFAULT_BRIDGE"

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        -i|--id)
            CONTAINER_ID="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE="$2"
            shift 2
            ;;
        -m|--memory)
            MEMORY="$2"
            shift 2
            ;;
        -c|--cores)
            CORES="$2"
            shift 2
            ;;
        -d|--disk)
            DISK="$2"
            shift 2
            ;;
        -b|--bridge)
            BRIDGE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters or prompt for container name
if [[ -z "$CONTAINER_NAME" ]]; then
    print_status "Container name not provided. Please enter a name for the LXC container:"
    read -p "Container name: " CONTAINER_NAME
    
    if [[ -z "$CONTAINER_NAME" ]]; then
        print_error "Container name cannot be empty"
        exit 1
    fi
fi


# Get container ID if not specified
if [[ -z "$CONTAINER_ID" ]]; then
    CONTAINER_ID=$(get_next_id 100)
    print_status "Auto-assigned container ID: $CONTAINER_ID"
else
    # Check if ID is already in use
    if pct status $CONTAINER_ID >/dev/null 2>&1; then
        print_error "Container ID $CONTAINER_ID is already in use"
        exit 1
    fi
fi

# Build hostname
if [[ -n "$PROJECT" && -n "$ENVIRONMENT" ]]; then
    HOSTNAME="${PROJECT}-${ENVIRONMENT}"
elif [[ -n "$PROJECT" ]]; then
    HOSTNAME="$PROJECT"
else
    HOSTNAME="$CONTAINER_NAME"
fi

# Build network configuration
NET_CONFIG="name=eth0,bridge=$BRIDGE,ip=dhcp"

print_status "Creating LXC container with the following configuration:"
echo "  Container ID: $CONTAINER_ID"
echo "  Name: $CONTAINER_NAME"
echo "  Hostname: $HOSTNAME"
echo "  Template: $TEMPLATE"
echo "  Storage: $STORAGE"
echo "  Memory: ${MEMORY}MB"
echo "  CPU Cores: $CORES"
echo "  Disk: $DISK"
echo "  Network: $NET_CONFIG"

# Check if template exists
if ! pveam list $STORAGE | grep -q "$TEMPLATE"; then
    print_warning "Template $TEMPLATE not found in $STORAGE"
    print_status "Available templates:"
    pveam list $STORAGE
    print_error "Please download the template or specify a different one"
    exit 1
fi

# Create the LXC container
print_status "Creating LXC container..."
pct create $CONTAINER_ID $STORAGE:vztmpl/$TEMPLATE \
    --hostname $HOSTNAME \
    --memory $MEMORY \
    --cores $CORES \
    --rootfs $STORAGE:$DISK \
    --net0 $NET_CONFIG \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 1 \
    --startup order=1

print_success "Container $CONTAINER_ID created successfully"

# Start the container
print_status "Starting container..."
pct start $CONTAINER_ID

# Wait for container to be ready
print_status "Waiting for container to be ready..."
sleep 10

# Update system and install prerequisites
print_status "Updating system and installing prerequisites..."
pct exec $CONTAINER_ID -- bash -c "
    apt-get update && apt-get upgrade -y
    apt-get install -y curl wget gnupg lsb-release ca-certificates
"

# Install Docker
print_status "Installing Docker..."
pct exec $CONTAINER_ID -- bash -c "
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add user to docker group (if needed later)
    # usermod -aG docker \$USER
"

# Install Docker Compose (standalone)
print_status "Installing Docker Compose..."
pct exec $CONTAINER_ID -- bash -c "
    DOCKER_COMPOSE_VERSION=\$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'\"' -f4)
    curl -L \"https://github.com/docker/compose/releases/download/\${DOCKER_COMPOSE_VERSION}/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
"

# Create Portainer directory and docker-compose file
print_status "Setting up Portainer..."
pct exec $CONTAINER_ID -- bash -c "
    mkdir -p /opt/portainer
    cd /opt/portainer
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - '9000:9000'
      - '9443:9443'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    command: --admin-password-file /tmp/portainer_password

volumes:
  portainer_data:
EOF

    # Generate a random admin password
    ADMIN_PASSWORD=\$(openssl rand -base64 32)
    echo \"\$ADMIN_PASSWORD\" > /tmp/portainer_password
    chmod 600 /tmp/portainer_password
    
    # Save password for reference
    echo \"Portainer admin password: \$ADMIN_PASSWORD\" > /root/portainer_admin_password.txt
    chmod 600 /root/portainer_admin_password.txt
"

# Start Portainer
print_status "Starting Portainer..."
pct exec $CONTAINER_ID -- bash -c "
    cd /opt/portainer
    docker-compose up -d
"

# Create systemd service for Portainer auto-start
print_status "Creating Portainer systemd service..."
pct exec $CONTAINER_ID -- bash -c "
    cat > /etc/systemd/system/portainer.service << 'EOF'
[Unit]
Description=Portainer
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/opt/portainer
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable portainer.service
"

# Create directories for .NET deployments
print_status "Creating deployment directories..."
pct exec $CONTAINER_ID -- bash -c "
    mkdir -p /opt/deployments/{staging,production}
    chmod 755 /opt/deployments/{staging,production}
    
    # Create sample docker-compose template for .NET APIs
    cat > /opt/deployments/docker-compose.template.yml << 'EOF'
version: '3.8'

services:
  api:
    image: \${API_IMAGE:-mcr.microsoft.com/dotnet/samples:aspnetapp}
    container_name: \${PROJECT_NAME:-myapi}-\${ENVIRONMENT:-staging}
    restart: unless-stopped
    ports:
      - '\${API_PORT:-5000}:80'
      - '\${API_HTTPS_PORT:-5001}:443'
    environment:
      - ASPNETCORE_ENVIRONMENT=\${ENVIRONMENT:-Development}
      - ASPNETCORE_URLS=https://+:443;http://+:80
      - ASPNETCORE_Kestrel__Certificates__Default__Password=\${CERT_PASSWORD}
      - ASPNETCORE_Kestrel__Certificates__Default__Path=/https/aspnetapp.pfx
    volumes:
      - \${CERT_PATH:-./certs}:/https/:ro
      - \${APP_DATA:-./data}:/app/data
    networks:
      - api-network

networks:
  api-network:
    driver: bridge
EOF
"

# Get container IP for final output
CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')

print_success "LXC container setup completed successfully!"
echo ""
echo "Container Details:"
echo "  ID: $CONTAINER_ID"
echo "  Name: $CONTAINER_NAME"
echo "  Hostname: $HOSTNAME"
echo "  IP Address: $CONTAINER_IP"
echo ""
echo "Services:"
echo "  Portainer Web UI: http://$CONTAINER_IP:9000 or https://$CONTAINER_IP:9443"
echo "  Docker: Installed and running"
echo ""
echo "Next Steps:"
echo "  1. Access Portainer at http://$CONTAINER_IP:9000"
echo "  2. Login with username 'admin' and check password in:"
echo "     pct exec $CONTAINER_ID -- cat /root/portainer_admin_password.txt"
echo "  3. Use /opt/deployments/staging and /opt/deployments/production for your .NET APIs"
echo "  4. Copy docker-compose.template.yml for new deployments"
echo ""
echo "Deployment directories created:"
echo "  - /opt/deployments/staging"
echo "  - /opt/deployments/production"
echo "  - /opt/deployments/docker-compose.template.yml (template for .NET APIs)"
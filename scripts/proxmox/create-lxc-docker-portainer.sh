#!/bin/bash

# Working Proxmox LXC Container Setup Script
set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get next available ID checking both VMs and containers
get_next_id() {
    local id=100
    while qm status $id >/dev/null 2>&1 || pct status $id >/dev/null 2>&1; do
        ((id++))
    done
    echo $id
}

# Parse arguments
CONTAINER_NAME=""
PROJECT=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name) CONTAINER_NAME="$2"; shift 2 ;;
        -p|--project) PROJECT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Prompt for name if not provided
if [[ -z "$CONTAINER_NAME" ]]; then
    read -p "Container name: " CONTAINER_NAME
    if [[ -z "$CONTAINER_NAME" ]]; then
        print_error "Container name cannot be empty"
        exit 1
    fi
fi

# Get available ID
CONTAINER_ID=$(get_next_id)
print_status "Auto-assigned container ID: $CONTAINER_ID"

# Set hostname
HOSTNAME="$CONTAINER_NAME"

# Configuration
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
TEMPLATE_STORAGE="local"
CONTAINER_STORAGE="local-lvm"
MEMORY=2048
CORES=2
DISK_SIZE="8"
BRIDGE="vmbr0"

print_status "Creating LXC container with ID: $CONTAINER_ID, Hostname: $HOSTNAME"

# Check template exists
if ! pveam list $TEMPLATE_STORAGE | grep -q "$TEMPLATE"; then
    print_error "Template $TEMPLATE not found in $TEMPLATE_STORAGE"
    exit 1
fi

# Create container
print_status "Creating LXC container..."
pct create $CONTAINER_ID $TEMPLATE_STORAGE:vztmpl/$TEMPLATE \
    --hostname "$HOSTNAME" \
    --memory $MEMORY \
    --cores $CORES \
    --rootfs $CONTAINER_STORAGE:$DISK_SIZE \
    --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 1

print_success "Container $CONTAINER_ID created successfully!"

# Start container
print_status "Starting container..."
pct start $CONTAINER_ID
sleep 10

# Install Docker
print_status "Installing Docker..."
pct exec $CONTAINER_ID -- bash -c "
    apt-get update && apt-get upgrade -y
    apt-get install -y curl wget gnupg lsb-release ca-certificates
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
"

# Install Docker Compose
print_status "Installing Docker Compose..."
pct exec $CONTAINER_ID -- bash -c "
    DOCKER_COMPOSE_VERSION=\$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'\"' -f4)
    curl -L \"https://github.com/docker/compose/releases/download/\${DOCKER_COMPOSE_VERSION}/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
"

# Setup Portainer
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

volumes:
  portainer_data:
EOF

    # Generate admin password
    ADMIN_PASSWORD=\$(openssl rand -base64 32)
    echo \"\$ADMIN_PASSWORD\" > /root/portainer_admin_password.txt
    chmod 600 /root/portainer_admin_password.txt
    
    # Start Portainer
    docker-compose up -d
"

# Create deployment directories
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
    volumes:
      - \${APP_DATA:-./data}:/app/data
    networks:
      - api-network

networks:
  api-network:
    driver: bridge
EOF
"

# Create systemd service for Portainer
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

# Get container IP
CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')

# Prompt to set root password
print_status "Setting root password for container..."
pct exec $CONTAINER_ID -- passwd root

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
echo "  2. Setup admin password or use generated one:"
echo "     pct exec $CONTAINER_ID -- cat /root/portainer_admin_password.txt"
echo "  3. Use /opt/deployments/staging and /opt/deployments/production for your .NET APIs"
echo ""
echo "Deployment directories created:"
echo "  - /opt/deployments/staging"
echo "  - /opt/deployments/production"
echo "  - /opt/deployments/docker-compose.template.yml"
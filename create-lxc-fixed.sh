#!/bin/bash

# Quick fixed version for immediate use
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
if [[ -n "$PROJECT" ]]; then
    HOSTNAME="$PROJECT"
else
    HOSTNAME="$CONTAINER_NAME"
fi

# Configuration
TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local"
MEMORY=2048
CORES=2
DISK="8G"
BRIDGE="vmbr0"

print_status "Creating LXC container with ID: $CONTAINER_ID"

# Check template exists
if ! pveam list $STORAGE | grep -q "$TEMPLATE"; then
    print_error "Template $TEMPLATE not found in $STORAGE"
    exit 1
fi

# Create container
pct create $CONTAINER_ID $STORAGE:vztmpl/$TEMPLATE \
    --hostname "$HOSTNAME" \
    --memory $MEMORY \
    --cores $CORES \
    --rootfs $STORAGE:$DISK \
    --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 1 \
    --startup order=1

print_success "Container $CONTAINER_ID created successfully!"

# Start container
print_status "Starting container..."
pct start $CONTAINER_ID
sleep 10

# Install Docker and Portainer
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

print_status "Setting up Portainer..."
pct exec $CONTAINER_ID -- bash -c "
    mkdir -p /opt/portainer
    ADMIN_PASSWORD=\$(openssl rand -base64 32)
    echo \"\$ADMIN_PASSWORD\" > /root/portainer_admin_password.txt
    chmod 600 /root/portainer_admin_password.txt
    docker run -d --name portainer --restart unless-stopped -p 9000:9000 -p 9443:9443 -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
"

# Get IP
CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')

print_success "Setup complete!"
echo "Container ID: $CONTAINER_ID"
echo "IP: $CONTAINER_IP"
echo "Portainer: http://$CONTAINER_IP:9000"
echo "Admin password: pct exec $CONTAINER_ID -- cat /root/portainer_admin_password.txt"
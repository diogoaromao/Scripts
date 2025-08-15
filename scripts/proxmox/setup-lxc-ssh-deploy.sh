#!/bin/bash

# SSH and Deploy User Setup Script for LXC Containers
set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
CONTAINER_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--id) CONTAINER_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Prompt for container ID if not provided
if [[ -z "$CONTAINER_ID" ]]; then
    read -p "Container ID: " CONTAINER_ID
    if [[ -z "$CONTAINER_ID" ]]; then
        print_error "Container ID cannot be empty"
        exit 1
    fi
fi

# Verify container exists and is running
if ! pct status $CONTAINER_ID >/dev/null 2>&1; then
    print_error "Container $CONTAINER_ID does not exist"
    exit 1
fi

if [[ $(pct status $CONTAINER_ID | grep -o "status: [a-z]*" | cut -d' ' -f2) != "running" ]]; then
    print_error "Container $CONTAINER_ID is not running"
    exit 1
fi

print_status "Setting up SSH and deploy user for container $CONTAINER_ID..."

# Create deploy user and SSH setup
print_status "Creating deploy user with SSH access..."
pct exec $CONTAINER_ID -- bash -c "
    # Create deploy user for CI/CD
    useradd -m -s /bin/bash deploy 2>/dev/null || echo 'User deploy already exists'
    usermod -aG docker deploy
    
    # Set up SSH directory for deploy user
    mkdir -p /home/deploy/.ssh
    chmod 700 /home/deploy/.ssh
    touch /home/deploy/.ssh/authorized_keys
    chmod 600 /home/deploy/.ssh/authorized_keys
    chown -R deploy:deploy /home/deploy/.ssh
    
    # Set deployment directory ownership
    chown -R deploy:deploy /opt/deployments
    
    # Ensure SSH service is installed and running
    apt-get update -qq
    apt-get install -y openssh-server
    systemctl enable ssh
    systemctl start ssh
    
    # Configure SSH for key-based authentication
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart ssh
"

# Get container IP
CONTAINER_IP=$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')

# Generate SSH key pair
print_status "Generating SSH key pair..."
SSH_KEY_PATH="$HOME/.ssh/portainer_deploy"

# Create .ssh directory if it doesn't exist
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate SSH key pair (non-interactive)
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -C "github-actions-deployment" -N ""
    print_success "SSH key pair generated at $SSH_KEY_PATH"
else
    print_status "SSH key pair already exists at $SSH_KEY_PATH"
fi

# Add public key to container
print_status "Adding public key to container..."
if [[ -f "$SSH_KEY_PATH.pub" ]]; then
    cat "$SSH_KEY_PATH.pub" | pct exec $CONTAINER_ID -- tee -a /home/deploy/.ssh/authorized_keys > /dev/null
    print_success "Public key added to container"
else
    print_error "Public key file not found: $SSH_KEY_PATH.pub"
    exit 1
fi

# Wait a moment for SSH service to be ready
print_status "SSH service configured and started"

# Ensure all output is flushed
exec 1>&1

print_success "SSH and deploy user setup completed successfully!"
echo ""
echo "Container Details:"
echo "  ID: $CONTAINER_ID"
echo "  IP Address: $CONTAINER_IP"
echo "  Deploy User: deploy"
echo "  SSH Key: $SSH_KEY_PATH"
echo ""
echo "For GitHub Actions deployment, add these secrets to your repository:"
echo ""
echo "  Required for SSH deployment:"
echo "  1. Private key content (copy everything below including BEGIN/END lines):"
echo ""
cat "$SSH_KEY_PATH"
echo ""
echo "  2. Add to GitHub repository secrets:"
echo "     - PORTAINER_SSH_KEY: (Copy the ENTIRE output from step 1, including -----BEGIN and -----END lines)"
echo "     - PORTAINER_HOST: $CONTAINER_IP (or your cloudflared tunnel hostname)"
echo "     - PORTAINER_SSH_USER: deploy"
echo ""
echo "  Optional for Portainer API access:"
echo "     - PORTAINER_URL: http://$CONTAINER_IP:9000"
echo "     - PORTAINER_USERNAME: (your Portainer admin username)"
echo "     - PORTAINER_PASSWORD: (your Portainer admin password)"
echo ""
echo "SSH Setup Complete!"
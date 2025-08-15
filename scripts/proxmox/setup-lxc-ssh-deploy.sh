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

print_success "SSH and deploy user setup completed successfully!"
echo ""
echo "Container Details:"
echo "  ID: $CONTAINER_ID"
echo "  IP Address: $CONTAINER_IP"
echo "  Deploy User: deploy"
echo ""
echo "Next Steps:"
echo "  1. Generate SSH key pair on your local machine:"
echo "     ssh-keygen -t ed25519 -f ~/.ssh/portainer_deploy -C \"github-actions-deployment\""
echo ""
echo "  2. Add the public key to the container:"
echo "     cat ~/.ssh/portainer_deploy.pub | pct exec $CONTAINER_ID -- tee -a /home/deploy/.ssh/authorized_keys"
echo ""
echo "  3. Test SSH connection:"
echo "     ssh -i ~/.ssh/portainer_deploy deploy@$CONTAINER_IP"
echo ""
echo "  4. Add the private key to your GitHub repository secrets as SSH_PRIVATE_KEY"
echo ""
echo "SSH Setup Complete!"
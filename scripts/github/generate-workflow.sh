#!/bin/bash

# GitHub Actions Workflow Generator
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
SOLUTION_NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--solution) SOLUTION_NAME="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Prompt for solution name if not provided
if [[ -z "$SOLUTION_NAME" ]]; then
    read -p "Solution name (e.g., 'inab', 'budget'): " SOLUTION_NAME
    if [[ -z "$SOLUTION_NAME" ]]; then
        print_error "Solution name cannot be empty"
        exit 1
    fi
fi

# Convert to lowercase and replace spaces/special chars with hyphens
SOLUTION_LOWER=$(echo "$SOLUTION_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
SOLUTION_UPPER=$(echo "$SOLUTION_NAME" | tr '[:lower:]' '[:upper:]')

print_status "Generating workflow for solution: $SOLUTION_LOWER"

# Create .github/workflows directory if it doesn't exist
mkdir -p .github/workflows

# Generate workflow file
cat > .github/workflows/deploy.yml << EOF
name: Build and Deploy

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: docker.io
  API_IMAGE_NAME: \${{ secrets.DOCKER_USERNAME }}/${SOLUTION_LOWER}-api
  WEB_IMAGE_NAME: \${{ secrets.DOCKER_USERNAME }}/${SOLUTION_LOWER}-web

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      api: \${{ steps.changes.outputs.api }}
      web: \${{ steps.changes.outputs.web }}
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
    - uses: dorny/paths-filter@v3
      id: changes
      with:
        filters: |
          api:
            - 'src/${SOLUTION_UPPER}.Api/**'
            - '.github/workflows/deploy.yml'
          web:
            - 'src/${SOLUTION_LOWER}.web/**'
            - '.github/workflows/deploy.yml'

  build-api:
    needs: changes
    if: \${{ needs.changes.outputs.api == 'true' }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    outputs:
      image-sha: \${{ steps.sha.outputs.sha }}

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: \${{ env.REGISTRY }}
        username: \${{ secrets.DOCKER_USERNAME }}
        password: \${{ secrets.DOCKER_PASSWORD }}

    - name: Get short SHA
      id: sha
      run: echo "sha=\$(echo \${{ github.sha }} | cut -c1-7)" >> \$GITHUB_OUTPUT

    - name: Extract API metadata
      id: api-meta
      uses: docker/metadata-action@v5
      with:
        images: \${{ env.REGISTRY }}/\${{ env.API_IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-,enable=\{{is_default_branch}}
          type=raw,value=latest,enable=\{{is_default_branch}}

    - name: Build and push API Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        file: ./src/${SOLUTION_UPPER}.Api/Dockerfile.api
        push: true
        tags: \${{ steps.api-meta.outputs.tags }}
        labels: \${{ steps.api-meta.outputs.labels }}

  build-web:
    needs: changes
    if: \${{ needs.changes.outputs.web == 'true' }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    outputs:
      image-sha: \${{ steps.sha.outputs.sha }}

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: \${{ env.REGISTRY }}
        username: \${{ secrets.DOCKER_USERNAME }}
        password: \${{ secrets.DOCKER_PASSWORD }}

    - name: Get short SHA
      id: sha
      run: echo "sha=\$(echo \${{ github.sha }} | cut -c1-7)" >> \$GITHUB_OUTPUT

    - name: Extract Web metadata
      id: web-meta
      uses: docker/metadata-action@v5
      with:
        images: \${{ env.REGISTRY }}/\${{ env.WEB_IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-,enable=\{{is_default_branch}}
          type=raw,value=latest,enable=\{{is_default_branch}}

    - name: Build and push Web Docker image
      uses: docker/build-push-action@v5
      with:
        context: ./src/${SOLUTION_LOWER}.web
        file: ./src/${SOLUTION_LOWER}.web/Dockerfile.web
        push: true
        tags: \${{ steps.web-meta.outputs.tags }}
        labels: \${{ steps.web-meta.outputs.labels }}

  deploy-api-staging:
    needs: [changes, build-api]
    if: \${{ needs.changes.outputs.api == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    
    steps:
    - name: Deploy API to Staging via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=\$(curl -s -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/auth" \\
          -H "Content-Type: application/json" \\
          -d '{"username": "\${{ secrets.PORTAINER_USERNAME }}", "password": "\${{ secrets.PORTAINER_PASSWORD }}"}' \\
          | jq -r '.jwt')
        
        if [ "\$JWT_TOKEN" = "null" ] || [ -z "\$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-\${{ needs.build-api.outputs.image-sha }}"
        API_IMAGE_FULL="\${{ env.REGISTRY }}/\${{ env.API_IMAGE_NAME }}:\${IMAGE_TAG}"
        
        # Pull the API image to Portainer
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${API_IMAGE_FULL}" \\
          -H "Authorization: Bearer \$JWT_TOKEN"
        
        # Stop and remove existing API container if it exists
        API_CONTAINER_ID=\$(curl -s -X GET \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          | jq -r '.[] | select(.Names[]? | test("/${SOLUTION_LOWER}-staging\$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "\$API_CONTAINER_ID" ] && [ "\$API_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing API container: \$API_CONTAINER_ID"
          curl -X POST \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID/stop" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
          curl -X DELETE \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
        fi
        
        # Create new API container
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${SOLUTION_LOWER}-staging" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{
            "Image": "'\${API_IMAGE_FULL}'",
            "Env": [
              "ASPNETCORE_ENVIRONMENT=Staging",
              "ASPNETCORE_URLS=http://+:8080"
            ],
            "ExposedPorts": {"8080/tcp": {}},
            "HostConfig": {
              "PortBindings": {"8080/tcp": [{"HostPort": "3001"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \\
          | jq -r '.Id' > api_container_id.txt
        
        # Start the API container
        API_CONTAINER_ID=\$(cat api_container_id.txt)
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID/start" \\
          -H "Authorization: Bearer \$JWT_TOKEN"

  deploy-web-staging:
    needs: [changes, build-web]
    if: \${{ needs.changes.outputs.web == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    
    steps:
    - name: Deploy Web to Staging via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=\$(curl -s -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/auth" \\
          -H "Content-Type: application/json" \\
          -d '{"username": "\${{ secrets.PORTAINER_USERNAME }}", "password": "\${{ secrets.PORTAINER_PASSWORD }}"}' \\
          | jq -r '.jwt')
        
        if [ "\$JWT_TOKEN" = "null" ] || [ -z "\$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-\${{ needs.build-web.outputs.image-sha }}"
        WEB_IMAGE_FULL="\${{ env.REGISTRY }}/\${{ env.WEB_IMAGE_NAME }}:\${IMAGE_TAG}"
        
        # Pull the Web image to Portainer
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${WEB_IMAGE_FULL}" \\
          -H "Authorization: Bearer \$JWT_TOKEN"
        
        # Stop and remove existing Web container if it exists
        WEB_CONTAINER_ID=\$(curl -s -X GET \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          | jq -r '.[] | select(.Names[]? | test("/${SOLUTION_LOWER}-web-staging\$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "\$WEB_CONTAINER_ID" ] && [ "\$WEB_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing Web container: \$WEB_CONTAINER_ID"
          curl -X POST \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID/stop" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
          curl -X DELETE \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
        fi
        
        # Create new Web container
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${SOLUTION_LOWER}-web-staging" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{
            "Image": "'\${WEB_IMAGE_FULL}'",
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "3002"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \\
          | jq -r '.Id' > web_container_id.txt
        
        # Start the Web container
        WEB_CONTAINER_ID=\$(cat web_container_id.txt)
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID/start" \\
          -H "Authorization: Bearer \$JWT_TOKEN"

  deploy-api-production:
    needs: [changes, build-api, deploy-api-staging]
    if: \${{ needs.changes.outputs.api == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    environment: production
    
    steps:
    - name: Deploy API to Production via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=\$(curl -s -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/auth" \\
          -H "Content-Type: application/json" \\
          -d '{"username": "\${{ secrets.PORTAINER_USERNAME }}", "password": "\${{ secrets.PORTAINER_PASSWORD }}"}' \\
          | jq -r '.jwt')
        
        if [ "\$JWT_TOKEN" = "null" ] || [ -z "\$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-\${{ needs.build-api.outputs.image-sha }}"
        API_IMAGE_FULL="\${{ env.REGISTRY }}/\${{ env.API_IMAGE_NAME }}:\${IMAGE_TAG}"
        
        # Pull the API image to Portainer
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${API_IMAGE_FULL}" \\
          -H "Authorization: Bearer \$JWT_TOKEN"
        
        # Stop and remove existing API container if it exists
        API_CONTAINER_ID=\$(curl -s -X GET \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          | jq -r '.[] | select(.Names[]? | test("/${SOLUTION_LOWER}-production\$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "\$API_CONTAINER_ID" ] && [ "\$API_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing API container: \$API_CONTAINER_ID"
          curl -X POST \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID/stop" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
          curl -X DELETE \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
        fi
        
        # Create new API container
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${SOLUTION_LOWER}-production" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{
            "Image": "'\${API_IMAGE_FULL}'",
            "Env": [
              "ASPNETCORE_ENVIRONMENT=Production",
              "ASPNETCORE_URLS=http://+:8080"
            ],
            "ExposedPorts": {"8080/tcp": {}},
            "HostConfig": {
              "PortBindings": {"8080/tcp": [{"HostPort": "3000"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \\
          | jq -r '.Id' > api_container_id.txt
        
        # Start the API container
        API_CONTAINER_ID=\$(cat api_container_id.txt)
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID/start" \\
          -H "Authorization: Bearer \$JWT_TOKEN"

  deploy-web-production:
    needs: [changes, build-web, deploy-web-staging]
    if: \${{ needs.changes.outputs.web == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    environment: production
    
    steps:
    - name: Deploy Web to Production via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=\$(curl -s -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/auth" \\
          -H "Content-Type: application/json" \\
          -d '{"username": "\${{ secrets.PORTAINER_USERNAME }}", "password": "\${{ secrets.PORTAINER_PASSWORD }}"}' \\
          | jq -r '.jwt')
        
        if [ "\$JWT_TOKEN" = "null" ] || [ -z "\$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-\${{ needs.build-web.outputs.image-sha }}"
        WEB_IMAGE_FULL="\${{ env.REGISTRY }}/\${{ env.WEB_IMAGE_NAME }}:\${IMAGE_TAG}"
        
        # Pull the Web image to Portainer
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${WEB_IMAGE_FULL}" \\
          -H "Authorization: Bearer \$JWT_TOKEN"
        
        # Stop and remove existing Web container if it exists
        WEB_CONTAINER_ID=\$(curl -s -X GET \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          | jq -r '.[] | select(.Names[]? | test("/${SOLUTION_LOWER}-web-production\$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "\$WEB_CONTAINER_ID" ] && [ "\$WEB_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing Web container: \$WEB_CONTAINER_ID"
          curl -X POST \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID/stop" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
          curl -X DELETE \\
            "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID" \\
            -H "Authorization: Bearer \$JWT_TOKEN" || true
        fi
        
        # Create new Web container
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${SOLUTION_LOWER}-web-production" \\
          -H "Authorization: Bearer \$JWT_TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{
            "Image": "'\${WEB_IMAGE_FULL}'",
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "3003"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \\
          | jq -r '.Id' > web_container_id.txt
        
        # Start the Web container
        WEB_CONTAINER_ID=\$(cat web_container_id.txt)
        curl -X POST \\
          "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID/start" \\
          -H "Authorization: Bearer \$JWT_TOKEN"
EOF

print_success "GitHub Actions workflow generated: .github/workflows/deploy.yml"
echo ""
echo "Workflow details:"
echo "  Solution: $SOLUTION_LOWER"
echo "  API image: $SOLUTION_LOWER-api"
echo "  Web image: $SOLUTION_LOWER-web"
echo ""
echo "Expected project structure:"
echo "  src/${SOLUTION_UPPER}.Api/Dockerfile.api"
echo "  src/${SOLUTION_LOWER}.web/Dockerfile.web"
echo ""
echo "Container ports:"
echo "  API staging: 3001"
echo "  Web staging: 3002"
echo "  API production: 3000"
echo "  Web production: 3003"
echo ""
echo "Required GitHub secrets:"
echo "  - DOCKER_USERNAME"
echo "  - DOCKER_PASSWORD"
echo "  - PORTAINER_URL"
echo "  - PORTAINER_USERNAME"
echo "  - PORTAINER_PASSWORD"
echo "  - PORTAINER_ENDPOINT_ID"

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"id": "1", "content": "Create script to generate GitHub workflow based on solution name", "status": "in_progress"}, {"id": "2", "content": "Analyze INAB workflow structure and replaceable parts", "status": "completed"}, {"id": "3", "content": "Create template with variable substitution", "status": "completed"}]
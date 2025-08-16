#!/bin/bash

# GitHub Actions Workflow Generator for Portainer Deployment
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
PROJECT_NAME=""
DEPLOYMENT_TYPE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project) PROJECT_NAME="$2"; shift 2 ;;
        -t|--type) DEPLOYMENT_TYPE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Prompt for project name if not provided
if [[ -z "$PROJECT_NAME" ]]; then
    read -p "Project name (e.g., 'budget', 'ecommerce'): " PROJECT_NAME
    if [[ -z "$PROJECT_NAME" ]]; then
        print_error "Project name cannot be empty"
        exit 1
    fi
fi

# Convert to lowercase and replace spaces/special chars with hyphens
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')

# Prompt for deployment type if not provided
if [[ -z "$DEPLOYMENT_TYPE" ]]; then
    echo ""
    echo "Select deployment type:"
    echo "  1) API only"
    echo "  2) Web app (frontend + API)"
    read -p "Choice (1-2): " choice
    case $choice in
        1) DEPLOYMENT_TYPE="api-only" ;;
        2) DEPLOYMENT_TYPE="webapp" ;;
        *) print_error "Invalid choice. Please select 1 or 2"; exit 1 ;;
    esac
fi

print_status "Generating workflow for project: $PROJECT_NAME (type: $DEPLOYMENT_TYPE)"

# Create .github/workflows directory if it doesn't exist
mkdir -p .github/workflows

# Generate workflow file
if [[ "$DEPLOYMENT_TYPE" == "api-only" ]]; then
    # Generate API-only workflow
    cat > .github/workflows/deploy-to-portainer.yml << EOF
name: Deploy ${PROJECT_NAME^} API to Portainer

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  REGISTRY: docker.io
  IMAGE_NAME: ${PROJECT_NAME}-api

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: \${{ steps.meta.outputs.tags }}
      image-digest: \${{ steps.build.outputs.digest }}
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: \${{ env.REGISTRY }}
        username: \${{ secrets.DOCKER_USERNAME }}
        password: \${{ secrets.DOCKER_PASSWORD }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: \${{ env.REGISTRY }}/\${{ secrets.DOCKER_USERNAME }}/\${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-
          type=raw,value=staging,enable=true
          type=raw,value=latest,enable=\{{is_default_branch}}

    - name: Build and push Docker image
      id: build
      uses: docker/build-push-action@v5
      with:
        context: ./${PROJECT_NAME^}
        file: ./${PROJECT_NAME^}/src/${PROJECT_NAME^}.Api/Dockerfile
        push: true
        tags: \${{ steps.meta.outputs.tags }}
        labels: \${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy-staging:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: staging
    
    steps:
    - name: Deploy to Portainer (Staging)
      run: |
        # Authenticate with Portainer
        AUTH_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{
            "username": "\${{ secrets.PORTAINER_USERNAME }}",
            "password": "\${{ secrets.PORTAINER_PASSWORD }}"
          }')
        
        JWT=\$(echo \$AUTH_RESPONSE | jq -r '.jwt')
        
        if [ "\$JWT" = "null" ] || [ -z "\$JWT" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        # Pull latest image
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api&tag=staging" \
          -H "Authorization: Bearer \$JWT"
        
        # Stop and remove existing container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-staging/stop" \
          -H "Authorization: Bearer \$JWT" || true
        
        curl -X DELETE "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-staging?force=true" \
          -H "Authorization: Bearer \$JWT" || true
        
        # Create new container
        CREATE_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${PROJECT_NAME}-api-staging" \
          -H "Authorization: Bearer \$JWT" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api:staging",
            "Env": ["ASPNETCORE_ENVIRONMENT=Staging"],
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "5001"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }')
        
        CONTAINER_ID=\$(echo \$CREATE_RESPONSE | jq -r '.Id')
        
        if [ "\$CONTAINER_ID" = "null" ] || [ -z "\$CONTAINER_ID" ]; then
          echo "Failed to create container"
          echo "Response: \$CREATE_RESPONSE"
          exit 1
        fi
        
        # Start container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$CONTAINER_ID/start" \
          -H "Authorization: Bearer \$JWT"
        
        echo "Successfully deployed ${PROJECT_NAME}-api to staging"

  deploy-production:
    needs: [build, deploy-staging]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production
    
    steps:
    - name: Deploy to Portainer (Production)
      run: |
        # Authenticate with Portainer
        AUTH_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{
            "username": "\${{ secrets.PORTAINER_USERNAME }}",
            "password": "\${{ secrets.PORTAINER_PASSWORD }}"
          }')
        
        JWT=\$(echo \$AUTH_RESPONSE | jq -r '.jwt')
        
        if [ "\$JWT" = "null" ] || [ -z "\$JWT" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        # Pull latest image
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api&tag=latest" \
          -H "Authorization: Bearer \$JWT"
        
        # Stop and remove existing container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-prod/stop" \
          -H "Authorization: Bearer \$JWT" || true
        
        curl -X DELETE "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-prod?force=true" \
          -H "Authorization: Bearer \$JWT" || true
        
        # Create new container
        CREATE_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${PROJECT_NAME}-api-prod" \
          -H "Authorization: Bearer \$JWT" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api:latest",
            "Env": ["ASPNETCORE_ENVIRONMENT=Production"],
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "5000"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }')
        
        CONTAINER_ID=\$(echo \$CREATE_RESPONSE | jq -r '.Id')
        
        if [ "\$CONTAINER_ID" = "null" ] || [ -z "\$CONTAINER_ID" ]; then
          echo "Failed to create container"
          echo "Response: \$CREATE_RESPONSE"
          exit 1
        fi
        
        # Start container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$CONTAINER_ID/start" \
          -H "Authorization: Bearer \$JWT"
        
        echo "Successfully deployed ${PROJECT_NAME}-api to production"
EOF

else
    # Generate webapp (frontend + API) workflow
    cat > .github/workflows/deploy-to-portainer.yml << EOF
name: Deploy ${PROJECT_NAME^} to Portainer

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  REGISTRY: docker.io
  API_IMAGE_NAME: ${PROJECT_NAME}-api
  WEB_IMAGE_NAME: ${PROJECT_NAME}-web

jobs:
  build-api:
    runs-on: ubuntu-latest
    outputs:
      image-tag: \${{ steps.meta.outputs.tags }}
      image-digest: \${{ steps.build.outputs.digest }}
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: \${{ env.REGISTRY }}
        username: \${{ secrets.DOCKER_USERNAME }}
        password: \${{ secrets.DOCKER_PASSWORD }}

    - name: Extract metadata (API)
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: \${{ env.REGISTRY }}/\${{ secrets.DOCKER_USERNAME }}/\${{ env.API_IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-
          type=raw,value=staging,enable=true
          type=raw,value=latest,enable=\{{is_default_branch}}

    - name: Build and push API Docker image
      id: build
      uses: docker/build-push-action@v5
      with:
        context: ./${PROJECT_NAME^}
        file: ./${PROJECT_NAME^}/src/${PROJECT_NAME^}.Api/Dockerfile
        push: true
        tags: \${{ steps.meta.outputs.tags }}
        labels: \${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  build-web:
    runs-on: ubuntu-latest
    outputs:
      image-tag: \${{ steps.meta.outputs.tags }}
      image-digest: \${{ steps.build.outputs.digest }}
    
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: \${{ env.REGISTRY }}
        username: \${{ secrets.DOCKER_USERNAME }}
        password: \${{ secrets.DOCKER_PASSWORD }}

    - name: Extract metadata (Web)
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: \${{ env.REGISTRY }}/\${{ secrets.DOCKER_USERNAME }}/\${{ env.WEB_IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-
          type=raw,value=staging,enable=true
          type=raw,value=latest,enable=\{{is_default_branch}}

    - name: Build and push Web Docker image
      id: build
      uses: docker/build-push-action@v5
      with:
        context: ./${PROJECT_NAME^}
        file: ./${PROJECT_NAME^}/src/${PROJECT_NAME^}.Web/Dockerfile
        push: true
        tags: \${{ steps.meta.outputs.tags }}
        labels: \${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max

  deploy-staging:
    needs: [build-api, build-web]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: staging
    
    steps:
    - name: Deploy to Portainer (Staging)
      run: |
        # Authenticate with Portainer
        AUTH_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{
            "username": "\${{ secrets.PORTAINER_USERNAME }}",
            "password": "\${{ secrets.PORTAINER_PASSWORD }}"
          }')
        
        JWT=\$(echo \$AUTH_RESPONSE | jq -r '.jwt')
        
        if [ "\$JWT" = "null" ] || [ -z "\$JWT" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        # Pull latest API image
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api&tag=staging" \
          -H "Authorization: Bearer \$JWT"
        
        # Pull latest Web image
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-web&tag=staging" \
          -H "Authorization: Bearer \$JWT"
        
        # Stop and remove existing API container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-staging/stop" \
          -H "Authorization: Bearer \$JWT" || true
        
        curl -X DELETE "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-staging?force=true" \
          -H "Authorization: Bearer \$JWT" || true
        
        # Stop and remove existing Web container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-web-staging/stop" \
          -H "Authorization: Bearer \$JWT" || true
        
        curl -X DELETE "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-web-staging?force=true" \
          -H "Authorization: Bearer \$JWT" || true
        
        # Create API container
        API_CREATE_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${PROJECT_NAME}-api-staging" \
          -H "Authorization: Bearer \$JWT" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api:staging",
            "Env": ["ASPNETCORE_ENVIRONMENT=Staging"],
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "5001"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            },
            "NetworkingConfig": {
              "EndpointsConfig": {
                "${PROJECT_NAME}-network": {}
              }
            }
          }')
        
        API_CONTAINER_ID=\$(echo \$API_CREATE_RESPONSE | jq -r '.Id')
        
        if [ "\$API_CONTAINER_ID" = "null" ] || [ -z "\$API_CONTAINER_ID" ]; then
          echo "Failed to create API container"
          echo "Response: \$API_CREATE_RESPONSE"
          exit 1
        fi
        
        # Create Web container
        WEB_CREATE_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${PROJECT_NAME}-web-staging" \
          -H "Authorization: Bearer \$JWT" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-web:staging",
            "Env": [
              "NODE_ENV=staging",
              "API_BASE_URL=http://${PROJECT_NAME}-api-staging"
            ],
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "3001"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            },
            "NetworkingConfig": {
              "EndpointsConfig": {
                "${PROJECT_NAME}-network": {}
              }
            }
          }')
        
        WEB_CONTAINER_ID=\$(echo \$WEB_CREATE_RESPONSE | jq -r '.Id')
        
        if [ "\$WEB_CONTAINER_ID" = "null" ] || [ -z "\$WEB_CONTAINER_ID" ]; then
          echo "Failed to create Web container"
          echo "Response: \$WEB_CREATE_RESPONSE"
          exit 1
        fi
        
        # Start API container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID/start" \
          -H "Authorization: Bearer \$JWT"
        
        # Start Web container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID/start" \
          -H "Authorization: Bearer \$JWT"
        
        echo "Successfully deployed ${PROJECT_NAME} to staging"
        echo "API: http://your-host:5001"
        echo "Web: http://your-host:3001"

  deploy-production:
    needs: [build-api, build-web, deploy-staging]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production
    
    steps:
    - name: Deploy to Portainer (Production)
      run: |
        # Authenticate with Portainer
        AUTH_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{
            "username": "\${{ secrets.PORTAINER_USERNAME }}",
            "password": "\${{ secrets.PORTAINER_PASSWORD }}"
          }')
        
        JWT=\$(echo \$AUTH_RESPONSE | jq -r '.jwt')
        
        if [ "\$JWT" = "null" ] || [ -z "\$JWT" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        # Pull latest API image
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api&tag=latest" \
          -H "Authorization: Bearer \$JWT"
        
        # Pull latest Web image
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-web&tag=latest" \
          -H "Authorization: Bearer \$JWT"
        
        # Stop and remove existing API container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-prod/stop" \
          -H "Authorization: Bearer \$JWT" || true
        
        curl -X DELETE "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-api-prod?force=true" \
          -H "Authorization: Bearer \$JWT" || true
        
        # Stop and remove existing Web container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-web-prod/stop" \
          -H "Authorization: Bearer \$JWT" || true
        
        curl -X DELETE "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/${PROJECT_NAME}-web-prod?force=true" \
          -H "Authorization: Bearer \$JWT" || true
        
        # Create API container
        API_CREATE_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${PROJECT_NAME}-api-prod" \
          -H "Authorization: Bearer \$JWT" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-api:latest",
            "Env": ["ASPNETCORE_ENVIRONMENT=Production"],
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "5000"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            },
            "NetworkingConfig": {
              "EndpointsConfig": {
                "${PROJECT_NAME}-network": {}
              }
            }
          }')
        
        API_CONTAINER_ID=\$(echo \$API_CREATE_RESPONSE | jq -r '.Id')
        
        if [ "\$API_CONTAINER_ID" = "null" ] || [ -z "\$API_CONTAINER_ID" ]; then
          echo "Failed to create API container"
          echo "Response: \$API_CREATE_RESPONSE"
          exit 1
        fi
        
        # Create Web container
        WEB_CREATE_RESPONSE=\$(curl -s -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=${PROJECT_NAME}-web-prod" \
          -H "Authorization: Bearer \$JWT" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "\${{ secrets.DOCKER_USERNAME }}/${PROJECT_NAME}-web:latest",
            "Env": [
              "NODE_ENV=production",
              "API_BASE_URL=http://${PROJECT_NAME}-api-prod"
            ],
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "3000"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            },
            "NetworkingConfig": {
              "EndpointsConfig": {
                "${PROJECT_NAME}-network": {}
              }
            }
          }')
        
        WEB_CONTAINER_ID=\$(echo \$WEB_CREATE_RESPONSE | jq -r '.Id')
        
        if [ "\$WEB_CONTAINER_ID" = "null" ] || [ -z "\$WEB_CONTAINER_ID" ]; then
          echo "Failed to create Web container"
          echo "Response: \$WEB_CREATE_RESPONSE"
          exit 1
        fi
        
        # Start API container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$API_CONTAINER_ID/start" \
          -H "Authorization: Bearer \$JWT"
        
        # Start Web container
        curl -X POST "\${{ secrets.PORTAINER_URL }}/api/endpoints/\${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/\$WEB_CONTAINER_ID/start" \
          -H "Authorization: Bearer \$JWT"
        
        echo "Successfully deployed ${PROJECT_NAME} to production"
        echo "API: http://your-host:5000"
        echo "Web: http://your-host:3000"
EOF
fi

print_success "GitHub Actions workflow generated: .github/workflows/deploy-to-portainer.yml"
echo ""
echo "Workflow details:"
echo "  Project: ${PROJECT_NAME^}"
echo "  Type: $DEPLOYMENT_TYPE"

if [[ "$DEPLOYMENT_TYPE" == "api-only" ]]; then
    echo "  Image name: ${PROJECT_NAME}-api"
    echo "  Staging container: ${PROJECT_NAME}-api-staging (port 5001)"
    echo "  Production container: ${PROJECT_NAME}-api-prod (port 5000)"
    echo ""
    echo "Make sure your project structure matches:"
    echo "  ./${PROJECT_NAME^}/src/${PROJECT_NAME^}.Api/Dockerfile"
else
    echo "  API image: ${PROJECT_NAME}-api"
    echo "  Web image: ${PROJECT_NAME}-web"
    echo "  Staging containers:"
    echo "    - ${PROJECT_NAME}-api-staging (port 5001)"
    echo "    - ${PROJECT_NAME}-web-staging (port 3001)"
    echo "  Production containers:"
    echo "    - ${PROJECT_NAME}-api-prod (port 5000)"
    echo "    - ${PROJECT_NAME}-web-prod (port 3000)"
    echo ""
    echo "Make sure your project structure matches:"
    echo "  ./${PROJECT_NAME^}/src/${PROJECT_NAME^}.Api/Dockerfile"
    echo "  ./${PROJECT_NAME^}/src/${PROJECT_NAME^}.Web/Dockerfile"
fi

echo ""
echo "Required GitHub secrets:"
echo "  - DOCKER_USERNAME"
echo "  - DOCKER_PASSWORD"
echo "  - PORTAINER_URL"
echo "  - PORTAINER_USERNAME"
echo "  - PORTAINER_PASSWORD"
echo "  - PORTAINER_ENDPOINT_ID"
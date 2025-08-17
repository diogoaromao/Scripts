param(
    [string]$SolutionName
)

# Get solution name if not provided
if (-not $SolutionName) {
    $SolutionName = Read-Host "Enter the solution name"
}

# Convert to lowercase and replace spaces/special chars with hyphens
$standardizedName = $SolutionName.ToLower() -replace '[^a-z0-9]', '-'

# Create .github/workflows directory if it doesn't exist
$workflowDir = ".github\workflows"
if (-not (Test-Path $workflowDir)) {
    New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
}

# Generate the workflow YAML content
$workflowContent = @"
name: Deploy $SolutionName

on:
  push:
    branches: [ main, master ]
    paths:
      - '$standardizedName/**'
      - '.github/workflows/**'
  pull_request:
    branches: [ main, master ]
    paths:
      - '$standardizedName/**'
  workflow_dispatch:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: `${{ github.actor }}
        password: `${{ secrets.GITHUB_TOKEN }}

    - name: Build and push API Docker image
      uses: docker/build-push-action@v5
      with:
        context: ./$standardizedName/api
        push: true
        tags: |
          ghcr.io/`${{ github.repository_owner }}/$standardizedName-api:latest
          ghcr.io/`${{ github.repository_owner }}/$standardizedName-api:`${{ github.sha }}

    - name: Build and push Web Docker image
      uses: docker/build-push-action@v5
      with:
        context: ./$standardizedName/web
        push: true
        tags: |
          ghcr.io/`${{ github.repository_owner }}/$standardizedName-web:latest
          ghcr.io/`${{ github.repository_owner }}/$standardizedName-web:`${{ github.sha }}

  deploy-staging:
    needs: build-and-deploy
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master'
    
    steps:
    - name: Deploy API to Staging
      run: |
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/stacks/`${{ secrets.STAGING_API_STACK_ID }}/stop" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X DELETE "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.STAGING_API_CONTAINER_ID }}" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/create" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "ghcr.io/`${{ github.repository_owner }}/$standardizedName-api:latest",
            "Name": "$standardizedName-api-staging",
            "HostConfig": {
              "PortBindings": {
                "80/tcp": [{"HostPort": "`${{ secrets.STAGING_API_PORT }}"}]
              }
            }
          }'
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.STAGING_API_CONTAINER_ID }}/start" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"

    - name: Deploy Web to Staging
      run: |
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/stacks/`${{ secrets.STAGING_WEB_STACK_ID }}/stop" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X DELETE "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.STAGING_WEB_CONTAINER_ID }}" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/create" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "ghcr.io/`${{ github.repository_owner }}/$standardizedName-web:latest",
            "Name": "$standardizedName-web-staging",
            "HostConfig": {
              "PortBindings": {
                "80/tcp": [{"HostPort": "`${{ secrets.STAGING_WEB_PORT }}"}]
              }
            }
          }'
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.STAGING_WEB_CONTAINER_ID }}/start" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"

  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/master'
    environment: production
    
    steps:
    - name: Deploy API to Production
      run: |
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/stacks/`${{ secrets.PROD_API_STACK_ID }}/stop" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X DELETE "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.PROD_API_CONTAINER_ID }}" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/create" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "ghcr.io/`${{ github.repository_owner }}/$standardizedName-api:latest",
            "Name": "$standardizedName-api-prod",
            "HostConfig": {
              "PortBindings": {
                "80/tcp": [{"HostPort": "`${{ secrets.PROD_API_PORT }}"}]
              }
            }
          }'
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.PROD_API_CONTAINER_ID }}/start" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"

    - name: Deploy Web to Production
      run: |
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/stacks/`${{ secrets.PROD_WEB_STACK_ID }}/stop" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X DELETE "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.PROD_WEB_CONTAINER_ID }}" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/create" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "ghcr.io/`${{ github.repository_owner }}/$standardizedName-web:latest",
            "Name": "$standardizedName-web-prod",
            "HostConfig": {
              "PortBindings": {
                "80/tcp": [{"HostPort": "`${{ secrets.PROD_WEB_PORT }}"}]
              }
            }
          }'
        
        curl -X POST "`${{ secrets.PORTAINER_URL }}/api/containers/`${{ secrets.PROD_WEB_CONTAINER_ID }}/start" \
          -H "X-API-Key: `${{ secrets.PORTAINER_API_KEY }}"
"@

# Write the workflow file
$workflowPath = "$workflowDir\deploy.yml"
$workflowContent | Out-File -FilePath $workflowPath -Encoding UTF8

Write-Host "✅ GitHub Actions workflow generated successfully!" -ForegroundColor Green
Write-Host "📁 File created: $workflowPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "📋 Workflow Details:" -ForegroundColor Yellow
Write-Host "   • Solution: $SolutionName" -ForegroundColor White
Write-Host "   • Standardized name: $standardizedName" -ForegroundColor White
Write-Host "   • Triggers: Push to main/master, PR, manual dispatch" -ForegroundColor White
Write-Host "   • Builds: API and Web Docker images" -ForegroundColor White
Write-Host "   • Deploys: Staging → Production" -ForegroundColor White
Write-Host ""
Write-Host "🏗️  Expected project structure:" -ForegroundColor Yellow
Write-Host "   $standardizedName/" -ForegroundColor White
Write-Host "   ├── api/" -ForegroundColor White
Write-Host "   │   └── Dockerfile" -ForegroundColor White
Write-Host "   └── web/" -ForegroundColor White
Write-Host "       └── Dockerfile" -ForegroundColor White
Write-Host ""
Write-Host "🔐 Required GitHub Secrets:" -ForegroundColor Yellow
Write-Host "   • PORTAINER_URL" -ForegroundColor White
Write-Host "   • PORTAINER_API_KEY" -ForegroundColor White
Write-Host "   • STAGING_API_STACK_ID" -ForegroundColor White
Write-Host "   • STAGING_API_CONTAINER_ID" -ForegroundColor White
Write-Host "   • STAGING_API_PORT" -ForegroundColor White
Write-Host "   • STAGING_WEB_STACK_ID" -ForegroundColor White
Write-Host "   • STAGING_WEB_CONTAINER_ID" -ForegroundColor White
Write-Host "   • STAGING_WEB_PORT" -ForegroundColor White
Write-Host "   • PROD_API_STACK_ID" -ForegroundColor White
Write-Host "   • PROD_API_CONTAINER_ID" -ForegroundColor White
Write-Host "   • PROD_API_PORT" -ForegroundColor White
Write-Host "   • PROD_WEB_STACK_ID" -ForegroundColor White
Write-Host "   • PROD_WEB_CONTAINER_ID" -ForegroundColor White
Write-Host "   • PROD_WEB_PORT" -ForegroundColor White
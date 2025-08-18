param(
    [Parameter(Mandatory = $false)]
    [string]$SolutionName
)

# Function to prompt for solution name if not provided
function Get-SolutionName {
    if ([string]::IsNullOrWhiteSpace($SolutionName)) {
        do {
            $SolutionName = Read-Host "Enter the solution name"
        } while ([string]::IsNullOrWhiteSpace($SolutionName))
    }
    return $SolutionName
}

# Get solution name
$SolutionName = Get-SolutionName

Write-Host "Creating solution: $SolutionName" -ForegroundColor Green

# Create solution
Write-Host "Creating .NET solution..." -ForegroundColor Yellow
dotnet new sln --name $SolutionName

# Create src directory
New-Item -ItemType Directory -Path "src" -Force | Out-Null

# Create API project
Write-Host "Creating API project..." -ForegroundColor Yellow
dotnet new webapi -o "src\$SolutionName.Api" -f net9.0 --use-controllers

# Add API project to solution
dotnet sln add "src\$SolutionName.Api\$SolutionName.Api.csproj"

# Create directory structure for API project
$apiPath = "src\$SolutionName.Api"
New-Item -ItemType Directory -Path "$apiPath\Contracts\VideoGames" -Force | Out-Null
New-Item -ItemType Directory -Path "$apiPath\Data" -Force | Out-Null
New-Item -ItemType Directory -Path "$apiPath\Entities" -Force | Out-Null
New-Item -ItemType Directory -Path "$apiPath\Errors\VideoGames" -Force | Out-Null
New-Item -ItemType Directory -Path "$apiPath\Features\VideoGames" -Force | Out-Null

# Install NuGet packages for API
Write-Host "Installing NuGet packages for API..." -ForegroundColor Yellow
Push-Location "src\$SolutionName.Api"

dotnet add package ErrorOr --version 2.0.1
dotnet add package FluentValidation
dotnet add package MediatR
dotnet add package Microsoft.AspNetCore.OpenApi
dotnet add package Microsoft.EntityFrameworkCore.InMemory
dotnet add package Scalar.AspNetCore

Pop-Location

# Update API project file to match target configuration
$apiProjectFile = "src\$SolutionName.Api\$SolutionName.Api.csproj"
$apiProjectContent = @"
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <DockerDefaultTargetOS>Linux</DockerDefaultTargetOS>
    <UserSecretsId>aspnet-$SolutionName.Api-$(New-Guid)</UserSecretsId>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="ErrorOr" Version="2.0.1" />
    <PackageReference Include="FluentValidation" Version="11.9.2" />
    <PackageReference Include="MediatR" Version="12.4.1" />
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="9.0.0" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.InMemory" Version="9.0.0" />
    <PackageReference Include="Scalar.AspNetCore" Version="1.2.49" />
  </ItemGroup>

  <ItemGroup>
    <Folder Include="Shared\" />
  </ItemGroup>

</Project>
"@

Set-Content -Path $apiProjectFile -Value $apiProjectContent

# Create additional appsettings files
$apiSettingsPath = "src\$SolutionName.Api"
$developmentSettings = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  }
}
"@

$productionSettings = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  }
}
"@

$stagingSettings = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  }
}
"@

Set-Content -Path "$apiSettingsPath\appsettings.Development.json" -Value $developmentSettings
Set-Content -Path "$apiSettingsPath\appsettings.Production.json" -Value $productionSettings
Set-Content -Path "$apiSettingsPath\appsettings.Staging.json" -Value $stagingSettings

# Create Dockerfile for API
$dockerfileContent = @"
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["src/$SolutionName.Api/$SolutionName.Api.csproj", "src/$SolutionName.Api/"]
RUN dotnet restore "./src/$SolutionName.Api/$SolutionName.Api.csproj"
COPY . .
WORKDIR "/src/src/$SolutionName.Api"
RUN dotnet build "./$SolutionName.Api.csproj" -c `$BUILD_CONFIGURATION -o /app/build

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./$SolutionName.Api.csproj" -c `$BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "$SolutionName.Api.dll"]
"@

Set-Content -Path "$apiPath\Dockerfile.api" -Value $dockerfileContent

# Create Vue.js web project
Write-Host "Creating Vue.js web project..." -ForegroundColor Yellow
Push-Location "src"

# Check if npm is available
if (Get-Command npm -ErrorAction SilentlyContinue) {
    # Create Vue.js project with basic setup
    npm create vue@latest "$($SolutionName.ToLower()).web" -- --typescript --router --vitest --cypress --eslint --prettier
    
    # Install dependencies if project was created successfully
    if (Test-Path "$($SolutionName.ToLower()).web") {
        Push-Location "$($SolutionName.ToLower()).web"
        npm install
        Pop-Location
    }
} else {
    Write-Warning "npm not found. Please install Node.js and npm, then run 'npm create vue@latest $($SolutionName.ToLower()).web' in the src directory"
    
    # Create basic directory structure for web project
    New-Item -ItemType Directory -Path "$($SolutionName.ToLower()).web" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($SolutionName.ToLower()).web\src" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($SolutionName.ToLower()).web\public" -Force | Out-Null
    New-Item -ItemType Directory -Path "$($SolutionName.ToLower()).web\.vscode" -Force | Out-Null
}

Pop-Location

# Create tests directory (empty as in original)
New-Item -ItemType Directory -Path "tests" -Force | Out-Null

# Create .github/workflows directory
New-Item -ItemType Directory -Path ".github\workflows" -Force | Out-Null

# Create .idea directory structure (JetBrains Rider)
New-Item -ItemType Directory -Path ".idea\.idea.$SolutionName\.idea" -Force | Out-Null

Write-Host "Solution '$SolutionName' created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Project Structure:" -ForegroundColor Cyan
Write-Host "  $SolutionName.sln"
Write-Host "  src/"
Write-Host "    $SolutionName.Api/ (ASP.NET Core Web API)"
Write-Host "    $($SolutionName.ToLower()).web/ (Vue.js application)"
Write-Host "  tests/ (empty, ready for test projects)"
Write-Host "  .github/workflows/ (ready for CI/CD)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open the solution in your IDE"
Write-Host "  2. Build the solution: dotnet build"
Write-Host "  3. Run the API: dotnet run --project src\$SolutionName.Api"
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "  4. Run the web app: cd src\$($SolutionName.ToLower()).web && npm run dev"
} else {
    Write-Host "  4. Install Node.js/npm and set up the Vue.js project in src\$($SolutionName.ToLower()).web"
}
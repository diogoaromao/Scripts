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

# Create actual INAB example files

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

# Remove default template files
Remove-Item "$apiPath\Controllers" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$apiPath\WeatherForecast.cs" -Force -ErrorAction SilentlyContinue
Remove-Item "$apiPath\$SolutionName.Api.http" -Force -ErrorAction SilentlyContinue

# Create specific INAB-style Program.cs
$programContent = @"
using FluentValidation;
using $SolutionName.Api.Data;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

builder.Services.AddDbContext<VideoGameDbContext>(options =>
    options.UseInMemoryDatabase("VideoGameDb"));

var assembly = typeof(Program).Assembly;

builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));
builder.Services.AddValidatorsFromAssembly(assembly);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();

app.Run();
"@

Set-Content -Path "$apiPath\Program.cs" -Value $programContent

# Create VideoGame entity
$videoGameEntityContent = @"
namespace $SolutionName.Api.Entities;

public class VideoGame
{
    public int Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Genre { get; set; } = string.Empty;
    public int ReleaseYear { get; set; }
}
"@

Set-Content -Path "$apiPath\Entities\VideoGame.cs" -Value $videoGameEntityContent

# Create VideoGameDbContext
$dbContextContent = @"
using $SolutionName.Api.Entities;
using Microsoft.EntityFrameworkCore;

namespace $SolutionName.Api.Data;

public class VideoGameDbContext : DbContext
{
    public VideoGameDbContext(DbContextOptions<VideoGameDbContext> options) : base(options)
    {
        
    }
    
    public DbSet<VideoGame> VideoGames { get; set; }
}
"@

Set-Content -Path "$apiPath\Data\VideoGameDbContext.cs" -Value $dbContextContent

# Create CreateVideoGameRequest contract
$createRequestContent = @"
namespace $SolutionName.Api.Contracts.VideoGames;

public record CreateVideoGameRequest(string Title, string Genre, int ReleaseYear);
"@

Set-Content -Path "$apiPath\Contracts\VideoGames\CreateVideoGameRequest.cs" -Value $createRequestContent

# Create VideoGameErrors
$videoGameErrorsContent = @"
using ErrorOr;

namespace $SolutionName.Api.Errors.VideoGames;

public static class VideoGameErrors
{
    public static Error NotFound =>
        Error.NotFound(
            code: "VideoGame.NotFound",
            description: "The requested video game was not found.");
}
"@

Set-Content -Path "$apiPath\Errors\VideoGames\VideoGameErrors.cs" -Value $videoGameErrorsContent

# Create CreateVideoGame feature
$createVideoGameContent = @"
using ErrorOr;
using FluentValidation;
using $SolutionName.Api.Contracts.VideoGames;
using $SolutionName.Api.Data;
using $SolutionName.Api.Entities;
using MediatR;
using Microsoft.AspNetCore.Mvc;

namespace $SolutionName.Api.Features.VideoGames;

public static class CreateVideoGame
{
    public record Command(string Title, string Genre, int ReleaseYear) : IRequest<ErrorOr<Response>>;

    public class Validator : AbstractValidator<Command>
    {
        public Validator()
        {
            RuleFor(x => x.Title).NotEmpty();
            RuleFor(x => x.Genre).NotEmpty();
            RuleFor(x => x.ReleaseYear).GreaterThanOrEqualTo(1900);
        }
    }
    
    public record Response(int Id, string Title, string Genre, int ReleaseYear);

    public class Handler(VideoGameDbContext context, IValidator<Command> validator) : IRequestHandler<Command, ErrorOr<Response>>
    {
        public async Task<ErrorOr<Response>> Handle(Command request, CancellationToken cancellationToken)
        {
            var validationResult = validator.Validate(request);
            if (!validationResult.IsValid)
            {
                return Error.Validation(code: "CreateVideoGame.Validation",
                    string.Join(", ",
                        validationResult.Errors.Select(x => x.ErrorMessage)));
            }
            
            var videoGame = new VideoGame
            {
                Title = request.Title,
                Genre = request.Genre,
                ReleaseYear = request.ReleaseYear
            };
            
            context.VideoGames.Add(videoGame);
            await context.SaveChangesAsync(cancellationToken);

            var response = new Response(videoGame.Id,
                videoGame.Title,
                videoGame.Genre,
                videoGame.ReleaseYear);

            return response;
        }
    }
}
"@

Set-Content -Path "$apiPath\Features\VideoGames\CreateVideoGame.cs" -Value $createVideoGameContent

# Create GetAllVideoGames feature
$getAllVideoGamesContent = @"
using $SolutionName.Api.Data;
using MediatR;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace $SolutionName.Api.Features.VideoGames;

public static class GetAllVideoGames
{
    public record Query : IRequest<IEnumerable<Response>>;
    
    public record Response(int Id, string Title, string Genre, int ReleaseYear);

    public class Handler(VideoGameDbContext context) : IRequestHandler<Query, IEnumerable<Response>>
    {
        public async Task<IEnumerable<Response>> Handle(Query request, CancellationToken cancellationToken)
        {
            var videoGames = await context.VideoGames.ToListAsync(cancellationToken);
            return videoGames.Select(vg => new Response(vg.Id, vg.Title, vg.Genre, vg.ReleaseYear));
        }
    }
}

[ApiController]
[Route("api/games")]
public class GetAllVideoGamesController(ISender sender) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<GetAllVideoGames.Response>> GetAllVideoGames()
    {
        var response = await sender.Send(new GetAllVideoGames.Query());
        return Ok(response);
    }
}
"@

Set-Content -Path "$apiPath\Features\VideoGames\GetAllVideoGames.cs" -Value $getAllVideoGamesContent

# Create Properties/launchSettings.json
$launchSettingsContent = @"
{
  "profiles": {
    "http": {
      "commandName": "Project",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      },
      "dotnetRunMessages": true,
      "applicationUrl": "http://localhost:5233"
    },
    "https": {
      "commandName": "Project",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      },
      "launchBrowser": true,
      "launchUrl": "scalar",
      "dotnetRunMessages": true,
      "applicationUrl": "https://localhost:7072;http://localhost:5233"
    },
    "Container (Dockerfile)": {
      "commandName": "Docker",
      "launchUrl": "{Scheme}://{ServiceHost}:{ServicePort}",
      "environmentVariables": {
        "ASPNETCORE_HTTPS_PORTS": "8081",
        "ASPNETCORE_HTTP_PORTS": "8080"
      },
      "publishAllPorts": true,
      "useSSL": true
    }
  },
  "`$schema": "https://json.schemastore.org/launchsettings.json"
}
"@

Set-Content -Path "$apiPath\Properties\launchSettings.json" -Value $launchSettingsContent

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
# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
USER `$APP_UID
WORKDIR /app
EXPOSE 8080
EXPOSE 8081


# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["src/$SolutionName.Api/$SolutionName.Api.csproj", "src/$SolutionName.Api/"]
RUN dotnet restore "./src/$SolutionName.Api/$SolutionName.Api.csproj"
COPY . .
WORKDIR "/src/src/$SolutionName.Api"
RUN dotnet build "./$SolutionName.Api.csproj" -c `$BUILD_CONFIGURATION -o /app/build

# This stage is used to publish the service project to be copied to the final stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./$SolutionName.Api.csproj" -c `$BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# This stage is used in production or when running from VS in regular mode (Default when not using the Debug configuration)
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
    # Create Vue.js project with basic setup (JavaScript, not TypeScript)
    npm create vue@latest "$($SolutionName.ToLower()).web" -- --router --vitest --eslint
    
    # Install dependencies if project was created successfully
    if (Test-Path "$($SolutionName.ToLower()).web") {
        Push-Location "$($SolutionName.ToLower()).web"
        npm install
        
        # Override vite.config.js with INAB-style configuration
        $viteConfig = @"
import { defineConfig } from 'vite';
import plugin from '@vitejs/plugin-vue';

// https://vitejs.dev/config/
export default defineConfig({
    plugins: [plugin()],
    server: {
        port: 58241,
    }
})
"@
        Set-Content -Path "vite.config.js" -Value $viteConfig
        
        # Override jsconfig.json with INAB-style configuration
        $jsConfig = @"
{
  "compilerOptions": {
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "exclude": ["node_modules", "dist"]
}
"@
        Set-Content -Path "jsconfig.json" -Value $jsConfig
        
        # Remove cypress folder if it was created
        Remove-Item "cypress" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Remove any TypeScript files and replace with JavaScript equivalents if needed
        # Remove TypeScript config files that might have been created
        Remove-Item "tsconfig.json" -Force -ErrorAction SilentlyContinue
        Remove-Item "tsconfig.app.json" -Force -ErrorAction SilentlyContinue
        Remove-Item "tsconfig.node.json" -Force -ErrorAction SilentlyContinue
        
        # Convert any .ts files to .js files in src directory
        Get-ChildItem -Path "src" -Filter "*.ts" -Recurse | ForEach-Object {
            $jsFile = $_.FullName -replace '\.ts$', '.js'
            Move-Item $_.FullName $jsFile -Force
        }
        
        # Ensure index.html has correct content
        $indexHtmlContent = @"
<!DOCTYPE html>
<html lang="">
  <head>
    <meta charset="UTF-8">
    <link rel="icon" href="/favicon.ico">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vite App</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.js"></script>
  </body>
</html>
"@
        Set-Content -Path "index.html" -Value $indexHtmlContent
        
        # Ensure main.js has correct content
        $mainJsContent = @"
import './assets/main.css'

import { createApp } from 'vue'
import App from './App.vue'

createApp(App).mount('#app')
"@
        Set-Content -Path "src\main.js" -Value $mainJsContent
        
        # Ensure App.vue has correct content
        $appVueContent = @"
<script setup>
import HelloWorld from './components/HelloWorld.vue'
import TheWelcome from './components/TheWelcome.vue'
</script>

<template>
  <header>
    <img alt="Vue logo" class="logo" src="./assets/logo.svg" width="125" height="125" />

    <div class="wrapper">
      <HelloWorld msg="You did it!" />
    </div>
  </header>

  <main>
    <TheWelcome />
  </main>
</template>

<style scoped>
header {
  line-height: 1.5;
}

.logo {
  display: block;
  margin: 0 auto 2rem;
}

@media (min-width: 1024px) {
  header {
    display: flex;
    place-items: center;
    padding-right: calc(var(--section-gap) / 2);
  }

  .logo {
    margin: 0 2rem 0 0;
  }

  header .wrapper {
    display: flex;
    place-items: flex-start;
    flex-wrap: wrap;
  }
}
</style>
"@
        Set-Content -Path "src\App.vue" -Value $appVueContent
        
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

# Add Vue.js web project to solution if it was created successfully
$webProjectName = "$($SolutionName.ToLower()).web"
if (Test-Path "src\$webProjectName") {
    Write-Host "Adding web project to solution..." -ForegroundColor Yellow
    
    # Create .esproj file for Visual Studio integration
    $webProjectContent = @"
<Project Sdk="Microsoft.VisualStudio.JavaScript.Sdk/1.0.2752196">
  <PropertyGroup>
    <StartupCommand>npm run dev</StartupCommand>
    <JavaScriptTestRoot>.\</JavaScriptTestRoot>
    <JavaScriptTestFramework>Vitest</JavaScriptTestFramework>
    <!-- Allows the build (or compile) script located on package.json to run on Build -->
    <ShouldRunBuildScript>false</ShouldRunBuildScript>
    <!-- Folder where production build objects will be placed -->
    <BuildOutputFolder>`$(MSBuildProjectDirectory)\dist</BuildOutputFolder>
  </PropertyGroup>
</Project>
"@
    
    Set-Content -Path "src\$webProjectName\$webProjectName.esproj" -Value $webProjectContent
    
    # Create Dockerfile.web for the web project
    $webDockerfileContent = @"
# Web-only Dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --no-cache
COPY . .
RUN npm run build

FROM nginx:alpine AS final
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
"@
    
    Set-Content -Path "src\$webProjectName\Dockerfile.web" -Value $webDockerfileContent
    
    # Add to solution using .esproj extension
    dotnet sln add "src\$webProjectName\$webProjectName.esproj"
}

# Create tests directory (empty as in original)
New-Item -ItemType Directory -Path "tests" -Force | Out-Null

# Add tests folder to solution as a solution folder
Write-Host "Adding tests folder to solution..." -ForegroundColor Yellow
# Create a temporary placeholder file to add the solution folder
$tempFile = "tests\.placeholder"
Set-Content -Path $tempFile -Value ""
dotnet sln add $tempFile --solution-folder tests
Remove-Item $tempFile -Force

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
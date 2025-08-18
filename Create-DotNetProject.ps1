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
dotnet add package FluentValidation.DependencyInjectionExtensions --version 12.0.0
dotnet add package MediatR --version 12.5.0
dotnet add package Microsoft.AspNetCore.OpenApi --version 9.0.8
dotnet add package Microsoft.EntityFrameworkCore --version 9.0.8
dotnet add package Microsoft.EntityFrameworkCore.InMemory --version 9.0.8
dotnet add package Microsoft.EntityFrameworkCore.Tools --version 9.0.8
dotnet add package Microsoft.VisualStudio.Azure.Containers.Tools.Targets --version 1.22.1
dotnet add package Scalar.AspNetCore --version 2.6.9

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

[ApiController]
[Route("api/games")]
public class CreateVideoGameController(ISender sender) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> CreateVideoGame([FromBody] CreateVideoGameRequest request)
    {
        var command = new CreateVideoGame.Command(request.Title, request.Genre, request.ReleaseYear);
        
        var result = await sender.Send(command);

        return result.Match<IActionResult>(
            response => Created(`$"/api/games/{response.Id}", response),
            errors => BadRequest(errors));
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
    <UserSecretsId>57dac3bf-fec9-4a6a-a44d-e48497a5ccfb</UserSecretsId>
    <DockerDefaultTargetOS>Linux</DockerDefaultTargetOS>
    <DockerfileContext>..\..</DockerfileContext>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="ErrorOr" Version="2.0.1" />
    <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="12.0.0" />
    <PackageReference Include="MediatR" Version="12.5.0" />
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="9.0.8" />
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="9.0.8" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.InMemory" Version="9.0.8" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Tools" Version="9.0.8">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    </PackageReference>
    <PackageReference Include="Microsoft.VisualStudio.Azure.Containers.Tools.Targets" Version="1.22.1" />
    <PackageReference Include="Scalar.AspNetCore" Version="2.6.9" />
  </ItemGroup>

  <ItemGroup>
    <Content Update="appsettings.Development.json">
      <DependentUpon>appsettings.json</DependentUpon>
    </Content>
    <Content Update="appsettings.Production.json">
      <DependentUpon>appsettings.json</DependentUpon>
    </Content>
    <Content Update="appsettings.Staging.json">
      <DependentUpon>appsettings.json</DependentUpon>
    </Content>
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
        
        # Create HelloWorld component
        $helloWorldContent = @"
<script setup>
defineProps({
  msg: {
    type: String,
    required: true,
  },
})
</script>

<template>
  <div class="greetings">
    <h1 class="green">{{ msg }}</h1>
    <h3>
      You've successfully created a project with
      <a href="https://vite.dev/" target="_blank" rel="noopener">Vite</a> +
      <a href="https://vuejs.org/" target="_blank" rel="noopener">Vue 3</a>.
    </h3>
  </div>
</template>

<style scoped>
h1 {
  font-weight: 500;
  font-size: 2.6rem;
  position: relative;
  top: -10px;
}

h3 {
  font-size: 1.2rem;
}

.greetings h1,
.greetings h3 {
  text-align: center;
}

@media (min-width: 1024px) {
  .greetings h1,
  .greetings h3 {
    text-align: left;
  }
}
</style>
"@
        New-Item -ItemType Directory -Path "src\components" -Force | Out-Null
        Set-Content -Path "src\components\HelloWorld.vue" -Value $helloWorldContent
        
        # Create WelcomeItem component
        $welcomeItemContent = @"
<template>
  <div class="item">
    <i>
      <slot name="icon"></slot>
    </i>
    <div class="details">
      <h3>
        <slot name="heading"></slot>
      </h3>
      <slot></slot>
    </div>
  </div>
</template>

<style scoped>
.item {
  margin-top: 2rem;
  display: flex;
  position: relative;
}

.details {
  flex: 1;
  margin-left: 1rem;
}

i {
  display: flex;
  place-items: center;
  place-content: center;
  width: 32px;
  height: 32px;

  color: var(--color-text);
}

h3 {
  font-size: 1.2rem;
  font-weight: 500;
  margin-bottom: 0.4rem;
  color: var(--color-heading);
}

@media (min-width: 1024px) {
  .item {
    margin-top: 0;
    padding: 0.4rem 0 1rem calc(var(--section-gap) / 2);
  }

  i {
    top: calc(50% - 25px);
    left: -26px;
    position: absolute;
    border: 1px solid var(--color-border);
    background: var(--color-background);
    border-radius: 8px;
    width: 50px;
    height: 50px;
  }

  .item:before {
    content: ' ';
    border-left: 1px solid var(--color-border);
    position: absolute;
    left: 0;
    bottom: calc(50% + 25px);
    height: calc(50% - 25px);
  }

  .item:after {
    content: ' ';
    border-left: 1px solid var(--color-border);
    position: absolute;
    left: 0;
    top: calc(50% + 25px);
    height: calc(50% - 25px);
  }

  .item:first-of-type:before {
    display: none;
  }

  .item:last-of-type:after {
    display: none;
  }
}
</style>
"@
        Set-Content -Path "src\components\WelcomeItem.vue" -Value $welcomeItemContent
        
        # Create TheWelcome component
        $theWelcomeContent = @"
<script setup>
import WelcomeItem from './WelcomeItem.vue'
import DocumentationIcon from './icons/IconDocumentation.vue'
import ToolingIcon from './icons/IconTooling.vue'
import EcosystemIcon from './icons/IconEcosystem.vue'
import CommunityIcon from './icons/IconCommunity.vue'
import SupportIcon from './icons/IconSupport.vue'
</script>

<template>
  <WelcomeItem>
    <template #icon>
      <DocumentationIcon />
    </template>
    <template #heading>Documentation</template>

    Vue's
    <a href="https://vuejs.org/" target="_blank" rel="noopener">official documentation</a>
    provides you with all information you need to get started.
  </WelcomeItem>

  <WelcomeItem>
    <template #icon>
      <ToolingIcon />
    </template>
    <template #heading>Tooling</template>

    This project is served and bundled with
    <a href="https://vite.dev/guide/features.html" target="_blank" rel="noopener">Vite</a>. The
    recommended IDE setup is
    <a href="https://code.visualstudio.com/" target="_blank" rel="noopener">VSCode</a>
    +
    <a href="https://github.com/vuejs/language-tools" target="_blank" rel="noopener">Vue - Official</a>. If
    you need to test your components and web pages, check out
    <a href="https://vitest.dev/" target="_blank" rel="noopener">Vitest</a>
    and
    <a href="https://www.cypress.io/" target="_blank" rel="noopener">Cypress</a>
    /
    <a href="https://playwright.dev/" target="_blank" rel="noopener">Playwright</a>.

    More instructions are available in <code>README.md</code>.
  </WelcomeItem>

  <WelcomeItem>
    <template #icon>
      <EcosystemIcon />
    </template>
    <template #heading>Ecosystem</template>

    Get official tools and libraries for your project:
    <a href="https://pinia.vuejs.org/" target="_blank" rel="noopener">Pinia</a>,
    <a href="https://router.vuejs.org/" target="_blank" rel="noopener">Vue Router</a>,
    <a href="https://test-utils.vuejs.org/" target="_blank" rel="noopener">Vue Test Utils</a>,
    and
    <a href="https://github.com/vuejs/devtools" target="_blank" rel="noopener">Vue Dev Tools</a>. If
    you need more resources, we suggest paying
    <a href="https://github.com/vuejs/awesome-vue" target="_blank" rel="noopener">Awesome Vue</a> a visit.
  </WelcomeItem>

  <WelcomeItem>
    <template #icon>
      <CommunityIcon />
    </template>
    <template #heading>Community</template>

    Got stuck? Ask your question on
    <a href="https://chat.vuejs.org" target="_blank" rel="noopener">Vue Land</a>, our official Discord server, or
    <a href="https://stackoverflow.com/questions/tagged/vue.js" target="_blank" rel="noopener">StackOverflow</a>. You should also subscribe to
    <a href="https://news.vuejs.org" target="_blank" rel="noopener">our mailing list</a>
    and follow the official
    <a href="https://twitter.com/vuejs" target="_blank" rel="noopener">@vuejs</a>
    twitter account for latest news in the Vue world.
  </WelcomeItem>

  <WelcomeItem>
    <template #icon>
      <SupportIcon />
    </template>
    <template #heading>Support Vue</template>

    As an independent project, Vue relies on community backing for its sustainability. You can help us by
    <a href="https://vuejs.org/sponsor/" target="_blank" rel="noopener">becoming a sponsor</a>.
  </WelcomeItem>
</template>
"@
        Set-Content -Path "src\components\TheWelcome.vue" -Value $theWelcomeContent
        
        # Create icons directory and components
        New-Item -ItemType Directory -Path "src\components\icons" -Force | Out-Null
        
        # Create IconDocumentation
        $iconDocumentationContent = @"
<template>
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="17" fill="currentColor">
    <path
      d="M11 2.253a1 1 0 1 0-2 0h2zm-2 13.5a1 1 0 1 0 2 0h-2zm.447-12.53a1 1 0 1 0 1.107-1.666L9.447 2.777zM1 5.253V4.253h1v1H1zm18 0V4.253h1v1h-1zm-1.553.895a1 1 0 1 0 1.107 1.666l-1.107-1.666zM3.553 6.148a1 1 0 1 0-1.107-1.666L3.553 6.148zM2 6.253l8.447-.895 1.107 1.666L3.107 7.919 2 6.253zm7.447 9.342L18 14.7l1.107 1.666-8.553.895-1.107-1.666zm0-13.79a9.97 9.97 0 0 0-2.828.828L5.17 4.09a11.97 11.97 0 0 1 3.4-.998L9.447 2.22zm-2.828.828A9.95 9.95 0 0 0 4.65 4.65l-1.437-1.437a11.95 11.95 0 0 1 2.29-2.29L6.619 3.633zm-1.969 2.017A9.94 9.94 0 0 0 1.828 8.45L.172 7.55a11.94 11.94 0 0 1 1-3.622L4.65 4.65zM1.828 8.45a9.972 9.972 0 0 0-.172 1.8H.253a11.972 11.972 0 0 1 .207-2.168L1.828 8.45zm-.172 1.8a9.966 9.966 0 0 0 .172 1.8L.46 13.05a11.966 11.966 0 0 1-.207-2.168H1.656zm.172 1.8a9.94 9.94 0 0 0 .828 1.822L1.388 15.31a11.94 11.94 0 0 1-1-3.622L2.656 12.05zm.828 1.822a9.95 9.95 0 0 0 1.969 1.969l-1.437 1.437a11.95 11.95 0 0 1-2.29-2.29L3.484 13.872zm1.969 1.969a9.978 9.978 0 0 0 2.828.828L8.172 15.67a11.978 11.978 0 0 1-3.4-.998L5.453 15.841zm2.828.828a9.972 9.972 0 0 0 1.8.172V18.25a11.972 11.972 0 0 1-2.168-.207L9.281 16.669zm1.8.172a9.966 9.966 0 0 0 1.8-.172l.999 1.374a11.966 11.966 0 0 1-2.168.207V16.841zm1.8-.172a9.97 9.97 0 0 0 2.828-.828l1.72 1.169a11.97 11.97 0 0 1-3.4.998L12.081 16.669zm2.828-.828a9.95 9.95 0 0 0 1.969-1.969l1.437 1.437a11.95 11.95 0 0 1-2.29 2.29L14.85 15.841zm1.969-1.969a9.94 9.94 0 0 0 .828-1.822L18.612 13.05a11.94 11.94 0 0 1-1 3.622L16.819 13.872zm.828-1.822a9.966 9.966 0 0 0 .172-1.8H18.25a11.966 11.966 0 0 1-.207 2.168L17.647 12.05zm.172-1.8a9.972 9.972 0 0 0-.172-1.8L18.54 7.45a11.972 11.972 0 0 1 .207 2.168H17.819zm-.172-1.8a9.94 9.94 0 0 0-.828-1.822L17.612 4.09a11.94 11.94 0 0 1 1 3.622L16.819 8.45zm-.828-1.822a9.95 9.95 0 0 0-1.969-1.969l1.437-1.437a11.95 11.95 0 0 1 2.29 2.29L14.85 3.159z"
    />
  </svg>
</template>
"@
        Set-Content -Path "src\components\icons\IconDocumentation.vue" -Value $iconDocumentationContent
        
        # Create IconTooling
        $iconToolingContent = @"
<template>
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="currentColor">
    <path
      d="M10 3.22l-.61-.6a5.5 5.5 0 0 0-7.666.105 5.5 5.5 0 0 0-.114 7.665L10 18.78l8.39-8.4a5.5 5.5 0 0 0-.114-7.665 5.5 5.5 0 0 0-7.666-.105l-.61.61z"
    />
  </svg>
</template>
"@
        Set-Content -Path "src\components\icons\IconTooling.vue" -Value $iconToolingContent
        
        # Create IconEcosystem
        $iconEcosystemContent = @"
<template>
  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="20" fill="currentColor">
    <path
      d="M11.447 8.894a1 1 0 1 0-.894-1.789l.894 1.789zm-2.894-.789a1 1 0 1 0 .894 1.789l-.894-1.789zm0 1.789a1 1 0 1 0 .894-1.789l-.894 1.789zM7.447 7.106a1 1 0 1 0-.894 1.789l.894-1.789zM10 9a1 1 0 1 0 0 2v-2zm-9.447-1.106a1 1 0 1 0-.894-1.789l.894 1.789zm2.894-.789a1 1 0 1 0 .894 1.789l-.894-1.789zm2 .5a1 1 0 1 0 .894-1.789l-.894 1.789zm0 1.789a1 1 0 1 0 .894-1.789l-.894 1.789zm-2-.789a1 1 0 1 0 .894 1.789l-.894-1.789zm2.894-.789a1 1 0 1 0-.894 1.789l.894-1.789zm-2 .5a1 1 0 1 0 .894-1.789l-.894 1.789zM8.553 11.106a1 1 0 1 0 .894-1.789l-.894 1.789zm4.894-1.789a1 1 0 1 0 .894 1.789l-.894-1.789zM9 10a1 1 0 1 0 0 2v-2zm-7.447.894a1 1 0 1 0 .894-1.789l-.894 1.789zM15 9a1 1 0 1 0 0 2v-2zm2.447.894a1 1 0 1 0-.894-1.789l.894 1.789zm-10-1.789l.894 1.789.894-1.789-.894-1.789-.894 1.789zm.894-1.789L9 5.553l.894 1.789L9 9.105l-.894-1.789zm0 1.789l-.894 1.789-.894-1.789.894-1.789.894 1.789zm-.894 1.789L7.553 11.106 8.447 9.317l.894 1.789-.894 1.789zm.894-1.789l.894-1.789-.894-1.789-.894 1.789.894 1.789zm.894-1.789L10 7.553l-.894-1.789L8.212 7.553l.894 1.789zM10 7.553l-.894 1.789.894 1.789.894-1.789L10 7.553zM9.106 9L9 8.447 8.447 9l.553.553L9.106 9zM1 9l.894 1.789L3.683 9l-.894-1.789L1 9zm8.894 0L9 9.553 9.553 11l.894-1.553L9.894 9zm.553.553l.894 1.789.894-1.789-.894-1.789-.894 1.789zm.894 1.789l.894-1.789-.894-1.789-.894 1.789.894 1.789zM17 9l-.894 1.789.894 1.789.894-1.789L17 9zm-4.553-.553L13 9l.553.553-.553.553L12.447 8.447z"
    />
  </svg>
</template>
"@
        Set-Content -Path "src\components\icons\IconEcosystem.vue" -Value $iconEcosystemContent
        
        # Create IconCommunity
        $iconCommunityContent = @"
<template>
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="currentColor">
    <path
      d="M15 4a1 1 0 1 0 0 2V4zm0 11v-1a1 1 0 0 0-1 1h1zm0 4l-.707.707A1 1 0 0 0 16 19.414L15 18.414l-1.414 1.414A1 1 0 0 0 15 18.414V19zm1.414-2.414L15 18.414v-.828l1.414-1.414zm0-11.172L15 4.586V5.414l1.414 1.414zm-8.828 0L9 7.414V6.586l-1.414-1.414zm8.828 8.828L15 16.414v-.828l1.414-1.414zM9 7.414l1.414-1.414L9 4.586V7.414zM5 4a1 1 0 1 0 0 2V4zm0 11v-1a1 1 0 0 0-1 1h1zm0 4l-.707.707A1 1 0 0 0 6 19.414L5 18.414l-1.414 1.414A1 1 0 0 0 5 18.414V19zm1.414-2.414L5 18.414v-.828l1.414-1.414zm0-11.172L5 4.586V5.414l1.414 1.414zm-2.828 0L5 7.414V6.586L3.586 5.172zm2.828 8.828L5 16.414v-.828l1.414-1.414zM3 7.414l1.414-1.414L3 4.586V7.414z"
    />
  </svg>
</template>
"@
        Set-Content -Path "src\components\icons\IconCommunity.vue" -Value $iconCommunityContent
        
        # Create IconSupport
        $iconSupportContent = @"
<template>
  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" fill="currentColor">
    <path
      d="M10 10a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 8a2 2 0 1 1-4 0 2 2 0 0 1 4 0zM1.49 15.326a.78.78 0 0 1-.358-.442 3 3 0 0 1 4.308-3.516 6.484 6.484 0 0 0-1.905 3.959c-.023.222-.014.442.025.654a4.97 4.97 0 0 1-2.07-.655zM16.44 15.98a4.97 4.97 0 0 1-2.07.654.78.78 0 0 1 .357-.442 3 3 0 0 1 4.308-3.516 6.484 6.484 0 0 0-1.905 3.959c-.023.222-.014.442.025.654-.23-.02-.45-.032-.715-.309zM18 8a2 2 0 1 1-4 0 2 2 0 0 1 4 0zM5.304 16.19a.844.844 0 0 1-.277-.71 5 5 0 0 1 9.947 0 .843.843 0 0 1-.277.71A6.975 6.975 0 0 1 10 18a6.974 6.974 0 0 1-4.696-1.81z"
    />
  </svg>
</template>
"@
        Set-Content -Path "src\components\icons\IconSupport.vue" -Value $iconSupportContent
        
        # Create assets directory and CSS files
        New-Item -ItemType Directory -Path "src\assets" -Force | Out-Null
        
        # Create base.css
        $baseCssContent = @"
/* color palette from <https://github.com/vuejs/theme> */
:root {
  --vt-c-white: #ffffff;
  --vt-c-white-soft: #f8f8f8;
  --vt-c-white-mute: #f2f2f2;

  --vt-c-black: #181818;
  --vt-c-black-soft: #222222;
  --vt-c-black-mute: #282828;

  --vt-c-indigo: #2c3e50;

  --vt-c-divider-light-1: rgba(60, 60, 60, 0.29);
  --vt-c-divider-light-2: rgba(60, 60, 60, 0.12);
  --vt-c-divider-dark-1: rgba(84, 84, 84, 0.65);
  --vt-c-divider-dark-2: rgba(84, 84, 84, 0.48);

  --vt-c-text-light-1: var(--vt-c-indigo);
  --vt-c-text-light-2: rgba(60, 60, 60, 0.66);
  --vt-c-text-dark-1: var(--vt-c-white);
  --vt-c-text-dark-2: rgba(235, 235, 235, 0.64);
}

/* semantic color variables for this project */
:root {
  --color-background: var(--vt-c-white);
  --color-background-soft: var(--vt-c-white-soft);
  --color-background-mute: var(--vt-c-white-mute);

  --color-border: var(--vt-c-divider-light-2);
  --color-border-hover: var(--vt-c-divider-light-1);

  --color-heading: var(--vt-c-text-light-1);
  --color-text: var(--vt-c-text-light-1);
}

@media (prefers-color-scheme: dark) {
  :root {
    --color-background: var(--vt-c-black);
    --color-background-soft: var(--vt-c-black-soft);
    --color-background-mute: var(--vt-c-black-mute);

    --color-border: var(--vt-c-divider-dark-2);
    --color-border-hover: var(--vt-c-divider-dark-1);

    --color-heading: var(--vt-c-text-dark-1);
    --color-text: var(--vt-c-text-dark-2);
  }
}

*,
*::before,
*::after {
  box-sizing: border-box;
  margin: 0;
  font-weight: normal;
}

body {
  min-height: 100vh;
  color: var(--color-text);
  background: var(--color-background);
  transition: color 0.5s, background-color 0.5s;
  line-height: 1.6;
  font-family: Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
  font-size: 15px;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
"@
        Set-Content -Path "src\assets\base.css" -Value $baseCssContent
        
        # Create main.css
        $mainCssContent = @"
@import './base.css';

#app {
  max-width: 1280px;
  margin: 0 auto;
  padding: 2rem;
  font-weight: normal;
}

a,
.green {
  text-decoration: none;
  color: hsla(160, 100%, 37%, 1);
  transition: 0.4s;
  padding: 3px;
}

@media (hover: hover) {
  a:hover {
    background-color: hsla(160, 100%, 37%, 0.2);
  }
}

@media (min-width: 1024px) {
  body {
    display: flex;
    place-items: center;
  }

  #app {
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 0 2rem;
  }
}
"@
        Set-Content -Path "src\assets\main.css" -Value $mainCssContent
        
        # Create configuration files
        $editorConfigContent = @"
[*.{js,jsx,mjs,cjs,ts,tsx,mts,cts,vue,css,scss,sass,less,styl}]
charset = utf-8
indent_size = 2
indent_style = space
insert_final_newline = true
trim_trailing_whitespace = true
end_of_line = lf
max_line_length = 100
"@
        Set-Content -Path ".editorconfig" -Value $editorConfigContent
        
        $gitAttributesContent = @"
* text=auto eol=lf
"@
        Set-Content -Path ".gitattributes" -Value $gitAttributesContent
        
        $eslintConfigContent = @"
import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'

export default [
  {
    name: 'app/files-to-lint',
    files: ['**/*.{js,mjs,jsx,vue}'],
  },

  {
    name: 'app/files-to-ignore',
    ignores: ['**/dist/**', '**/dist-ssr/**', '**/coverage/**'],
  },

  js.configs.recommended,
  ...pluginVue.configs['flat/essential'],

  {
    languageOptions: {
      ecmaVersion: 'latest',
    },
  },
]
"@
        Set-Content -Path "eslint.config.js" -Value $eslintConfigContent
        
        # Create .vscode directory and extensions.json
        New-Item -ItemType Directory -Path ".vscode" -Force | Out-Null
        $vscodeExtensionsContent = @"
{
  "recommendations": [
    "Vue.volar",
    "dbaeumer.vscode-eslint",
    "EditorConfig.EditorConfig"
  ]
}
"@
        Set-Content -Path ".vscode\extensions.json" -Value $vscodeExtensionsContent
        
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

# Create deploy.yml workflow file
$deployWorkflowContent = @"
name: Build and Deploy

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: docker.io
  API_IMAGE_NAME: `${{ secrets.DOCKER_USERNAME }}/$($SolutionName.ToLower())-api
  WEB_IMAGE_NAME: `${{ secrets.DOCKER_USERNAME }}/$($SolutionName.ToLower())-web

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      api: `${{ steps.changes.outputs.api }}
      web: `${{ steps.changes.outputs.web }}
    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
    - uses: dorny/paths-filter@v3
      id: changes
      with:
        filters: |
          api:
            - 'src/$SolutionName.Api/**'
            - '.github/workflows/deploy.yml'
          web:
            - 'src/$($SolutionName.ToLower()).web/**'
            - '.github/workflows/deploy.yml'

  build-api:
    needs: changes
    if: `${{ needs.changes.outputs.api == 'true' }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    outputs:
      image-sha: `${{ steps.sha.outputs.sha }}

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: `${{ env.REGISTRY }}
        username: `${{ secrets.DOCKER_USERNAME }}
        password: `${{ secrets.DOCKER_PASSWORD }}

    - name: Get short SHA
      id: sha
      run: echo "sha=`$(echo `${{ github.sha }} | cut -c1-7)" >> `$GITHUB_OUTPUT

    - name: Extract API metadata
      id: api-meta
      uses: docker/metadata-action@v5
      with:
        images: `${{ env.REGISTRY }}/`${{ env.API_IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-,enable={{is_default_branch}}
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Build and push API Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        file: ./src/$SolutionName.Api/Dockerfile.api
        push: true
        tags: `${{ steps.api-meta.outputs.tags }}
        labels: `${{ steps.api-meta.outputs.labels }}

  build-web:
    needs: changes
    if: `${{ needs.changes.outputs.web == 'true' }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    outputs:
      image-sha: `${{ steps.sha.outputs.sha }}

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        registry: `${{ env.REGISTRY }}
        username: `${{ secrets.DOCKER_USERNAME }}
        password: `${{ secrets.DOCKER_PASSWORD }}

    - name: Get short SHA
      id: sha
      run: echo "sha=`$(echo `${{ github.sha }} | cut -c1-7)" >> `$GITHUB_OUTPUT

    - name: Extract Web metadata
      id: web-meta
      uses: docker/metadata-action@v5
      with:
        images: `${{ env.REGISTRY }}/`${{ env.WEB_IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix=main-,enable={{is_default_branch}}
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Build and push Web Docker image
      uses: docker/build-push-action@v5
      with:
        context: ./src/$($SolutionName.ToLower()).web
        file: ./src/$($SolutionName.ToLower()).web/Dockerfile.web
        push: true
        tags: `${{ steps.web-meta.outputs.tags }}
        labels: `${{ steps.web-meta.outputs.labels }}

  deploy-api-staging:
    needs: [changes, build-api]
    if: `${{ needs.changes.outputs.api == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    
    steps:
    - name: Deploy API to Staging via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=`$(curl -s -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{"username": "`${{ secrets.PORTAINER_USERNAME }}", "password": "`${{ secrets.PORTAINER_PASSWORD }}"}' \
          | jq -r '.jwt')
        
        if [ "`$JWT_TOKEN" = "null" ] || [ -z "`$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-`${{ needs.build-api.outputs.image-sha }}"
        API_IMAGE_FULL="`${{ env.REGISTRY }}/`${{ env.API_IMAGE_NAME }}:`${IMAGE_TAG}"
        
        # Pull the API image to Portainer
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=`${API_IMAGE_FULL}" \
          -H "Authorization: Bearer `$JWT_TOKEN"
        
        # Stop and remove existing API container if it exists
        API_CONTAINER_ID=`$(curl -s -X GET \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          | jq -r '.[] | select(.Names[]? | test("/$($SolutionName.ToLower())-staging`$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "`$API_CONTAINER_ID" ] && [ "`$API_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing API container: `$API_CONTAINER_ID"
          curl -X POST \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$API_CONTAINER_ID/stop" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
          curl -X DELETE \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$API_CONTAINER_ID" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
        fi
        
        # Create new API container
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=$($SolutionName.ToLower())-staging" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "'`${API_IMAGE_FULL}'",
            "Env": [
              "ASPNETCORE_ENVIRONMENT=Staging",
              "ASPNETCORE_URLS=http://+:8080"
            ],
            "ExposedPorts": {"8080/tcp": {}},
            "HostConfig": {
              "PortBindings": {"8080/tcp": [{"HostPort": "3001"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \
          | jq -r '.Id' > api_container_id.txt
        
        # Start the API container
        API_CONTAINER_ID=`$(cat api_container_id.txt)
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$API_CONTAINER_ID/start" \
          -H "Authorization: Bearer `$JWT_TOKEN"

  deploy-web-staging:
    needs: [changes, build-web]
    if: `${{ needs.changes.outputs.web == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    
    steps:
    - name: Deploy Web to Staging via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=`$(curl -s -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{"username": "`${{ secrets.PORTAINER_USERNAME }}", "password": "`${{ secrets.PORTAINER_PASSWORD }}"}' \
          | jq -r '.jwt')
        
        if [ "`$JWT_TOKEN" = "null" ] || [ -z "`$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-`${{ needs.build-web.outputs.image-sha }}"
        WEB_IMAGE_FULL="`${{ env.REGISTRY }}/`${{ env.WEB_IMAGE_NAME }}:`${IMAGE_TAG}"
        
        # Pull the Web image to Portainer
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=`${WEB_IMAGE_FULL}" \
          -H "Authorization: Bearer `$JWT_TOKEN"
        
        # Stop and remove existing Web container if it exists
        WEB_CONTAINER_ID=`$(curl -s -X GET \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          | jq -r '.[] | select(.Names[]? | test("/$($SolutionName.ToLower())-web-staging`$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "`$WEB_CONTAINER_ID" ] && [ "`$WEB_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing Web container: `$WEB_CONTAINER_ID"
          curl -X POST \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$WEB_CONTAINER_ID/stop" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
          curl -X DELETE \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$WEB_CONTAINER_ID" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
        fi
        
        # Create new Web container
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=$($SolutionName.ToLower())-web-staging" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "'`${WEB_IMAGE_FULL}'",
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "3002"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \
          | jq -r '.Id' > web_container_id.txt
        
        # Start the Web container
        WEB_CONTAINER_ID=`$(cat web_container_id.txt)
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$WEB_CONTAINER_ID/start" \
          -H "Authorization: Bearer `$JWT_TOKEN"

  deploy-api-production:
    needs: [changes, build-api, deploy-api-staging]
    if: `${{ needs.changes.outputs.api == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    environment: production
    
    steps:
    - name: Deploy API to Production via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=`$(curl -s -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{"username": "`${{ secrets.PORTAINER_USERNAME }}", "password": "`${{ secrets.PORTAINER_PASSWORD }}"}' \
          | jq -r '.jwt')
        
        if [ "`$JWT_TOKEN" = "null" ] || [ -z "`$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-`${{ needs.build-api.outputs.image-sha }}"
        API_IMAGE_FULL="`${{ env.REGISTRY }}/`${{ env.API_IMAGE_NAME }}:`${IMAGE_TAG}"
        
        # Pull the API image to Portainer
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=`${API_IMAGE_FULL}" \
          -H "Authorization: Bearer `$JWT_TOKEN"
        
        # Stop and remove existing API container if it exists
        API_CONTAINER_ID=`$(curl -s -X GET \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          | jq -r '.[] | select(.Names[]? | test("/$($SolutionName.ToLower())-production`$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "`$API_CONTAINER_ID" ] && [ "`$API_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing API container: `$API_CONTAINER_ID"
          curl -X POST \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$API_CONTAINER_ID/stop" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
          curl -X DELETE \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$API_CONTAINER_ID" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
        fi
        
        # Create new API container
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=$($SolutionName.ToLower())-production" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "'`${API_IMAGE_FULL}'",
            "Env": [
              "ASPNETCORE_ENVIRONMENT=Production",
              "ASPNETCORE_URLS=http://+:8080"
            ],
            "ExposedPorts": {"8080/tcp": {}},
            "HostConfig": {
              "PortBindings": {"8080/tcp": [{"HostPort": "3000"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \
          | jq -r '.Id' > api_container_id.txt
        
        # Start the API container
        API_CONTAINER_ID=`$(cat api_container_id.txt)
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$API_CONTAINER_ID/start" \
          -H "Authorization: Bearer `$JWT_TOKEN"

  deploy-web-production:
    needs: [changes, build-web, deploy-web-staging]
    if: `${{ needs.changes.outputs.web == 'true' && github.ref == 'refs/heads/main' && github.event_name == 'push' }}
    runs-on: ubuntu-latest
    environment: production
    
    steps:
    - name: Deploy Web to Production via Portainer API
      run: |
        # Get JWT token from Portainer
        JWT_TOKEN=`$(curl -s -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/auth" \
          -H "Content-Type: application/json" \
          -d '{"username": "`${{ secrets.PORTAINER_USERNAME }}", "password": "`${{ secrets.PORTAINER_PASSWORD }}"}' \
          | jq -r '.jwt')
        
        if [ "`$JWT_TOKEN" = "null" ] || [ -z "`$JWT_TOKEN" ]; then
          echo "Failed to authenticate with Portainer"
          exit 1
        fi
        
        IMAGE_TAG="main-`${{ needs.build-web.outputs.image-sha }}"
        WEB_IMAGE_FULL="`${{ env.REGISTRY }}/`${{ env.WEB_IMAGE_NAME }}:`${IMAGE_TAG}"
        
        # Pull the Web image to Portainer
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/images/create?fromImage=`${WEB_IMAGE_FULL}" \
          -H "Authorization: Bearer `$JWT_TOKEN"
        
        # Stop and remove existing Web container if it exists
        WEB_CONTAINER_ID=`$(curl -s -X GET \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/json?all=true" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          | jq -r '.[] | select(.Names[]? | test("/$($SolutionName.ToLower())-web-production`$")) | .Id' 2>/dev/null || echo "")
        
        if [ ! -z "`$WEB_CONTAINER_ID" ] && [ "`$WEB_CONTAINER_ID" != "null" ]; then
          echo "Stopping existing Web container: `$WEB_CONTAINER_ID"
          curl -X POST \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$WEB_CONTAINER_ID/stop" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
          curl -X DELETE \
            "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$WEB_CONTAINER_ID" \
            -H "Authorization: Bearer `$JWT_TOKEN" || true
        fi
        
        # Create new Web container
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/create?name=$($SolutionName.ToLower())-web-production" \
          -H "Authorization: Bearer `$JWT_TOKEN" \
          -H "Content-Type: application/json" \
          -d '{
            "Image": "'`${WEB_IMAGE_FULL}'",
            "ExposedPorts": {"80/tcp": {}},
            "HostConfig": {
              "PortBindings": {"80/tcp": [{"HostPort": "3003"}]},
              "RestartPolicy": {"Name": "unless-stopped"}
            }
          }' \
          | jq -r '.Id' > web_container_id.txt
        
        # Start the Web container
        WEB_CONTAINER_ID=`$(cat web_container_id.txt)
        curl -X POST \
          "`${{ secrets.PORTAINER_URL }}/api/endpoints/`${{ secrets.PORTAINER_ENDPOINT_ID }}/docker/containers/`$WEB_CONTAINER_ID/start" \
          -H "Authorization: Bearer `$JWT_TOKEN"
"@

Set-Content -Path ".github\workflows\deploy.yml" -Value $deployWorkflowContent

# Create .idea directory structure (JetBrains Rider)
New-Item -ItemType Directory -Path ".idea\.idea.$SolutionName\.idea" -Force | Out-Null

# Create .idea configuration files
$ideaGitignoreContent = @"
# Default ignored files
/shelf/
/workspace.xml
# Rider ignored files
/.idea.$SolutionName.iml
/contentModel.xml
/modules.xml
/projectSettingsUpdater.xml
# Editor-based HTTP Client requests
/httpRequests/
# Datasource local storage ignored files
/dataSources/
/dataSources.local.xml
"@
Set-Content -Path ".idea\.idea.$SolutionName\.idea\.gitignore" -Value $ideaGitignoreContent

$encodingsXmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="Encoding" addBOMForNewFiles="with BOM under Windows, with no BOM otherwise" />
</project>
"@
Set-Content -Path ".idea\.idea.$SolutionName\.idea\encodings.xml" -Value $encodingsXmlContent

$indexLayoutXmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="UserContentModel">
    <attachedFolders />
    <explicitIncludes />
    <explicitExcludes />
  </component>
</project>
"@
Set-Content -Path ".idea\.idea.$SolutionName\.idea\indexLayout.xml" -Value $indexLayoutXmlContent

$vcsXmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="VcsDirectoryMappings">
    <mapping directory="" vcs="Git" />
  </component>
</project>
"@
Set-Content -Path ".idea\.idea.$SolutionName\.idea\vcs.xml" -Value $vcsXmlContent

# Create .dockerignore file
$dockerIgnoreContent = @"
**/.classpath
**/.dockerignore
**/.env
**/.git
**/.gitignore
**/.project
**/.settings
**/.toolstarget
**/.vs
**/.vscode
**/*.*proj.user
**/*.dbmdl
**/*.jfm
**/azds.yaml
**/bin
**/charts
**/docker-compose*
**/Dockerfile*
**/node_modules
**/npm-debug.log
**/obj
**/secrets.dev.yaml
**/values.dev.yaml
LICENSE
README.md
!**/.gitignore
!.git/HEAD
!.git/config
!.git/packed-refs
!.git/refs/heads/**
"@
Set-Content -Path ".dockerignore" -Value $dockerIgnoreContent

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
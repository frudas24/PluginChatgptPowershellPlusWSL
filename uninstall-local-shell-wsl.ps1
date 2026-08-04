[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$MarketplaceName = 'personal',
    [string]$McpHostName = 'local-shell-host'
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is resolved only after parameter binding in Windows PowerShell 5.1.
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = $PSScriptRoot }

function Get-NormalizedPath {
    param([string]$Path)
    return [IO.Path]::GetFullPath($Path.Replace('\\?\', '')).TrimEnd('\\')
}

function Resolve-CodexCli {
    $command = Get-Command codex -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $localCopy = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexCli\codex.exe'
    if (Test-Path -LiteralPath $localCopy -PathType Leaf) { return $localCopy }

    $package = Get-AppxPackage -Name OpenAI.Codex
    if (-not $package) { throw 'Codex CLI not found and the OpenAI Codex Microsoft Store app is not installed.' }

    $packagedCli = Join-Path $package.InstallLocation 'app\resources\codex.exe'
    if (-not (Test-Path -LiteralPath $packagedCli -PathType Leaf)) { throw "codex.exe not found in the Store app: $packagedCli" }

    $cliDirectory = Split-Path -Parent $localCopy
    New-Item -ItemType Directory -Path $cliDirectory -Force | Out-Null
    Copy-Item -LiteralPath $packagedCli -Destination $localCopy -Force
    return $localCopy
}

$pluginRoot = Join-Path $RepoRoot 'plugins\local-shell-wsl'
$serverScript = Join-Path $pluginRoot 'scripts\server.ps1'
foreach ($path in @($pluginRoot, $serverScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "This is not a local-shell-wsl checkout: $path was not found."
    }
}

$expectedRepoRoot = Get-NormalizedPath $RepoRoot
$expectedServerScript = Get-NormalizedPath $serverScript
$cli = Resolve-CodexCli

# Tolerate partial installs: every removal checks ownership and presence first.
$marketplaces = (& $cli plugin marketplace list --json | ConvertFrom-Json).marketplaces
if ($LASTEXITCODE -ne 0) { throw 'Could not list Codex marketplaces.' }
$marketplaceEntry = @($marketplaces | Where-Object { $_.name -eq $MarketplaceName }) | Select-Object -First 1
$marketplaceMatchesCheckout = $false
if ($marketplaceEntry) {
    $marketplaceMatchesCheckout = ((Get-NormalizedPath ([string]$marketplaceEntry.root)) -eq $expectedRepoRoot)
}

$plugins = (& $cli plugin list --json | ConvertFrom-Json).installed
if ($LASTEXITCODE -ne 0) { throw 'Could not list installed plugins.' }
$installed = @($plugins | Where-Object { $_.pluginId -eq "local-shell-wsl@$MarketplaceName" -and $_.installed })
if ($installed.Count -gt 0 -and $marketplaceMatchesCheckout) {
    & $cli plugin remove local-shell-wsl --marketplace $MarketplaceName
    if ($LASTEXITCODE -ne 0) { throw 'Could not remove local-shell-wsl.' }
    Write-Host "Removed plugin local-shell-wsl@$MarketplaceName."
} elseif ($installed.Count -gt 0) {
    Write-Warning "Plugin local-shell-wsl@$MarketplaceName belongs to another marketplace checkout and was left unchanged."
} else {
    Write-Host "Plugin local-shell-wsl@$MarketplaceName was not installed."
}

$mcpServers = & $cli mcp list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not list configured MCP servers.' }
$hostEntry = @($mcpServers | Where-Object { $_.name -eq $McpHostName }) | Select-Object -First 1
$hostMatchesCheckout = $false
if ($hostEntry -and [string]$hostEntry.transport.command -eq 'powershell.exe') {
    $args = @($hostEntry.transport.args)
    if ($args.Count -gt 0) {
        $hostMatchesCheckout = ((Get-NormalizedPath ([string]$args[-1])) -eq $expectedServerScript)
    }
}
if ($hostMatchesCheckout) {
    & $cli mcp remove $McpHostName
    if ($LASTEXITCODE -ne 0) { throw "Could not remove the $McpHostName MCP host." }
    Write-Host "Removed MCP host $McpHostName."
} elseif ($hostEntry) {
    Write-Warning "MCP host $McpHostName points to another checkout and was left unchanged."
} else {
    Write-Host "MCP host $McpHostName was not registered."
}

if ($marketplaceMatchesCheckout) {
    & $cli plugin marketplace remove $MarketplaceName
    if ($LASTEXITCODE -ne 0) { throw "Could not remove marketplace '$MarketplaceName'." }
    Write-Host "Removed marketplace $MarketplaceName."
} elseif ($marketplaceEntry) {
    Write-Warning "Marketplace $MarketplaceName points to another checkout and was left unchanged."
} else {
    Write-Host "Marketplace $MarketplaceName was not registered."
}

Write-Host "`nUninstalled. The repository clone and extracted Codex CLI copy were left in place." -ForegroundColor Green

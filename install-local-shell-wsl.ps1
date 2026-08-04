[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$MarketplaceName = 'personal',
    [string]$McpHostName = 'local-shell-host',
    [switch]$ReplaceExistingHost
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is still empty while an advanced script binds parameter
# defaults (PS 5.1 quirk), so it must be resolved in the body.
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

    # Extract a runnable CLI copy from the Microsoft Store app so the
    # installer works even when `codex` was never added to the PATH.
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
        throw "Incomplete install: $path was not found."
    }
}

$cli = Resolve-CodexCli

# Skill plugin through the local marketplace.
$configured = (& $cli plugin marketplace list --json | ConvertFrom-Json).marketplaces
if ($LASTEXITCODE -ne 0) { throw 'Could not list Codex marketplaces.' }
$existing = $configured | Where-Object { $_.name -eq $MarketplaceName }
if ($existing) {
    $actual = [IO.Path]::GetFullPath(([string]$existing.root).Replace('\\?\', ''))
    $expected = [IO.Path]::GetFullPath($RepoRoot)
    if ($actual -ne $expected) { throw "Marketplace '$MarketplaceName' already points to another path: $actual" }
} else {
    & $cli plugin marketplace add $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not register the local marketplace.' }
}

& $cli plugin add "local-shell-wsl@$MarketplaceName"
if ($LASTEXITCODE -ne 0) { throw 'Could not install local-shell-wsl.' }

# The plugin-embedded MCP gets E_ACCESSDENIED from WSL CreateInstance when the
# desktop app launches it. The global MCP host runs with tool approval prompts
# and is the launch context where WSL works, so it is the supported shape.
$mcpServers = & $cli mcp list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not list configured MCP servers.' }
$hostEntry = @($mcpServers | Where-Object { $_.name -eq $McpHostName }) | Select-Object -First 1
$hostNeedsUpdate = $true
if ($hostEntry) {
    $registeredArgs = @($hostEntry.transport.args)
    $hostMatchesCheckout = ([string]$hostEntry.transport.command -eq 'powershell.exe') -and
        ($registeredArgs.Count -gt 0) -and
        ((Get-NormalizedPath ([string]$registeredArgs[-1])) -eq (Get-NormalizedPath $serverScript))
    $hostNeedsUpdate = -not $hostMatchesCheckout
    if ($hostNeedsUpdate) {
        if (-not $ReplaceExistingHost) {
            throw "MCP host '$McpHostName' already points to another checkout. Run the uninstaller there first, or rerun with -ReplaceExistingHost."
        }
        & $cli mcp remove $McpHostName
        if ($LASTEXITCODE -ne 0) { throw "Could not remove the stale $McpHostName MCP host." }
    }
}
if ($hostNeedsUpdate) {
    & $cli mcp add $McpHostName -- powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $serverScript
    if ($LASTEXITCODE -ne 0) { throw "Could not register the $McpHostName MCP host." }
}

& $cli plugin list
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the installation.' }

Write-Host "`nInstalled. Fully close Codex, reopen it, and start or fork a conversation before using @local-shell-wsl." -ForegroundColor Green

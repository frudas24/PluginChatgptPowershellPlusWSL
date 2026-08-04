[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$MarketplaceName = 'personal'
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is still empty while an advanced script binds parameter
# defaults (PS 5.1 quirk), so it must be resolved in the body.
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = $PSScriptRoot }

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
$mcpTemplate = Join-Path $pluginRoot '.mcp.template.json'
$mcpConfig = Join-Path $pluginRoot '.mcp.json'

foreach ($path in @($pluginRoot, $serverScript, $mcpTemplate)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Incomplete install: $path was not found."
    }
}

$cli = Resolve-CodexCli

# The MCP manifest needs an absolute path; it is generated locally so the
# repository can live in any folder on any machine.
$template = Get-Content -LiteralPath $mcpTemplate -Raw
$escapedServerScript = $serverScript.Replace('\', '\\')
$template.Replace('__SERVER_SCRIPT__', $escapedServerScript) |
    Set-Content -LiteralPath $mcpConfig -Encoding UTF8

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

# The global host was an earlier experiment. The plugin is self-contained and
# provides its own MCP through .mcp.json; leave no residual global config.
$mcpServers = & $cli mcp list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not list configured MCP servers.' }
if (@($mcpServers | Where-Object { $_.name -eq 'local-shell-host' }).Count -gt 0) {
    & $cli mcp remove local-shell-host
    if ($LASTEXITCODE -ne 0) { throw 'Could not remove the previous global MCP host.' }
}

& $cli plugin add "local-shell-wsl@$MarketplaceName"
if ($LASTEXITCODE -ne 0) { throw 'Could not install local-shell-wsl.' }

& $cli plugin list
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the installation.' }

Write-Host "`nInstalled. Fully close Codex, reopen it, and start or fork a conversation before using @local-shell-wsl." -ForegroundColor Green

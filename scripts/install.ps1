[CmdletBinding()]
param(
    [string]$Repository = "https://github.com/frudas24/PluginChatgptPowershellPlusWSL.git",
    [string]$Ref = "main",
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "Frudas24\PluginChatgptPowershellPlusWSL"),
    [string]$CodexPath
)

$ErrorActionPreference = "Stop"

function Invoke-External {
    param(
        [string]$FileName,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    & $FileName @Arguments
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "Command failed: $FileName $($Arguments -join ' ')"
    }
}

function Resolve-CodexPath {
    param([string]$RequestedPath)

    $candidates = @($RequestedPath, (Join-Path $env:LOCALAPPDATA "OpenAI\CodexCli\codex.exe")) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command codex -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Codex CLI was not found. Install it or pass -CodexPath C:\path\to\codex.exe."
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required to install this plugin. Install Git for Windows and run this script again."
}

$codex = Resolve-CodexPath $CodexPath
$parent = Split-Path -Parent $InstallRoot
if (-not (Test-Path -LiteralPath $InstallRoot)) {
    [void][IO.Directory]::CreateDirectory($parent)
    Invoke-External "git" @("clone", "--branch", $Ref, "--single-branch", $Repository, $InstallRoot)
} elseif (Test-Path -LiteralPath (Join-Path $InstallRoot ".git") -PathType Container) {
    # The installer owns this generated MCP file and recreates it below.
    Invoke-External "git" @("-C", $InstallRoot, "checkout", "--", "plugins/local-shell-wsl/.mcp.json") -AllowFailure
    Invoke-External "git" @("-C", $InstallRoot, "pull", "--ff-only", "origin", $Ref)
} else {
    throw "InstallRoot exists but is not this plugin's Git checkout: $InstallRoot"
}

$pluginRoot = Join-Path $InstallRoot "plugins\local-shell-wsl"
$serverPath = Join-Path $pluginRoot "scripts\server.ps1"
$marketplacePath = Join-Path $InstallRoot ".agents\plugins\marketplace.json"
$mcpPath = Join-Path $pluginRoot ".mcp.json"
foreach ($path in @($serverPath, $marketplacePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required plugin file is missing: $path"
    }
}

# A native absolute path matches the launch mode that permits WSL in ChatGPT Work.
$mcp = [ordered]@{
    mcpServers = [ordered]@{
        "local-shell" = [ordered]@{
            command = "powershell.exe"
            args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $serverPath)
        }
    }
}
$mcp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $mcpPath -Encoding UTF8

# Replace the Git-backed marketplace so the installed plugin uses the native checkout.
Invoke-External $codex @("plugin", "remove", "local-shell-wsl", "--marketplace", "frudas24") -AllowFailure
Invoke-External $codex @("plugin", "marketplace", "remove", "frudas24") -AllowFailure
Invoke-External $codex @("plugin", "marketplace", "add", $InstallRoot)
Invoke-External $codex @("plugin", "add", "local-shell-wsl@frudas24")

Write-Host "Installed local-shell-wsl from $InstallRoot"
Write-Host "Restart ChatGPT Work or Codex, then start a new chat."

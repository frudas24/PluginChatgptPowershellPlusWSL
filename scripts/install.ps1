[CmdletBinding()]
param(
    [string]$Repository = "https://github.com/frudas24/PluginChatgptPowershellPlusWSL.git",
    [string]$Ref = "main",
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "Frudas24\PluginChatgptPowershellPlusWSL")
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

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required to install this plugin. Install Git for Windows and run this script again."
}

if (-not (Test-Path -LiteralPath $InstallRoot)) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $InstallRoot))
    Invoke-External "git" @("clone", "--branch", $Ref, "--single-branch", $Repository, $InstallRoot)
} elseif (Test-Path -LiteralPath (Join-Path $InstallRoot ".git") -PathType Container) {
    # The installer owns the generated MCP file; drop it so pull stays clean.
    Invoke-External "git" @("-C", $InstallRoot, "checkout", "--", "plugins/local-shell-wsl/.mcp.json") -AllowFailure
    Invoke-External "git" @("-C", $InstallRoot, "pull", "--ff-only", "origin", $Ref)
} else {
    throw "InstallRoot exists but is not this plugin's Git checkout: $InstallRoot"
}

# Both install modes share one code path: the local installer inside the checkout.
$localInstaller = Join-Path $InstallRoot "install-local-shell-wsl.ps1"
if (-not (Test-Path -LiteralPath $localInstaller -PathType Leaf)) {
    throw "Local installer is missing from the checkout: $localInstaller"
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $localInstaller -RepoRoot $InstallRoot
if ($LASTEXITCODE -ne 0) { throw "The local installer reported a failure." }

Write-Host "Restart ChatGPT Work or Codex, then start a new chat."

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$pluginRoot = Join-Path $PSScriptRoot 'plugins\local-shell-wsl'
$serverScript = Join-Path $pluginRoot 'scripts\server.ps1'
$mcpTemplate = Join-Path $pluginRoot '.mcp.template.json'
$mcpConfig = Join-Path $pluginRoot '.mcp.json'

foreach ($path in @($pluginRoot, $serverScript, $mcpTemplate)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Instalador incompleto: no se encontró $path"
    }
}

$package = Get-AppxPackage -Name OpenAI.Codex
if (-not $package) { throw 'No se encontró la aplicación OpenAI Codex de Microsoft Store.' }

$packagedCli = Join-Path $package.InstallLocation 'app\resources\codex.exe'
if (-not (Test-Path -LiteralPath $packagedCli)) { throw "No se encontró codex.exe: $packagedCli" }

$cliDirectory = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexCli'
$cli = Join-Path $cliDirectory 'codex.exe'
New-Item -ItemType Directory -Path $cliDirectory -Force | Out-Null
Copy-Item -LiteralPath $packagedCli -Destination $cli -Force

# El manifiesto MCP necesita una ruta absoluta. Se genera localmente para que
# el repositorio se pueda clonar en cualquier carpeta o equipo.
$template = Get-Content -LiteralPath $mcpTemplate -Raw
$escapedServerScript = $serverScript.Replace('\', '\\')
$template.Replace('__SERVER_SCRIPT__', $escapedServerScript) |
    Set-Content -LiteralPath $mcpConfig -Encoding UTF8

$marketplaceName = 'personal'
$configured = (& $cli plugin marketplace list --json | ConvertFrom-Json).marketplaces
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar los marketplaces de Codex.' }
$personal = $configured | Where-Object { $_.name -eq $marketplaceName }
if ($personal) {
    $actual = [IO.Path]::GetFullPath(([string]$personal.root).Replace('\\?\', ''))
    $expected = [IO.Path]::GetFullPath($PSScriptRoot)
    if ($actual -ne $expected) { throw "El marketplace 'personal' ya apunta a otra ruta: $actual" }
} else {
    & $cli plugin marketplace add $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo registrar el marketplace local.' }
}

# El host global fue una prueba anterior. El plugin es autosuficiente y aporta
# su propio MCP mediante .mcp.json; no dejamos configuración global residual.
$mcpServers = & $cli mcp list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar los servidores MCP configurados.' }
if (@($mcpServers | Where-Object { $_.name -eq 'local-shell-host' }).Count -gt 0) {
    & $cli mcp remove local-shell-host
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo eliminar el host MCP global anterior.' }
}

& $cli plugin add 'local-shell-wsl@personal'
if ($LASTEXITCODE -ne 0) { throw 'No se pudo instalar local-shell-wsl.' }

& $cli plugin list
if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar la instalación.' }

Write-Host "`nInstalado. Cierra Codex por completo, ábrelo y crea/forkea una conversación antes de usar @local-shell-wsl." -ForegroundColor Green

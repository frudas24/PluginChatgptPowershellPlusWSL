$serverPath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\scripts\server.ps1"
$remoteInstallerPath = Join-Path $PSScriptRoot "..\scripts\install.ps1"
$localInstallerPath = Join-Path $PSScriptRoot "..\install-local-shell-wsl.ps1"
$uninstallerPath = Join-Path $PSScriptRoot "..\uninstall-local-shell-wsl.ps1"
$pluginPath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\.codex-plugin\plugin.json"
$marketplacePath = Join-Path $PSScriptRoot "..\.agents\plugins\marketplace.json"

Describe "local-shell-wsl server" {
    It "has valid PowerShell syntax" {
        foreach ($scriptPath in @($serverPath, $remoteInstallerPath, $localInstallerPath, $uninstallerPath)) {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            $errors.Count | Should Be 0
        }
    }

    It "uses bounded output and process-tree cleanup" {
        $source = Get-Content -LiteralPath $serverPath -Raw
        $source | Should Match 'class BoundedStreamReader'
        $source | Should Match 'taskkill\.exe'
    }

    It "launches WSL through a PowerShell child" {
        $source = Get-Content -LiteralPath $serverPath -Raw
        $source | Should Match "wsl\.exe '--' 'bash' '-lc'"
        $source | Should Not Match 'Invoke-LocalProcess "wsl\.exe"'
    }

    It "has valid marketplace metadata" {
        { Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json } | Should Not Throw
        { Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json } | Should Not Throw
    }

    It "does not embed an MCP server in the plugin" {
        $plugin = Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json
        ($plugin.PSObject.Properties.Name -join ',') | Should Not Match '(^|,)mcpServers(,|$)'
    }

    It "registers the global MCP host from the installer" {
        $source = Get-Content -LiteralPath $localInstallerPath -Raw
        $source | Should Match 'mcp add'
        $source | Should Match 'local-shell-host'
    }

    It "only removes matching MCP and marketplace registrations" {
        $source = Get-Content -LiteralPath $uninstallerPath -Raw
        $source | Should Match 'MCP host .*points to another checkout'
        $source | Should Match 'Marketplace .*points to another checkout'
        $source | Should Match 'Get-NormalizedPath'
    }

    It "uses the personal marketplace identity and current plugin version" {
        $plugin = Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
        $plugin.version | Should Be "0.3.2"
        $marketplace.name | Should Be "personal"
    }
}

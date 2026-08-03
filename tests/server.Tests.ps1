$serverPath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\scripts\server.ps1"
$remoteInstallerPath = Join-Path $PSScriptRoot "..\scripts\install.ps1"
$localInstallerPath = Join-Path $PSScriptRoot "..\install-local-shell-wsl.ps1"
$pluginPath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\.codex-plugin\plugin.json"
$marketplacePath = Join-Path $PSScriptRoot "..\.agents\plugins\marketplace.json"
$mcpTemplatePath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\.mcp.template.json"

Describe "local-shell-wsl server" {
    It "has valid PowerShell syntax" {
        foreach ($scriptPath in @($serverPath, $remoteInstallerPath, $localInstallerPath)) {
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

    It "has valid marketplace metadata" {
        { Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json } | Should Not Throw
        { Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json } | Should Not Throw
        { Get-Content -LiteralPath $mcpTemplatePath -Raw | ConvertFrom-Json } | Should Not Throw
    }

    It "keeps the MCP template on the generated placeholder" {
        $template = Get-Content -LiteralPath $mcpTemplatePath -Raw
        $template | Should Match '__SERVER_SCRIPT__'
    }

    It "uses the personal marketplace identity and current plugin version" {
        $plugin = Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
        $plugin.version | Should Be "0.3.0"
        $marketplace.name | Should Be "personal"
    }
}

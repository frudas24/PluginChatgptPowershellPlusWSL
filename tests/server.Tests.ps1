$serverPath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\scripts\server.ps1"
$pluginPath = Join-Path $PSScriptRoot "..\plugins\local-shell-wsl\.codex-plugin\plugin.json"
$marketplacePath = Join-Path $PSScriptRoot "..\.agents\plugins\marketplace.json"

Describe "local-shell-wsl server" {
    It "has valid PowerShell syntax" {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($serverPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should Be 0
    }

    It "uses bounded output and process-tree cleanup" {
        $source = Get-Content -LiteralPath $serverPath -Raw
        $source | Should Match 'class BoundedStreamReader'
        $source | Should Match 'taskkill\.exe'
    }

    It "has valid marketplace metadata" {
        { Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json } | Should Not Throw
        { Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json } | Should Not Throw
    }

    It "uses the GitHub marketplace identity and current plugin version" {
        $plugin = Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json
        $marketplace = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
        $plugin.version | Should Be "0.2.3"
        $marketplace.name | Should Be "frudas24"
    }
}

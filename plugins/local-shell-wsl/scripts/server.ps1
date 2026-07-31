$ErrorActionPreference = "Stop"

$MaxOutputChars = 120000
$BlockedPattern = '(?i)(^|[;&|]\s*)(remove-item|del|erase|rd|rmdir|rm|unlink|shred|format|clear-disk|initialize-disk|stop-computer|restart-computer|shutdown|reboot|mkfs|dd)\b|git\s+(reset\s+--hard|clean\s+-[a-z]*f)|:\(\)\s*\{'

function Send-JsonRpcResult {
    param($Id, $Result)
    $response = [ordered]@{ jsonrpc = "2.0"; id = $Id; result = $Result }
    [Console]::Out.WriteLine(($response | ConvertTo-Json -Depth 20 -Compress))
}

function Send-JsonRpcError {
    param($Id, [int]$Code, [string]$Message)
    $response = [ordered]@{
        jsonrpc = "2.0"
        id = $Id
        error = [ordered]@{ code = $Code; message = $Message }
    }
    [Console]::Out.WriteLine(($response | ConvertTo-Json -Depth 20 -Compress))
}

function Assert-SafeCommand {
    param([string]$Command)
    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw "El comando no puede estar vacío."
    }
    if ($Command -match $BlockedPattern) {
        throw "Comando bloqueado por la política de seguridad del plugin."
    }
}

function Invoke-LocalProcess {
    param(
        [string]$FileName,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds
    )

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FileName
    $start.Arguments = $Arguments
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($WorkingDirectory) { $start.WorkingDirectory = $WorkingDirectory }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        throw "El comando superó el límite de $TimeoutSeconds segundos."
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($stdout.Contains([char]0)) { $stdout = $stdout.Replace([string][char]0, "") }
    if ($stderr.Contains([char]0)) { $stderr = $stderr.Replace([string][char]0, "") }
    if ($stdout.Length -gt $MaxOutputChars) { $stdout = $stdout.Substring(0, $MaxOutputChars) + "`n[Salida truncada]" }
    if ($stderr.Length -gt $MaxOutputChars) { $stderr = $stderr.Substring(0, $MaxOutputChars) + "`n[Salida truncada]" }

    return [ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function Get-ToolDefinitions {
    return @(
        [ordered]@{
            name = "run_powershell"
            description = "Ejecuta un comando no destructivo en Windows PowerShell local."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    command = [ordered]@{ type = "string"; description = "Comando PowerShell." }
                    cwd = [ordered]@{ type = "string"; description = "Directorio de trabajo de Windows opcional." }
                    timeout_seconds = [ordered]@{ type = "integer"; minimum = 1; maximum = 120; default = 30 }
                }
                required = @("command")
                additionalProperties = $false
            }
        },
        [ordered]@{
            name = "run_wsl"
            description = "Ejecuta un comando no destructivo en la distribución WSL predeterminada."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    command = [ordered]@{ type = "string"; description = "Comando para bash dentro de WSL." }
                    cwd = [ordered]@{ type = "string"; description = "Directorio Linux opcional, por ejemplo /home/usuario." }
                    timeout_seconds = [ordered]@{ type = "integer"; minimum = 1; maximum = 120; default = 30 }
                }
                required = @("command")
                additionalProperties = $false
            }
        }
    )
}

function Invoke-Tool {
    param([string]$Name, $Arguments)
    $command = [string]$Arguments.command
    Assert-SafeCommand $command
    $timeout = if ($Arguments.timeout_seconds) { [Math]::Min(120, [Math]::Max(1, [int]$Arguments.timeout_seconds)) } else { 30 }

    if ($Name -eq "run_powershell") {
        $wrappedCommand = "`$ProgressPreference = 'SilentlyContinue'; " + $command
        $bytes = [Text.Encoding]::Unicode.GetBytes($wrappedCommand)
        $encoded = [Convert]::ToBase64String($bytes)
        $result = Invoke-LocalProcess "powershell.exe" "-NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded" ([string]$Arguments.cwd) $timeout
    } elseif ($Name -eq "run_wsl") {
        $linuxCommand = if ($Arguments.cwd) { "cd -- " + "'" + ([string]$Arguments.cwd).Replace("'", "'\''") + "' && " + $command } else { $command }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($linuxCommand))
        $bash = "echo $encoded | base64 -d | bash"
        $result = Invoke-LocalProcess "wsl.exe" "-- bash -lc `"$bash`"" $null $timeout
    } else {
        throw "Herramienta desconocida: $Name"
    }

    $text = $result | ConvertTo-Json -Depth 5
    return [ordered]@{
        content = @([ordered]@{ type = "text"; text = $text })
        isError = ($result.exit_code -ne 0)
    }
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $request = $null
    try {
        $request = $line | ConvertFrom-Json
        switch ([string]$request.method) {
            "initialize" {
                Send-JsonRpcResult $request.id ([ordered]@{
                    protocolVersion = "2025-03-26"
                    capabilities = [ordered]@{ tools = [ordered]@{} }
                    serverInfo = [ordered]@{ name = "local-shell-wsl"; version = "0.1.0" }
                })
            }
            "notifications/initialized" {}
            "ping" { Send-JsonRpcResult $request.id ([ordered]@{}) }
            "tools/list" { Send-JsonRpcResult $request.id ([ordered]@{ tools = @(Get-ToolDefinitions) }) }
            "tools/call" {
                $result = Invoke-Tool ([string]$request.params.name) $request.params.arguments
                Send-JsonRpcResult $request.id $result
            }
            default {
                if ($null -ne $request.id) { Send-JsonRpcError $request.id -32601 "Método no encontrado." }
            }
        }
    } catch {
        $id = if ($null -ne $request) { $request.id } else { $null }
        Send-JsonRpcError $id -32603 $_.Exception.Message
    }
}

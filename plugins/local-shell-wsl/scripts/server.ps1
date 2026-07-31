$ErrorActionPreference = "Stop"

$MaxOutputChars = 120000
$BlockedPattern = '(?i)(^|[;&|]\s*)(remove-item|del|erase|rd|rmdir|rm|unlink|shred|format|clear-disk|initialize-disk|stop-computer|restart-computer|shutdown|reboot|mkfs|dd)\b|git\s+(reset\s+--hard|clean\s+-[a-z]*f)|:\(\)\s*\{'
$ManagedWindowsRoot = Join-Path ([IO.Path]::GetTempPath()) "codex-local-shell-wsl"
$ManagedTemps = @{}
[void][IO.Directory]::CreateDirectory($ManagedWindowsRoot)

Add-Type @'
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;

public static class BoundedStreamReader
{
    public static Task<string> ReadAsync(StreamReader reader, int maxChars)
    {
        return Task<string>.Factory.StartNew(() => Read(reader, maxChars));
    }

    private static string Read(StreamReader reader, int maxChars)
    {
        var buffer = new char[8192];
        var output = new StringBuilder(Math.Min(maxChars, buffer.Length));
        var truncated = false;
        int count;
        while ((count = reader.Read(buffer, 0, buffer.Length)) > 0)
        {
            var remaining = maxChars - output.Length;
            if (remaining > 0) output.Append(buffer, 0, Math.Min(remaining, count));
            if (count > remaining) truncated = true;
        }
        return truncated ? output.ToString() + "\n[Output truncated]" : output.ToString();
    }
}
'@

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
        throw "Command cannot be empty."
    }
    if ($Command -match $BlockedPattern) {
        throw "Command blocked by plugin security policy."
    }
}

function Assert-ManagedWindowsRoot {
    $rootItem = Get-Item -LiteralPath $ManagedWindowsRoot -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Managed temp root is not a normal directory."
    }
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($Process.HasExited) { return }
    try {
        # Process.Kill() only terminates one process on Windows PowerShell 5.1.
        $taskKill = New-Object System.Diagnostics.ProcessStartInfo
        $taskKill.FileName = "taskkill.exe"
        $taskKill.Arguments = "/PID $($Process.Id) /T /F"
        $taskKill.UseShellExecute = $false
        $taskKill.CreateNoWindow = $true
        $killer = [System.Diagnostics.Process]::Start($taskKill)
        [void]$killer.WaitForExit(5000)
    } catch {}
    if (-not $Process.HasExited) {
        try { $Process.Kill() } catch {}
    }
    try { $Process.WaitForExit() } catch {}
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
    # Drain both pipes concurrently while retaining at most the response limit.
    $stdoutTask = [BoundedStreamReader]::ReadAsync($process.StandardOutput, $MaxOutputChars)
    $stderrTask = [BoundedStreamReader]::ReadAsync($process.StandardError, $MaxOutputChars)

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-ProcessTree $process
        throw "Command exceeded the $TimeoutSeconds second limit."
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($stdout.Contains([char]0)) { $stdout = $stdout.Replace([string][char]0, "") }
    if ($stderr.Contains([char]0)) { $stderr = $stderr.Replace([string][char]0, "") }
    return [ordered]@{
        exit_code = $process.ExitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function Invoke-WslBash {
    param([string]$Script, [int]$TimeoutSeconds = 30)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    # timeout also constrains the Linux-side bash if wsl.exe outlives its Windows parent.
    $bootstrap = "printf '%s' '$encoded' | base64 -d | timeout --signal=TERM --kill-after=5s $TimeoutSeconds bash"
    return Invoke-LocalProcess "wsl.exe" "-- bash -lc `"$bootstrap`"" $null ($TimeoutSeconds + 6)
}

function Assert-NoWindowsReparsePoints {
    param([string]$Path)
    $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Managed temp is a link or reparse point; cleanup rejected."
    }
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction Stop) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Temp contains a link or reparse point; cleanup rejected."
        }
    }
}

function New-ManagedTemp {
    param([string]$Environment)
    $handle = [Guid]::NewGuid().ToString("N")

    if ($Environment -eq "powershell") {
        Assert-ManagedWindowsRoot
        $root = [IO.Path]::GetFullPath($ManagedWindowsRoot).TrimEnd('\')
        $path = [IO.Path]::GetFullPath((Join-Path $root $handle))
        if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Could not build a safe temp path."
        }
        [void][IO.Directory]::CreateDirectory($path)
    } elseif ($Environment -eq "wsl") {
        $path = "/tmp/codex-local-shell-wsl/$handle"
        $script = @'
set -eu
umask 077
root=/tmp/codex-local-shell-wsl
if [ -e "$root" ] || [ -L "$root" ]; then
  [ -d "$root" ] && [ ! -L "$root" ] || exit 44
else
  mkdir -- "$root"
fi
chmod 700 -- "$root"
mkdir -- "{0}"
printf '%s' "{0}"
'@ -f $path
        $result = Invoke-WslBash $script 30
        if ($result.exit_code -ne 0) {
            throw "Could not create WSL temp: $($result.stderr)$($result.stdout)"
        }
    } else {
        throw "Invalid environment. Use powershell or wsl."
    }

    $ManagedTemps[$handle] = [pscustomobject]@{
        handle = $handle
        environment = $Environment
        path = $path
        created_at = [DateTime]::UtcNow.ToString("o")
    }
    return $ManagedTemps[$handle]
}

function Remove-ManagedTemp {
    param([string]$Handle)
    if ($Handle -notmatch '^[a-f0-9]{32}$' -or -not $ManagedTemps.ContainsKey($Handle)) {
        throw "Unknown temp handle or not issued by this server."
    }

    $entry = $ManagedTemps[$Handle]
    if ($entry.environment -eq "powershell") {
        Assert-ManagedWindowsRoot
        $root = [IO.Path]::GetFullPath($ManagedWindowsRoot).TrimEnd('\')
        $expected = [IO.Path]::GetFullPath((Join-Path $root $Handle))
        $actual = [IO.Path]::GetFullPath([string]$entry.path)
        if ($actual -ne $expected -or -not $actual.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Temp path does not match the managed handle."
        }
        Assert-NoWindowsReparsePoints $actual
        [IO.Directory]::Delete($actual, $true)
    } elseif ($entry.environment -eq "wsl") {
        $expected = "/tmp/codex-local-shell-wsl/$Handle"
        if ([string]$entry.path -ne $expected) {
            throw "WSL temp path does not match the managed handle."
        }
        $script = @'
set -eu
root=/tmp/codex-local-shell-wsl
path="$root/{0}"
[ -d "$root" ]
[ ! -L "$root" ]
[ -d "$path" ]
[ ! -L "$path" ]
resolved="$(readlink -f -- "$path")"
test "$resolved" = "$path"
if find "$path" -mindepth 1 -type l -print -quit | grep -q .; then
  echo 'Temp contains a symbolic link; cleanup rejected.' >&2
  exit 42
fi
if command -v findmnt >/dev/null 2>&1 && findmnt -rn -o TARGET -R "$path" | grep -q .; then
  echo 'Temp contains a mount point; cleanup rejected.' >&2
  exit 43
fi
rm -rf -- "$path"
[ ! -e "$path" ]
'@ -f $Handle
        $result = Invoke-WslBash $script 30
        if ($result.exit_code -ne 0) {
            throw "Could not clean up WSL temp: $($result.stderr)$($result.stdout)"
        }
    } else {
        throw "Temp record has an unknown environment."
    }

    $ManagedTemps.Remove($Handle)
    return [ordered]@{ handle = $Handle; deleted = $true }
}

function Get-ToolDefinitions {
    return @(
        [ordered]@{
            name = "run_powershell"
            description = "Run a non-destructive command in local Windows PowerShell."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    command = [ordered]@{ type = "string"; description = "PowerShell command." }
                    cwd = [ordered]@{ type = "string"; description = "Optional Windows working directory." }
                    timeout_seconds = [ordered]@{ type = "integer"; minimum = 1; maximum = 120; default = 30 }
                }
                required = @("command")
                additionalProperties = $false
            }
        },
        [ordered]@{
            name = "run_wsl"
            description = "Run a non-destructive command in the default WSL distribution."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    command = [ordered]@{ type = "string"; description = "Command to run in bash inside WSL." }
                    cwd = [ordered]@{ type = "string"; description = "Optional Linux directory, e.g. /home/user." }
                    timeout_seconds = [ordered]@{ type = "integer"; minimum = 1; maximum = 120; default = 30 }
                }
                required = @("command")
                additionalProperties = $false
            }
        },
        [ordered]@{
            name = "create_managed_temp"
            description = "Create a managed temp directory and return an opaque handle and its path."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    environment = [ordered]@{ type = "string"; enum = @("powershell", "wsl"); default = "powershell" }
                }
                additionalProperties = $false
            }
        },
        [ordered]@{
            name = "list_managed_temps"
            description = "List active temps created by this server instance."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{}
                additionalProperties = $false
            }
        },
        [ordered]@{
            name = "cleanup_managed_temp"
            description = "Delete only a managed temp created by this instance, using its opaque handle."
            inputSchema = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    handle = [ordered]@{ type = "string"; pattern = "^[a-f0-9]{32}$" }
                }
                required = @("handle")
                additionalProperties = $false
            }
        }
    )
}

function Invoke-Tool {
    param([string]$Name, $Arguments)
    if ($Name -eq "create_managed_temp") {
        $environment = if ($Arguments.environment) { [string]$Arguments.environment } else { "powershell" }
        $result = New-ManagedTemp $environment
    } elseif ($Name -eq "list_managed_temps") {
        $result = [ordered]@{ temps = @($ManagedTemps.Values | Sort-Object created_at) }
    } elseif ($Name -eq "cleanup_managed_temp") {
        $result = Remove-ManagedTemp ([string]$Arguments.handle)
    } elseif ($Name -eq "run_powershell" -or $Name -eq "run_wsl") {
        $command = [string]$Arguments.command
        Assert-SafeCommand $command
        $timeout = if ($Arguments.timeout_seconds) { [Math]::Min(120, [Math]::Max(1, [int]$Arguments.timeout_seconds)) } else { 30 }
        if ($Name -eq "run_powershell") {
            $wrappedCommand = "`$ProgressPreference = 'SilentlyContinue'; " + $command
            $bytes = [Text.Encoding]::Unicode.GetBytes($wrappedCommand)
            $encoded = [Convert]::ToBase64String($bytes)
            $result = Invoke-LocalProcess "powershell.exe" "-NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded" ([string]$Arguments.cwd) $timeout
        } else {
            $linuxCommand = if ($Arguments.cwd) { "cd -- " + "'" + ([string]$Arguments.cwd).Replace("'", "'\''") + "' && " + $command } else { $command }
            $result = Invoke-WslBash $linuxCommand $timeout
        }
    } else {
        throw "Unknown tool: $Name"
    }

    $text = $result | ConvertTo-Json -Depth 5
    return [ordered]@{
        content = @([ordered]@{ type = "text"; text = $text })
        isError = ($result.exit_code -ne 0)
    }
}

try {
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
                        serverInfo = [ordered]@{ name = "local-shell-wsl"; version = "0.2.2" }
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
                    if ($null -ne $request.id) { Send-JsonRpcError $request.id -32601 "Method not found." }
                }
            }
        } catch {
            $id = if ($null -ne $request) { $request.id } else { $null }
            Send-JsonRpcError $id -32603 $_.Exception.Message
        }
    }
} finally {
    # Best-effort cleanup on a graceful MCP shutdown; crashes still require manual cleanup.
    foreach ($handle in @($ManagedTemps.Keys)) {
        try { [void](Remove-ManagedTemp $handle) } catch {}
    }
}

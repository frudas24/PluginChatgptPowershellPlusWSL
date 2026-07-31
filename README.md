# PowerShell + WSL local for Codex

Local plugin that exposes five MCP tools:

- `run_powershell`: execute Windows PowerShell.
- `run_wsl`: execute Bash in the default WSL distribution.
- `create_managed_temp`: create a managed temp in Windows or WSL.
- `list_managed_temps`: show active temps for this instance.
- `cleanup_managed_temp`: clean up a managed temp via its opaque handle.

## Installation

Install the Windows-native copy with PowerShell. This preserves WSL access in ChatGPT Work by generating an absolute local server path:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/frudas24/PluginChatgptPowershellPlusWSL/main/scripts/install.ps1)))
```

The installer requires Git for Windows and Codex CLI. It installs the repository under `%LOCALAPPDATA%\Frudas24\PluginChatgptPowershellPlusWSL`, refreshes it from `main` on subsequent runs, and registers it as the local `frudas24` marketplace.

After publishing an update to `main`, rerun the same command:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/frudas24/PluginChatgptPowershellPlusWSL/main/scripts/install.ps1)))
```

Restart Codex and begin a new task after enabling or updating the plugin.

## Security

The server blocks common destructive patterns, limits retained output to 120 KB per stream, and uses `taskkill /T` to stop timed-out Windows process trees. Managed cleanup does not accept arbitrary paths: only handles created by the current instance are accepted, the canonical path is validated, and links or mount points are rejected. Graceful server shutdown cleans active managed temps; a crash can still leave a temp behind. This is a preventive barrier, not full isolation: any local terminal carries risk. Always review the execution request that Codex displays.

## Requirements

- Windows PowerShell 5.1 or later.
- WSL installed with a default distribution for `run_wsl`.

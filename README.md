# PowerShell + WSL local for Codex

Local plugin that exposes five MCP tools:

- `run_powershell`: execute Windows PowerShell.
- `run_wsl`: execute Bash in the default WSL distribution.
- `create_managed_temp`: create a managed temp in Windows or WSL.
- `list_managed_temps`: show active temps for this instance.
- `cleanup_managed_temp`: clean up a managed temp via its opaque handle.

## Installation

The Microsoft Store app protects its internal copy of `codex.exe`. Run the included installer from PowerShell:

```powershell
& "<plugin-path>\scripts\install.ps1"
```

The installer copies the CLI to a normal folder under `%LOCALAPPDATA%`, registers the marketplace, and installs the plugin. After that, close Codex completely, reopen it, and create a new task.

## Security

The server blocks common destructive patterns, caps each execution at 120 seconds, and truncates excessive output. Managed cleanup does not accept arbitrary paths: only handles created by the current instance are accepted, the canonical path is validated, and links or mount points are rejected. This is a preventive barrier, not full isolation: any local terminal carries risk. Always review the execution request that Codex displays.

## Requirements

- Windows PowerShell 5.1 or later.
- WSL installed with a default distribution for `run_wsl`.

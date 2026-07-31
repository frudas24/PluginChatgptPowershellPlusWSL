# PowerShell + WSL local for Codex

Local plugin that exposes five MCP tools:

- `run_powershell`: execute Windows PowerShell.
- `run_wsl`: execute Bash in the default WSL distribution.
- `create_managed_temp`: create a managed temp in Windows or WSL.
- `list_managed_temps`: show active temps for this instance.
- `cleanup_managed_temp`: clean up a managed temp via its opaque handle.

## Installation

Install directly from GitHub with Codex CLI:

```powershell
codex plugin marketplace add frudas24/PluginChatgptPowershellPlusWSL --ref main
codex plugin add local-shell-wsl@frudas24
```

After publishing an update to `main`, refresh and reinstall it:

```powershell
codex plugin marketplace upgrade frudas24
codex plugin add local-shell-wsl@frudas24
```

Restart Codex and begin a new task after enabling or updating the plugin.

## Security

The server blocks common destructive patterns, limits retained output to 120 KB per stream, and uses `taskkill /T` plus Linux `timeout` to stop timed-out commands. Managed cleanup does not accept arbitrary paths: only handles created by the current instance are accepted, the canonical path is validated, and links or mount points are rejected. Graceful server shutdown cleans active managed temps; a crash can still leave a temp behind. This is a preventive barrier, not full isolation: any local terminal carries risk. Always review the execution request that Codex displays.

## Requirements

- Windows PowerShell 5.1 or later.
- WSL installed with a default distribution for `run_wsl`.

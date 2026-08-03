# PowerShell + WSL local for Codex

Local plugin that exposes five MCP tools:

- `run_powershell`: execute Windows PowerShell.
- `run_wsl`: execute Bash in the default WSL distribution.
- `create_managed_temp`: create a managed temp in Windows or WSL.
- `list_managed_temps`: show active temps for this instance.
- `cleanup_managed_temp`: clean up a managed temp via its opaque handle.

## Installation

Both modes run the same installation logic. The installer registers the
checkout as the local `personal` marketplace, generates `.mcp.json` from
`.mcp.template.json` with the absolute local server path (the launch mode
that allows WSL from ChatGPT for Windows), installs `local-shell-wsl@personal`,
and removes the legacy global `local-shell-host` MCP entry if it exists.

If `codex` is not on the `PATH`, the installer extracts a runnable CLI copy
from the OpenAI Codex Microsoft Store app.

### Local mode (personal)

Clone the repository anywhere and run the installer from the clone:

```powershell
git clone https://github.com/frudas24/PluginChatgptPowershellPlusWSL.git
Set-Location .\PluginChatgptPowershellPlusWSL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-local-shell-wsl.ps1
```

### Remote mode (from GitHub)

One command; requires Git for Windows. It clones (or fast-forwards) the
repository into `%LOCALAPPDATA%\Frudas24\PluginChatgptPowershellPlusWSL` and
then runs the same local installer from that checkout:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/frudas24/PluginChatgptPowershellPlusWSL/main/scripts/install.ps1)))
```

### Updating

Rerun the same command you used to install. Then fully close Codex, reopen
it, and start or fork a conversation before invoking `@local-shell-wsl`.

## Security

The server blocks common destructive patterns, limits retained output to
120 KB per stream, and uses `taskkill /T` to stop timed-out Windows process
trees. Managed cleanup does not accept arbitrary paths: only handles created
by the current instance are accepted, the canonical path is validated, and
links or mount points are rejected. Graceful server shutdown cleans active
managed temps; a crash can still leave a temp behind. This is a preventive
barrier, not full isolation: any local terminal carries risk. Always review
the execution request that Codex displays.

## Requirements

- Windows PowerShell 5.1 or later.
- WSL installed with a default distribution for `run_wsl`.
- The OpenAI Codex Microsoft Store app, or the `codex` CLI on the `PATH`.
- Git for Windows, only for the initial clone or remote mode.

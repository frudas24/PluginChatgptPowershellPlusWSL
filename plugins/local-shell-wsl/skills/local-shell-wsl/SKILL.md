---
name: local-shell-wsl
description: Use local PowerShell or WSL to inspect, diagnose, and work with the user's machine, including isolated tests in managed temps.
---

# PowerShell + WSL local

Use `run_powershell` for Windows commands and `run_wsl` for Linux commands in the default WSL distribution.

For tests that need temporary files:

1. Use `create_managed_temp` and keep the returned `handle`.
2. Run setup and test inside the returned path.
3. Use `cleanup_managed_temp` with the `handle`; never rephrase a blocked deletion.
4. If cleanup is rejected due to links or mounts, report the path and stop.

`cleanup_managed_temp` only accepts handles issued by the current instance. Use `list_managed_temps` to review active temps.

Before running:

- Briefly explain what will be inspected or changed.
- Prefer read-only commands.
- Keep the working directory within the user-specified path.
- Do not attempt to bypass destructive-command blocking.
- For cleaning up managed temps, use only `cleanup_managed_temp`.
- If you need to delete any other path, format, restart, or overwrite data, stop and ask the user to do it directly.

After running, summarize the result and note any non-zero exit codes.

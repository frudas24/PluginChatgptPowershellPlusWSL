# PowerShell + WSL local para Codex

Plugin local que expone dos herramientas MCP:

- `run_powershell`: ejecuta Windows PowerShell.
- `run_wsl`: ejecuta Bash en la distribución WSL predeterminada.

## Instalación

La aplicación de Microsoft Store protege su copia interna de `codex.exe`. Ejecuta el instalador incluido desde PowerShell:

```powershell
& "C:\Users\FRudas\Documents\Codex\2026-07-23\qu\outputs\install-local-shell-wsl.ps1"
```

El instalador copia la CLI a una carpeta normal bajo `%LOCALAPPDATA%`, registra el marketplace e instala el plugin. Después, cierra Codex completamente, vuelve a abrirlo y crea una tarea nueva.

## Seguridad

El servidor bloquea patrones destructivos comunes, limita cada ejecución a 120 segundos y trunca salidas excesivas. Es una barrera preventiva, no un aislamiento completo: cualquier terminal local implica riesgo. Revisa siempre la solicitud de ejecución que muestra Codex.

## Requisitos

- Windows PowerShell 5.1 o posterior.
- WSL instalado y con una distribución predeterminada para `run_wsl`.

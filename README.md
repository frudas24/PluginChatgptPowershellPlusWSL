# PowerShell + WSL local para Codex

Plugin local que expone cinco herramientas MCP:

- `run_powershell`: ejecuta Windows PowerShell.
- `run_wsl`: ejecuta Bash en la distribución WSL predeterminada.
- `create_managed_temp`: crea un temporal administrado en Windows o WSL.
- `list_managed_temps`: muestra temporales activos de la instancia.
- `cleanup_managed_temp`: limpia un temporal mediante su identificador opaco.

## Instalación

La aplicación de Microsoft Store protege su copia interna de `codex.exe`. Ejecuta el instalador incluido desde PowerShell:

```powershell
& "C:\Users\FRudas\Documents\Codex\2026-07-23\qu\outputs\install-local-shell-wsl.ps1"
```

El instalador copia la CLI a una carpeta normal bajo `%LOCALAPPDATA%`, registra el marketplace e instala el plugin. Después, cierra Codex completamente, vuelve a abrirlo y crea una tarea nueva.

## Seguridad

El servidor bloquea patrones destructivos comunes, limita cada ejecución a 120 segundos y trunca salidas excesivas. La limpieza administrada no acepta rutas arbitrarias: sólo identificadores creados por la instancia, valida la ruta canónica y rechaza enlaces o puntos de montaje. Es una barrera preventiva, no un aislamiento completo: cualquier terminal local implica riesgo. Revisa siempre la solicitud de ejecución que muestra Codex.

## Requisitos

- Windows PowerShell 5.1 o posterior.
- WSL instalado y con una distribución predeterminada para `run_wsl`.

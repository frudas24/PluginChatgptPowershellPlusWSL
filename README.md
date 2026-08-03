# PowerShell + WSL local para Codex

Plugin local que expone cinco herramientas MCP:

- `run_powershell`: ejecuta Windows PowerShell.
- `run_wsl`: ejecuta Bash en la distribución WSL predeterminada.
- `create_managed_temp`: crea un temporal administrado en Windows o WSL.
- `list_managed_temps`: muestra temporales activos de la instancia.
- `cleanup_managed_temp`: limpia un temporal mediante su identificador opaco.

## Instalación en cualquier equipo

Requiere la aplicación de escritorio Codex instalada desde Microsoft Store. No hace falta que el comando `codex` esté en el `PATH`: el instalador extrae una copia ejecutable de la CLI de la aplicación.

```powershell
git clone https://github.com/frudas24/PluginChatgptPowershellPlusWSL.git
Set-Location .\PluginChatgptPowershellPlusWSL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-local-shell-wsl.ps1
```

El instalador registra este repositorio como marketplace local `personal`, genera la configuración MCP con la ruta local correcta e instala `local-shell-wsl@personal`. También elimina el antiguo host global `local-shell-host` si existía; el plugin es autosuficiente.

Al terminar, cierra Codex por completo, vuelve a abrirlo y crea o bifurca una conversación. Invoca `@local-shell-wsl` y pide, por ejemplo, `ejecuta pwd && ls en WSL`.

Para actualizar una copia existente, ejecuta el mismo instalador desde la carpeta clonada y vuelve a abrir/forkear la conversación.

## Seguridad

El servidor bloquea patrones destructivos comunes, limita cada ejecución a 120 segundos y trunca salidas excesivas. La limpieza administrada no acepta rutas arbitrarias: sólo identificadores creados por la instancia, valida la ruta canónica y rechaza enlaces o puntos de montaje. Es una barrera preventiva, no un aislamiento completo: cualquier terminal local implica riesgo. Revisa siempre la solicitud de ejecución que muestra Codex.

## Requisitos

- Windows PowerShell 5.1 o posterior.
- WSL instalado y con una distribución predeterminada para `run_wsl`.
- Git, sólo para el comando de clonación inicial.

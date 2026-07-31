---
name: local-shell-wsl
description: Usa PowerShell local o WSL para inspeccionar, diagnosticar y trabajar con el equipo del usuario cuando lo solicite.
---

# PowerShell + WSL local

Usa `run_powershell` para comandos de Windows y `run_wsl` para comandos Linux en la distribución WSL predeterminada.

Antes de ejecutar:

- Explica brevemente qué se inspeccionará o cambiará.
- Prefiere comandos de solo lectura.
- Mantén el directorio de trabajo dentro de la ruta indicada por el usuario.
- No intentes evadir el bloqueo de comandos destructivos.
- Si hace falta eliminar, formatear, reiniciar o sobrescribir datos, detente y pide al usuario hacerlo directamente.

Después de ejecutar, resume el resultado y menciona cualquier código de salida distinto de cero.

---
name: local-shell-wsl
description: Usa PowerShell local o WSL para inspeccionar, diagnosticar y trabajar con el equipo del usuario, incluyendo pruebas aisladas en temporales administrados.
---

# PowerShell + WSL local

Usa `run_powershell` para comandos de Windows y `run_wsl` para comandos Linux en la distribución WSL predeterminada.

Para pruebas que necesiten archivos temporales:

1. Usa `create_managed_temp` y conserva el `handle` devuelto.
2. Ejecuta la preparación y la prueba dentro de la ruta devuelta.
3. Usa `cleanup_managed_temp` con el `handle`; nunca reformules una eliminación bloqueada.
4. Si la limpieza se rechaza por enlaces o montajes, informa la ruta y detente.

`cleanup_managed_temp` sólo acepta identificadores emitidos por la instancia actual. Usa `list_managed_temps` para revisar temporales activos.

Antes de ejecutar:

- Explica brevemente qué se inspeccionará o cambiará.
- Prefiere comandos de solo lectura.
- Mantén el directorio de trabajo dentro de la ruta indicada por el usuario.
- No intentes evadir el bloqueo de comandos destructivos.
- Para limpiar temporales administrados, usa exclusivamente `cleanup_managed_temp`.
- Si hace falta eliminar cualquier otra ruta, formatear, reiniciar o sobrescribir datos, detente y pide al usuario hacerlo directamente.

Después de ejecutar, resume el resultado y menciona cualquier código de salida distinto de cero.

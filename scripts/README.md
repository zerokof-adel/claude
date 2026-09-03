# scripts

## Reinstall-ClaudeCode.ps1

Reinstalación limpia de Claude Code en Windows (PowerShell, sin privilegios de administrador).

### Uso

```powershell
# 1. Solo diagnóstico: inventaria instalaciones y PATH, no modifica nada.
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-ClaudeCode.ps1 -DiagnoseOnly

# 2. Reinstalación conservando login, MCP e historial.
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-ClaudeCode.ps1

# 3. Reinstalación total (DESTRUCTIVO: borra %USERPROFILE%\.claude y .claude.json).
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-ClaudeCode.ps1 -PurgeConfig
```

### Fases

| Fase | Acción | Reversible |
|------|--------|-----------|
| 1 | Diagnóstico: cuenta y elevación, directorio de trabajo, arquitectura, `where.exe claude`, binario nativo, WinGet, npm global, PATH de usuario, config | sí (solo lectura) |
| 2 | Purga de binarios y registros de paquete | no |
| 3 | Instalador nativo oficial `https://claude.ai/install.ps1` | — |
| 4 | Agrega `%USERPROFILE%\.local\bin` al PATH de usuario si falta | sí |
| 5 | Verificación: `claude --version` y `claude doctor` | sí (solo lectura) |

### Precondiciones

- **No elevar.** Ejecutar en PowerShell normal, sin "Ejecutar como administrador". `$env:USERPROFILE` y el PATH de usuario se resuelven según la cuenta del proceso: si el UAC eleva con otra cuenta de administrador, el binario y el PATH quedan en el perfil equivocado y `claude` sigue fallando en la sesión habitual. El script detecta la elevación y advierte.
- Cerrar todas las instancias de Claude Code. Windows bloquea `claude.exe` mientras el proceso corre y la purga falla.
- Usar `Windows PowerShell` de 64 bits, no la entrada `(x86)`. Claude Code no soporta procesos de 32 bits.
- Reiniciar la terminal después de la fase 4: el PATH se lee al iniciar el proceso.
- No lanzar `claude` desde `C:\Windows\system32`. Claude Code trata el directorio actual como el proyecto.

### Casos que el script detecta pero no corrige

- **`Claude.exe` de la app de escritorio en `WindowsApps`**: versiones antiguas de Claude Desktop registran un ejecutable con prioridad de PATH sobre el CLI. El script lo marca como advertencia; la corrección es actualizar Claude Desktop.
- **PowerShell de 32 bits**: advertencia, sin corrección automática.
- **Sesión elevada**: advertencia con la cuenta y el perfil resueltos, para verificar que correspondan al usuario habitual.
- **Directorio de trabajo bajo `%SystemRoot%`**: advertencia.

### Referencia

- Instalación: https://code.claude.com/docs/en/setup
- Diagnóstico de instalación: https://code.claude.com/docs/en/troubleshoot-install

<#
.SYNOPSIS
    Diagnostico y reinstalacion limpia de Claude Code en Windows.

.DESCRIPTION
    Ejecuta cinco fases:
      1. Diagnostico  : inventaria todas las instalaciones y el PATH de usuario.
      2. Purga        : elimina binarios y registros de paquete (no toca configuracion).
      3. Instalacion  : instalador nativo oficial (https://claude.ai/install.ps1).
      4. PATH         : agrega %USERPROFILE%\.local\bin al PATH de usuario si falta.
      5. Verificacion : claude --version y claude doctor.

    Por defecto NO borra ~/.claude ni ~/.claude.json, de modo que se conservan
    la sesion autenticada, los servidores MCP y el historial. Usar -PurgeConfig
    solo si la reinstalacion simple no resuelve el problema.

.PARAMETER DiagnoseOnly
    Ejecuta solo la fase 1 y termina. No modifica nada.

.PARAMETER PurgeConfig
    Elimina tambien %USERPROFILE%\.claude y %USERPROFILE%\.claude.json.
    DESTRUCTIVO: se pierden login, configuracion MCP e historial de sesiones.

.NOTES
    No requiere privilegios de administrador. Cerrar todas las instancias de
    Claude Code antes de ejecutar: Windows bloquea claude.exe mientras corre.
#>

[CmdletBinding()]
param(
    [switch]$DiagnoseOnly,
    [switch]$PurgeConfig
)

$ErrorActionPreference = 'Continue'

function Write-Phase { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Item  { param([string]$Text) Write-Host "  $Text" }

$BinPath     = Join-Path $env:USERPROFILE '.local\bin'
$ExePath     = Join-Path $BinPath 'claude.exe'
$VersionsDir = Join-Path $env:USERPROFILE '.local\share\claude'
$LegacyLocal = Join-Path $env:USERPROFILE '.claude\local'
$ConfigDir   = Join-Path $env:USERPROFILE '.claude'
$ConfigFile  = Join-Path $env:USERPROFILE '.claude.json'

# --------------------------------------------------------------------------
Write-Phase '1/5 Diagnostico'

if ([Environment]::Is64BitProcess) {
    Write-Item 'Proceso PowerShell: 64-bit (OK)'
} else {
    Write-Warning 'Proceso PowerShell: 32-bit (x86). Claude Code NO soporta 32-bit. Abrir "Windows PowerShell", no "(x86)".'
}

$found = @(where.exe claude 2>$null)
if ($found.Count -eq 0) {
    Write-Item 'where.exe claude   -> ninguna coincidencia en el PATH'
} else {
    Write-Item 'where.exe claude   ->'
    foreach ($p in $found) {
        if ($p -like '*WindowsApps*') {
            Write-Warning "    $p  <-- app de escritorio, tiene prioridad sobre el CLI. Actualizar Claude Desktop."
        } else {
            Write-Item "    $p"
        }
    }
}

Write-Item ("Binario nativo      -> {0}" -f $(if (Test-Path $ExePath) { $ExePath } else { 'ausente' }))
Write-Item ("Directorio versiones-> {0}" -f $(if (Test-Path $VersionsDir) { $VersionsDir } else { 'ausente' }))
Write-Item ("Instalacion legacy  -> {0}" -f $(if (Test-Path $LegacyLocal) { $LegacyLocal } else { 'ausente' }))

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$winget = if ($hasWinget) { (winget list --id Anthropic.ClaudeCode --exact 2>$null | Out-String) } else { '' }
Write-Item ("Paquete WinGet      -> {0}" -f $(
    if (-not $hasWinget)                          { 'winget no disponible' }
    elseif ($winget -match 'Anthropic\.ClaudeCode') { 'PRESENTE' }
    else                                          { 'ausente' }))

$npmls = ''
if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmls = (npm -g ls '@anthropic-ai/claude-code' --depth 0 2>$null | Out-String)
    Write-Item ("Paquete npm global  -> {0}" -f $(if ($npmls -match 'claude-code@') { 'PRESENTE' } else { 'ausente' }))
} else {
    Write-Item 'Paquete npm global  -> npm no instalado'
}

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
Write-Item ("PATH de usuario     -> {0}" -f $(if ($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $BinPath.TrimEnd('\')) }) { 'contiene .local\bin' } else { 'NO contiene .local\bin' }))

Write-Item ("Configuracion       -> {0} / {1}" -f `
    $(if (Test-Path $ConfigDir)  { '.claude presente' }      else { '.claude ausente' }), `
    $(if (Test-Path $ConfigFile) { '.claude.json presente' } else { '.claude.json ausente' }))

if ($DiagnoseOnly) { Write-Host "`nDiagnostico completo. Sin cambios aplicados." -ForegroundColor Green; return }

# --------------------------------------------------------------------------
Write-Phase '2/5 Purga de instalaciones previas'

if (Get-Process -Name 'claude' -ErrorAction SilentlyContinue) {
    Write-Warning 'Hay un proceso claude.exe en ejecucion. Cerrarlo y volver a ejecutar este script.'
    return
}

if ($winget -match 'Anthropic\.ClaudeCode') {
    Write-Item 'Desinstalando paquete WinGet...'
    winget uninstall --id Anthropic.ClaudeCode --exact --silent 2>&1 | Out-Null
}

if ((Get-Command npm -ErrorAction SilentlyContinue) -and ($npmls -match 'claude-code@')) {
    Write-Item 'Desinstalando paquete npm global...'
    npm uninstall -g '@anthropic-ai/claude-code' 2>&1 | Out-Null
}

foreach ($target in @($ExePath, $VersionsDir, $LegacyLocal)) {
    if (Test-Path $target) {
        Write-Item "Eliminando $target"
        Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($PurgeConfig) {
    Write-Warning 'PurgeConfig activo: se eliminan login, configuracion MCP e historial.'
    foreach ($target in @($ConfigDir, $ConfigFile)) {
        if (Test-Path $target) {
            Write-Item "Eliminando $target"
            Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# --------------------------------------------------------------------------
Write-Phase '3/5 Instalacion nativa'

Write-Item 'Descargando y ejecutando https://claude.ai/install.ps1 ...'
try {
    Invoke-Expression (Invoke-RestMethod -Uri 'https://claude.ai/install.ps1')
} catch {
    Write-Error "Fallo la instalacion: $($_.Exception.Message)"
    Write-Item 'Alternativa: winget install Anthropic.ClaudeCode'
    return
}

# --------------------------------------------------------------------------
Write-Phase '4/5 PATH de usuario'

$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$already  = $userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ieq $BinPath.TrimEnd('\')) }

if ($already) {
    Write-Item "$BinPath ya estaba en el PATH de usuario."
} else {
    $newPath = if ([string]::IsNullOrEmpty($userPath)) { $BinPath } else { "$userPath;$BinPath" }
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Item "Agregado $BinPath al PATH de usuario. Reiniciar la terminal para que aplique."
}

# PATH del proceso actual, solo para verificar sin reiniciar la terminal.
if ($env:PATH -notlike "*$BinPath*") { $env:PATH = "$env:PATH;$BinPath" }

# --------------------------------------------------------------------------
Write-Phase '5/5 Verificacion'

if (-not (Test-Path $ExePath)) {
    Write-Warning "No se encontro $ExePath tras la instalacion. Revisar la salida del instalador."
    return
}

$version = (& $ExePath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -eq 0 -and $version) {
    Write-Host "  claude --version -> $version" -ForegroundColor Green
    Write-Item 'Ejecutando claude doctor...'
    & $ExePath doctor
    Write-Host "`nListo. Cerrar y reabrir la terminal, luego ejecutar: claude" -ForegroundColor Green
} else {
    Write-Warning "El binario no responde. Salida: $version"
    Write-Item 'Revisar https://code.claude.com/docs/en/troubleshoot-install'
}

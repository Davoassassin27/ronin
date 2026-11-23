# =============================================================================
# Ronin - stop QEMU VM
# =============================================================================
param(
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$pidFile = Get-VmPidFile -Config $config

if (-not (Test-Path -LiteralPath $pidFile)) {
  Write-Warn 'No hay PID de VM. Nada que apagar.'
  exit 0
}

$pidValue = (Get-Content -LiteralPath $pidFile -Raw).Trim()
if ($pidValue -notmatch '^\d+$') {
  Write-Warn "PID invalido en $pidFile"
  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  exit 0
}

$process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
if (-not $process) {
  Write-Warn "El proceso $pidValue ya no existe."
  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
  exit 0
}

if (-not $Force) {
  Write-Info 'Intentando apagado ordenado por SSH...'
  $code = 1
  try {
    $code = Invoke-Ssh -Config $config -User 'root' -Command 'sync; systemctl poweroff' 2>$null
  } catch {
    $code = 1
  }
  if ($code -eq 0) {
    Write-Info 'Apagado solicitado; esperando...'
    for ($i = 0; $i -lt 30; $i++) {
      Start-Sleep -Seconds 2
      if (-not (Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue)) { break }
    }
  }
}

$still = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
if ($still) {
  Write-Warn "Forzando cierre del proceso $pidValue..."
  Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
$still = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
if ($still) {
  Write-Fail "No se pudo cerrar QEMU (PID $pidValue)."
  exit 1
}
Write-Ok 'VM detenida.'
exit 0

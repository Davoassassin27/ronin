# =============================================================================
# Ronin - host CLI
# =============================================================================
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Arg1 = '',
  [switch]$Force,
  [switch]$Iso,
  [switch]$Gl,
  [switch]$Tcg,
  [switch]$Whpx,
  [switch]$ResetNvram,
  [switch]$Finalize,
  [switch]$SkipHash,
  [string]$Display = '',
  [string]$Image = '',
  [string]$ExtraDisk = '',
  [string]$User = 'root'
)

$ErrorActionPreference = 'Stop'
$hostDir = Join-Path $PSScriptRoot 'build\scripts\host'
. (Join-Path $hostDir 'lib.ps1')

function Invoke-HostScript {
  param(
    [string]$Name,
    [hashtable]$Params = @{}
  )
  $path = Join-Path $hostDir $Name
  if (-not (Test-Path -LiteralPath $path)) {
    throw "No existe $path"
  }
  $global:LASTEXITCODE = 0
  & $path @Params
  return $LASTEXITCODE
}

function Show-Help {
  Write-Host ''
  Write-Host 'Ronin - build CLI' -ForegroundColor White
  Write-Host ''
  Write-Host 'Uso: .\build.ps1 <comando> [opciones]' -ForegroundColor Gray
  Write-Host ''
  Write-Host 'Host:' -ForegroundColor Cyan
  Write-Host '  doctor          Diagnostico completo del host'
  Write-Host '  install-qemu    Instala/verifica QEMU y WHPX'
  Write-Host '  fetch-iso       Descarga y verifica la ISO de CachyOS'
  Write-Host '  image           Crea la imagen cruda y la NVRAM UEFI'
  Write-Host '  status          Estado de imagen, VM y configuracion'
  Write-Host '  lint            Valida sintaxis de scripts y JSON
  test-unit       Unit tests + trazabilidad UX (reports/unit-*.json)'
  Write-Host ''
  Write-Host 'VM:' -ForegroundColor Cyan
  Write-Host '  up              Arranca la VM desde el disco'
  Write-Host '  up-iso          Arranca la VM desde la ISO (instalacion)'
  Write-Host '  wait-ssh        Espera a que el guest acepte SSH'
  Write-Host '  ssh             Abre shell SSH (root por defecto)'
  Write-Host '  down            Apaga la VM (-Force para matar)'
  Write-Host '  live-ssh        Prepara el HTTP server para inyectar la clave SSH en el live'
  Write-Host '  push            Copia build/ al guest'
  Write-Host '  run <script>    Ejecuta un script de guest (ej: 40-hw-adapt.sh)'
  Write-Host '  provision       Ejecuta 40 -> 90 (stack completo)'
  Write-Host '  finalize        Ejecuta 95 (deshabilita root SSH)'
  Write-Host '  verify          Ejecuta 90 y trae el reporte a reports/'
  Write-Host ''
  Write-Host 'Opciones:' -ForegroundColor Cyan
  Write-Host '  -Display gtk|sdl|none   Consola grafica (default: build.env)'
  Write-Host '  -Gl                     Aceleracion GL (virtio-vga-gl)'
  Write-Host '  -Tcg                    Fuerza TCG (default en build.env)'
  Write-Host '  -Whpx                   Intenta WHPX (experimental en este host)'
  Write-Host '  -ExtraDisk <path>       Segundo disco (migracion)'
  Write-Host '  -Image <path>           Imagen alternativa'
  Write-Host '  -Force                  Recrear imagen / matar VM'
  Write-Host '  -ResetNvram             Resetear NVRAM UEFI'
  Write-Host '  -Finalize               Incluir 95 en provision'
  Write-Host ''
  Write-Host 'Ejemplos:' -ForegroundColor Gray
  Write-Host '  .\build.ps1 doctor'
  Write-Host '  .\build.ps1 up-iso -Display gtk'
  Write-Host '  .\build.ps1 push'
  Write-Host '  .\build.ps1 run 10-partition.sh'
  Write-Host '  .\build.ps1 provision'
  Write-Host '  .\build.ps1 verify'
  Write-Host ''
}

switch ($Command.ToLower()) {
  'help' { Show-Help; exit 0 }

  'doctor' {
    exit (Invoke-HostScript '00-check-host.ps1' @{ SkipHash = $SkipHash })
  }

  'install-qemu' {
    exit (Invoke-HostScript '01-install-qemu.ps1')
  }

  'fetch-iso' {
    exit (Invoke-HostScript '02-fetch-iso.ps1' @{ Force = $Force })
  }

  'image' {
    exit (Invoke-HostScript '03-create-image.ps1' @{ Force = $Force; ResetNvram = $ResetNvram })
  }

  'up' {
    exit (Invoke-HostScript '04-start-vm.ps1' @{
      Image = $Image; ExtraDisk = $ExtraDisk; Display = $Display; Gl = $Gl; Tcg = $Tcg; Whpx = $Whpx
    })
  }

  'up-iso' {
    exit (Invoke-HostScript '04-start-vm.ps1' @{
      Iso = $true; Image = $Image; ExtraDisk = $ExtraDisk; Display = $Display; Gl = $Gl; Tcg = $Tcg; Whpx = $Whpx
    })
  }

  'wait-ssh' {
    exit (Invoke-HostScript '05-wait-ssh.ps1')
  }

  'ssh' {
    exit (Invoke-HostScript '06-ssh.ps1' @{ User = $User })
  }

  'down' {
    exit (Invoke-HostScript '07-stop-vm.ps1' @{ Force = $Force })
  }

  'live-ssh' {
    exit (Invoke-HostScript '10-bootstrap-live.ps1')
  }

  'push' {
    exit (Invoke-HostScript '08-push.ps1' @{ User = $User })
  }

  'run' {
    if (-not $Arg1) {
      Write-Host 'Falta el nombre del script. Ej: .\build.ps1 run 40-hw-adapt.sh' -ForegroundColor Red
      exit 2
    }
    exit (Invoke-HostScript '09-run-guest.ps1' @{ Script = $Arg1; User = $User })
  }

  'provision' {
    $code = Invoke-HostScript '08-push.ps1' @{ User = 'root' }
    if ($code -ne 0) { exit $code }

    $scripts = @(
      '40-hw-adapt.sh',
      '50-omarchy.sh',
      '60-dev-ai.sh',
      '70-gaming.sh',
      '80-harden.sh',
      '90-verify.sh'
    )
    if ($Finalize) { $scripts += '95-finalize.sh' }

    foreach ($script in $scripts) {
      Write-Host ''
      Write-Host ("### $script") -ForegroundColor Magenta
      $code = Invoke-HostScript '09-run-guest.ps1' @{ Script = $script; User = 'root' }
      if ($code -ne 0) {
        Write-Host "Fallo $script (codigo $code)." -ForegroundColor Red
        Write-Host 'Corregir y reanudar con: .\build.ps1 run <script>' -ForegroundColor Yellow
        exit $code
      }
    }
    if ($Finalize) {
      Write-Host 'Root SSH deshabilitado. Usar -User davos para SSH.' -ForegroundColor Yellow
    }
    exit 0
  }

  'finalize' {
    exit (Invoke-HostScript '09-run-guest.ps1' @{ Script = '95-finalize.sh'; User = 'root' })
  }

  'verify' {
    $reports = Join-Path $PSScriptRoot 'reports'
    if (-not (Test-Path -LiteralPath $reports)) { New-Item -ItemType Directory -Force -Path $reports | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $remote = '/var/log/ronin-verify.json'
    $local = Join-Path $reports "verify-$stamp.json"

    $cfg = Get-BuildConfig
    $targetUser = Get-ConfigValue $cfg 'TARGET_USER' 'davos'
    $user = 'root'
    $code = Invoke-HostScript '09-run-guest.ps1' @{ Script = '90-verify.sh'; User = $user }
    if ($code -ne 0 -and $code -ne 1) {
      Write-Warn 'SSH root fallo; intentando como usuario con sudo -n...'
      $user = $targetUser
      $code = Invoke-HostScript '09-run-guest.ps1' @{ Script = '90-verify.sh'; User = $user; Sudo = $true }
    }

    # Pull report (best effort)
    $scp = Get-Command scp.exe -ErrorAction SilentlyContinue
    if ($scp) {
      $key = Resolve-ProjectPath (Get-ConfigValue $cfg 'SSH_KEY' "$HOME\.ssh\ronin_ed25519")
      $port = Get-ConfigValue $cfg 'SSH_PORT' '2222'
      $scpArgs = @('-P', $port, '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=NUL', '-o', 'LogLevel=ERROR')
      if (Test-Path -LiteralPath $key) { $scpArgs += @('-i', $key) }
      $scpArgs += "${user}@127.0.0.1:$remote"
      $scpArgs += $local
      & scp.exe @scpArgs 2>$null
      if (Test-Path -LiteralPath $local) {
        Write-Ok "Reporte copiado: $local"
      }
    }

    exit $code
  }

  'status' {
    Write-Host ''
    Write-Host 'Ronin - status' -ForegroundColor White
    $cfgPath = Join-Path $PSScriptRoot 'build\build.env'
    Write-Info "Config: $cfgPath"
    if (Test-Path -LiteralPath $cfgPath) {
      Get-Content -LiteralPath $cfgPath | Select-String -Pattern '^(IMAGE_|VM_|ISO_|TARGET_HOSTNAME|TARGET_USER|SSH_PORT)' |
        ForEach-Object { Write-Host ('  ' + $_.Line) }
    }
    $pidFile = Get-VmPidFile -Config (Get-BuildConfig)
    if (Test-Path -LiteralPath $pidFile) {
      $p = (Get-Content -LiteralPath $pidFile -Raw).Trim()
      if ($p -match '^\d+$') {
        $proc = Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue
        if ($proc) { Write-Ok "VM corriendo (PID $p)" } else { Write-Warn "PID $p no existe (stale)" }
      } else {
        Write-Warn "PID invalido: $p"
      }
    } else {
      Write-Info 'VM detenida.'
    }
    exit 0
  }

  'lint' {
    $lint = Join-Path $PSScriptRoot 'tests\lint.ps1'
    if (-not (Test-Path -LiteralPath $lint)) { throw "No existe $lint" }
    & $lint
    exit $LASTEXITCODE
  }

  'test-unit' {
    $unit = Join-Path $PSScriptRoot 'tests\unit\run-unit-tests.ps1'
    if (-not (Test-Path -LiteralPath $unit)) { throw "No existe $unit" }
    & $unit
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    exit ([int]$code)
  }

  default {
    Write-Host "Comando desconocido: $Command" -ForegroundColor Red
    Show-Help
    exit 2
  }
}

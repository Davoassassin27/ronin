# =============================================================================
# Ronin - install / verify QEMU on Windows
# =============================================================================
. (Join-Path $PSScriptRoot 'lib.ps1')

Write-Step 'QEMU'

$qemu = $null
try {
  $qemu = Get-QemuExe
  Write-Ok "QEMU ya instalado: $qemu"
} catch {
  Write-Info 'QEMU no encontrado; instalando con winget...'
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) {
    Write-Fail 'winget no disponible. Instalar QEMU manualmente desde https://qemu.weilnetz.de/w64/'
    exit 1
  }
  & $winget.Source install --id SoftwareFreedomConservancy.QEMU -e `
    --accept-package-agreements --accept-source-agreements --silent --disable-interactivity
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "winget fallo con codigo $LASTEXITCODE"
    exit 1
  }

  # Refresh PATH for this process.
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machinePath;$userPath"
  $qemu = Get-QemuExe
  Write-Ok "QEMU instalado: $qemu"
}

$version = (& $qemu --version 2>&1 | Select-Object -First 1)
Write-Info $version

$ovmf = Get-OvmfPaths
foreach ($item in @(
  @{ Name = 'OVMF code'; Path = $ovmf.Code },
  @{ Name = 'OVMF vars'; Path = $ovmf.VarsTemplate }
)) {
  if ($item.Path -and (Test-Path -LiteralPath $item.Path)) {
    Write-Ok "$($item.Name): $($item.Path)"
  } else {
    Write-Fail "$($item.Name) no encontrado"
    exit 1
  }
}

if (Test-WHpx) {
  $probe = Test-WHpxRuntime
  if ($probe.Ok) {
    Write-Ok 'WHPX operativo (aceleracion por hardware)'
  } else {
    Write-Warn 'WHPX compilado pero no operativo.'
    Write-Warn $probe.Detail
    Write-Info 'Para habilitarlo (admin + reboot):'
    Write-Info '  Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All'
    Write-Info 'Mientras tanto, build.ps1 usara TCG (mucho mas lento).'
  }
} else {
  Write-Warn 'WHPX no compilado en este build de QEMU; se usara TCG.'
}

Write-Host ''
Write-Host 'Siguiente: .\build.ps1 fetch-iso' -ForegroundColor Cyan
exit 0

# =============================================================================
# Ronin - download CachyOS ISO and verify SHA-256
# =============================================================================
param(
  [switch]$Force
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$isoDir = Resolve-ProjectPath (Get-ConfigValue $config 'ISO_DIR' 'build/iso')
$isoName = Get-ConfigValue $config 'ISO_NAME' 'cachyos-desktop-linux-260809.iso'
$isoUrl = Get-ConfigValue $config 'ISO_URL'
$shaUrl = Get-ConfigValue $config 'ISO_SHA256_URL'
$expected = (Get-ConfigValue $config 'ISO_SHA256' '').ToLower()

New-Directory $isoDir
$isoPath = Join-Path $isoDir $isoName
$shaPath = Join-Path $isoDir ($isoName + '.sha256')

Write-Step "ISO CachyOS: $isoName"
Write-Info "Destino: $isoPath"

# 1. Checksum file
if (-not (Test-Path -LiteralPath $shaPath) -or $Force) {
  Write-Info "Descargando checksum: $shaUrl"
  curl.exe -fsSL --retry 3 -o $shaPath $shaUrl
  if ($LASTEXITCODE -ne 0) {
    Write-Fail 'No se pudo descargar el checksum.'
    exit 1
  }
}
$shaLine = (Get-Content -LiteralPath $shaPath -Raw).Trim()
if ($shaLine -match '^([0-9a-fA-F]{64})') {
  $expected = $matches[1].ToLower()
}
if (-not $expected) {
  Write-Fail 'No hay SHA-256 esperado en build.env ni en el archivo .sha256.'
  exit 1
}
Write-Info "SHA-256 esperado: $expected"

# 2. Existing file?
if ((Test-Path -LiteralPath $isoPath) -and -not $Force) {
  $actual = (Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash.ToLower()
  if ($actual -eq $expected) {
    $sizeGb = [math]::Round((Get-Item -LiteralPath $isoPath).Length / 1GB, 2)
    Write-Ok "ISO ya presente y verificada ($sizeGb GiB)."
    exit 0
  }
  Write-Warn 'La ISO existe pero el hash no coincide; se reanudara/descargara de nuevo.'
}

# 3. Download
$sizeHint = '3 GiB'
Write-Info "Descargando ($sizeHint)..."
if ($Force -and (Test-Path -LiteralPath $isoPath)) {
  Remove-Item -LiteralPath $isoPath -Force
}
curl.exe -L --fail --retry 3 --retry-delay 5 -C - -o $isoPath $isoUrl
if ($LASTEXITCODE -ne 0) {
  Write-Fail "curl fallo con codigo $LASTEXITCODE. Reintentar el script (resume automatico)."
  exit 1
}

# 4. Verify
Write-Info 'Verificando SHA-256...'
$actual = (Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) {
  Write-Fail "Hash no coincide.`n  esperado: $expected`n  actual:   $actual"
  Write-Info "El archivo quedo en $isoPath; borrarlo o usar -Force."
  exit 1
}

$sizeGb = [math]::Round((Get-Item -LiteralPath $isoPath).Length / 1GB, 2)
Write-Ok "ISO verificada: $isoName ($sizeGb GiB)"
Write-Host ''
Write-Host 'Siguiente: .\build.ps1 image' -ForegroundColor Cyan
exit 0

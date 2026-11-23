# =============================================================================
# Ronin - create raw image + UEFI NVRAM
# =============================================================================
param(
  [switch]$Force,
  [switch]$ResetNvram
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$imageDir = Resolve-ProjectPath (Get-ConfigValue $config 'IMAGE_DIR' 'E:/work-os/images')
$imageName = Get-ConfigValue $config 'IMAGE_NAME' 'ronin.img'
$imageSize = Get-ConfigValue $config 'IMAGE_SIZE' '120G'
$imagePath = Join-Path $imageDir $imageName
$varsPath = Join-Path $imageDir 'edk2-vars.fd'

Write-Step 'Imagen de construccion'
New-Directory $imageDir

$sizeBytes = ConvertTo-Bytes $imageSize
$freeGb = Get-FreeSpaceGB -Path $imageDir
$requiredGb = [math]::Round($sizeBytes / 1GB, 1) + 10
Write-Info "Directorio: $imageDir"
Write-Info ("Espacio libre: {0} GiB (requiere ~{1} GiB)" -f $freeGb, $requiredGb)
if ($freeGb -lt $requiredGb) {
  Write-Fail 'Espacio insuficiente. Liberar espacio o cambiar IMAGE_DIR/IMAGE_SIZE en build.env.'
  exit 1
}

$qemuImg = Get-QemuImgExe

if (Test-Path -LiteralPath $imagePath) {
  if ($Force) {
    Write-Warn "Eliminando imagen existente por -Force: $imagePath"
    Remove-Item -LiteralPath $imagePath -Force
  } else {
    $info = & $qemuImg info $imagePath 2>&1 | Out-String
    Write-Warn 'La imagen ya existe; no se sobreescribe (usar -Force para recrear).'
    Write-Host $info
  }
}

if (-not (Test-Path -LiteralPath $imagePath)) {
  Write-Info "Creando imagen cruda de $imageSize..."
  & $qemuImg create -f raw $imagePath $imageSize
  if ($LASTEXITCODE -ne 0) {
    Write-Fail 'qemu-img create fallo.'
    exit 1
  }
  Write-Ok "Imagen creada: $imagePath"
}

# UEFI vars: copy the template only once (NVRAM must persist between boots).
$ovmf = Get-OvmfPaths
if (-not $ovmf.VarsTemplate -or -not (Test-Path -LiteralPath $ovmf.VarsTemplate)) {
  Write-Fail 'No se encontro la plantilla de NVRAM UEFI (edk2-*-vars.fd).'
  exit 1
}
if ($ResetNvram -and (Test-Path -LiteralPath $varsPath)) {
  Remove-Item -LiteralPath $varsPath -Force
  Write-Warn 'NVRAM reseteada.'
}
if (-not (Test-Path -LiteralPath $varsPath)) {
  Copy-Item -LiteralPath $ovmf.VarsTemplate -Destination $varsPath
  Write-Ok "NVRAM creada: $varsPath"
} else {
  Write-Info "NVRAM existente: $varsPath"
}

Write-Host ''
& $qemuImg info $imagePath
Write-Host ''
Write-Ok 'Listo. Siguiente: .\build.ps1 up-iso' -ForegroundColor Green
exit 0

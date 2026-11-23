# =============================================================================
# Ronin - host readiness check
# =============================================================================
param(
  [switch]$SkipHash
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check {
  param(
    [string]$Name,
    [ValidateSet('PASS', 'WARN', 'FAIL', 'INFO')][string]$Status,
    [string]$Detail = ''
  )
  $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
}

Write-Host ''
Write-Host 'Ronin - host readiness' -ForegroundColor White
Write-Host ('Repo: ' + (Get-RepoRoot)) -ForegroundColor DarkGray
Write-Host ('Fecha: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray

# OS / CPU / RAM
try {
  $os = Get-CimInstance Win32_OperatingSystem
  Add-Check 'Windows x64' 'PASS' ("$($os.Caption) build $($os.BuildNumber)")
} catch {
  Add-Check 'Windows x64' 'WARN' $_.Exception.Message
}

try {
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  Add-Check 'CPU' 'PASS' ("$($cpu.Name.Trim()) / $($cpu.NumberOfCores)C $($cpu.NumberOfLogicalProcessors)T")
  if ($cpu.VirtualizationFirmwareEnabled) {
    Add-Check 'Virtualizacion de firmware' 'PASS' 'habilitada'
  } else {
    Add-Check 'Virtualizacion de firmware' 'FAIL' 'deshabilitada en BIOS/UEFI'
  }
} catch {
  Add-Check 'CPU' 'WARN' $_.Exception.Message
}

try {
  $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
  $ramGb = [math]::Round($ram / 1GB, 1)
  if ($ramGb -ge 16) {
    Add-Check 'RAM' 'PASS' "$ramGb GiB"
  } else {
    Add-Check 'RAM' 'WARN' "$ramGb GiB (recomendado >= 16 GiB; el guest usa 12 GiB)"
  }
} catch {
  Add-Check 'RAM' 'WARN' $_.Exception.Message
}

try {
  $hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
  if ($hv) {
    Add-Check 'Hypervisor de Windows' 'PASS' 'presente'
  } else {
    Add-Check 'Hypervisor de Windows' 'WARN' 'ausente; WHPX podria no estar disponible'
  }
} catch {
  Add-Check 'Hypervisor de Windows' 'WARN' $_.Exception.Message
}

# QEMU
$qemu = $null
try {
  $qemu = Get-QemuExe
  $version = (& $qemu --version 2>&1 | Select-Object -First 1)
  Add-Check 'QEMU' 'PASS' $version
} catch {
  Add-Check 'QEMU' 'FAIL' 'no instalado (.\build.ps1 install-qemu)'
}

$whpx = $false
if ($qemu) {
  $whpx = Test-WHpx
  if ($whpx) {
    $probe = Test-WHpxRuntime
    if ($probe.Ok) {
      Add-Check 'WHPX' 'PASS' $probe.Detail
    } else {
      Add-Check 'WHPX' 'WARN' ("compilado pero no operativo: " + $probe.Detail)
      $whpx = $false
    }
  } else {
    Add-Check 'WHPX' 'WARN' 'no compilado; se usara TCG (lento)'
  }
}

# OVMF
try {
  $ovmf = Get-OvmfPaths
  if (Test-Path -LiteralPath $ovmf.Code) {
    Add-Check 'OVMF code' 'PASS' $ovmf.Code
  } else {
    Add-Check 'OVMF code' 'FAIL' "falta $($ovmf.Code)"
  }
  if ($ovmf.VarsTemplate -and (Test-Path -LiteralPath $ovmf.VarsTemplate)) {
    Add-Check 'OVMF vars template' 'PASS' $ovmf.VarsTemplate
  } else {
    Add-Check 'OVMF vars template' 'FAIL' 'no se encontro edk2-*-vars.fd'
  }
} catch {
  Add-Check 'OVMF' 'FAIL' $_.Exception.Message
}

# SSH / SCP
foreach ($tool in @('ssh.exe', 'scp.exe')) {
  $c = Get-Command $tool -ErrorAction SilentlyContinue
  if ($c) {
    Add-Check $tool 'PASS' $c.Source
  } else {
    Add-Check $tool 'FAIL' 'no encontrado en PATH'
  }
}

# Espacio en disco
try {
  $imageDir = Resolve-ProjectPath (Get-ConfigValue $config 'IMAGE_DIR' 'E:/work-os/images')
  $sizeBytes = ConvertTo-Bytes (Get-ConfigValue $config 'IMAGE_SIZE' '120G')
  $required = [math]::Round($sizeBytes / 1GB, 1) + 15
  $free = Get-FreeSpaceGB -Path $imageDir
  if ($free -ge $required) {
    Add-Check 'Espacio para imagen' 'PASS' "$free GiB libres en $imageDir (requiere ~$required GiB)"
  } else {
    Add-Check 'Espacio para imagen' 'FAIL' "$free GiB libres en $imageDir; requiere ~$required GiB"
  }
} catch {
  Add-Check 'Espacio para imagen' 'WARN' $_.Exception.Message
}

# ISO
try {
  $isoDir = Resolve-ProjectPath (Get-ConfigValue $config 'ISO_DIR' 'build/iso')
  $isoName = Get-ConfigValue $config 'ISO_NAME' 'cachyos-desktop-linux-260809.iso'
  $iso = Join-Path $isoDir $isoName
  if (-not (Test-Path -LiteralPath $iso)) {
    Add-Check 'ISO CachyOS' 'WARN' "falta $iso (.\build.ps1 fetch-iso)"
  } else {
    $sizeMb = [math]::Round((Get-Item -LiteralPath $iso).Length / 1MB, 0)
    if ($SkipHash) {
      Add-Check 'ISO CachyOS' 'INFO' "$isoName ($sizeMb MiB); hash no verificado (-SkipHash)"
    } else {
      $expected = (Get-ConfigValue $config 'ISO_SHA256' '').ToLower()
      $actual = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash.ToLower()
      if ($actual -eq $expected) {
        Add-Check 'ISO CachyOS' 'PASS' "$isoName ($sizeMb MiB), sha256 OK"
      } else {
        Add-Check 'ISO CachyOS' 'FAIL' "sha256 no coincide: $actual"
      }
    }
  }
} catch {
  Add-Check 'ISO CachyOS' 'WARN' $_.Exception.Message
}

# Imagen / NVRAM / clave SSH
try {
  $imageDir = Resolve-ProjectPath (Get-ConfigValue $config 'IMAGE_DIR' 'E:/work-os/images')
  $imageName = Get-ConfigValue $config 'IMAGE_NAME' 'ronin.img'
  $image = Join-Path $imageDir $imageName
  if (Test-Path -LiteralPath $image) {
    Add-Check 'Imagen' 'PASS' $image
  } else {
    Add-Check 'Imagen' 'INFO' "aun no creada ($image)"
  }
  $vars = Join-Path $imageDir 'edk2-vars.fd'
  if (Test-Path -LiteralPath $vars) {
    Add-Check 'NVRAM UEFI' 'PASS' $vars
  } else {
    Add-Check 'NVRAM UEFI' 'INFO' "se creara en .\build.ps1 image ($vars)"
  }
} catch {
  Add-Check 'Imagen' 'WARN' $_.Exception.Message
}

try {
  $key = Resolve-ProjectPath (Get-ConfigValue $config 'SSH_KEY' "$HOME\.ssh\ronin_ed25519")
  if (Test-Path -LiteralPath $key) {
    Add-Check 'Clave SSH' 'PASS' $key
  } else {
    Add-Check 'Clave SSH' 'WARN' "falta $key; generar con ssh-keygen"
  }
} catch {
  Add-Check 'Clave SSH' 'WARN' $_.Exception.Message
}

# Reporte
Write-Host ''
$checks | Format-Table -AutoSize -Property Status, Name, Detail | Out-String -Width 200 | Write-Host

$fails = @($checks | Where-Object { $_.Status -eq 'FAIL' }).Count
$warns = @($checks | Where-Object { $_.Status -eq 'WARN' }).Count
$passes = @($checks | Where-Object { $_.Status -eq 'PASS' }).Count

Write-Host ("Resumen: {0} PASS, {1} WARN, {2} FAIL" -f $passes, $warns, $fails) -ForegroundColor White
if ($fails -gt 0) {
  Write-Host 'Estado: NOT READY' -ForegroundColor Red
  exit 1
}
Write-Host 'Estado: READY (revisar WARN)' -ForegroundColor Green
exit 0

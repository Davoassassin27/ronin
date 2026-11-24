# =============================================================================
# Ronin - push build scripts/config to guest
# =============================================================================
param(
  [string]$User = 'root',
  [string]$Destination = '/root/build-scripts'
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$repo = Get-RepoRoot

Write-Step 'Copiando build/ al guest'
Invoke-Ssh -Config $config -User $User -Command "mkdir -p $Destination" | Out-Null

$items = @(
  @{ Path = (Join-Path $repo 'build\guest'); Name = 'guest' },
  @{ Path = (Join-Path $repo 'build\config'); Name = 'config' },
  @{ Path = (Join-Path $repo 'build\build.env'); Name = 'build.env' }
)

foreach ($item in $items) {
  if (-not (Test-Path -LiteralPath $item.Path)) {
    Write-Fail "Falta $($item.Path)"
    exit 1
  }
  Write-Info "scp $($item.Name)"
  $code = Invoke-Scp -Config $config -User $User -Source $item.Path -Destination "$Destination/" -Recurse
  if ($code -ne 0) {
    Write-Fail "scp fallo para $($item.Name)"
    exit 1
  }
}

$kenseiRemote = "$Destination/kensei"
Invoke-Ssh -Config $config -User $User -Command "mkdir -p $kenseiRemote/data" | Out-Null
$kenseiItems = @(
  @{ Path = (Join-Path $repo 'kensei\src'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\prompts'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\config'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\scripts'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\eval'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\packaging'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\modelfiles'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\data\manual'); Dest = "$kenseiRemote/data/" },
  @{ Path = (Join-Path $repo 'kensei\pyproject.toml'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\README.md'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\LICENSE'); Dest = "$kenseiRemote/" },
  @{ Path = (Join-Path $repo 'kensei\NOTICE'); Dest = "$kenseiRemote/" }
)
foreach ($item in $kenseiItems) {
  if (-not (Test-Path -LiteralPath $item.Path)) {
    Write-Warn "Falta $($item.Path); se omite del payload Kensei."
    continue
  }
  Write-Info "scp kensei/$(Split-Path $item.Path -Leaf)"
  $code = Invoke-Scp -Config $config -User $User -Source $item.Path -Destination $item.Dest -Recurse
  if ($code -ne 0) {
    Write-Warn "scp fallo para Kensei: $($item.Path)"
  }
}

# SSH public key -> authorized_keys (for 30-configure.sh)
$key = Resolve-ProjectPath (Get-ConfigValue $config 'SSH_KEY' "$HOME\.ssh\ronin_ed25519")
$pub = "$key.pub"
if (Test-Path -LiteralPath $pub) {
  $code = Invoke-Scp -Config $config -User $User -Source $pub -Destination "$Destination/authorized_keys"
  if ($code -ne 0) { Write-Warn 'No se pudo copiar la clave publica.' }
  else { Write-Ok 'authorized_keys copiada.' }
} else {
  Write-Warn "No existe $pub; 30-configure.sh generara acceso solo con password."
}

# Normalize permissions inside guest (Windows scp does not preserve modes).
$cmd = "chmod +x $Destination/guest/*.sh 2>/dev/null || true; chmod 600 $Destination/authorized_keys 2>/dev/null || true; ls -la $Destination"
Invoke-Ssh -Config $config -User $User -Command $cmd | Out-Null

Write-Ok 'Build scripts copiados.'
Write-Host 'Siguiente: .\build.ps1 run 00-preflight.sh' -ForegroundColor Cyan
exit 0

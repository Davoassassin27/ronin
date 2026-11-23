# =============================================================================
# Ronin - inject SSH key into the CachyOS live environment
# =============================================================================
. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$repo = Get-RepoRoot
$sshDir = Join-Path $repo 'build\ssh'
$key = Resolve-ProjectPath (Get-ConfigValue $config 'SSH_KEY' "$HOME\.ssh\ronin_ed25519")
$pub = "$key.pub"

New-Directory $sshDir
if (-not (Test-Path -LiteralPath (Join-Path $sshDir 'authorized_keys'))) {
  if (Test-Path -LiteralPath $pub) {
    Copy-Item -LiteralPath $pub -Destination (Join-Path $sshDir 'authorized_keys')
  } else {
    Write-Fail "No existe $pub"
    exit 1
  }
}

$bootstrap = @'
#!/bin/bash
set -e
mkdir -p /root/.ssh
curl -s http://10.0.2.2:8000/authorized_keys -o /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
systemctl start sshd
systemctl enable sshd
echo BOOTSTRAP_DONE
'@
Set-Content -LiteralPath (Join-Path $sshDir 'bootstrap.sh') -Value $bootstrap -Encoding ASCII

$python = (Get-Command python.exe -ErrorAction SilentlyContinue)
if (-not $python) {
  Write-Fail 'python.exe no encontrado; no se puede servir la clave por HTTP.'
  exit 1
}

$pidFile = Join-Path (Join-Path $repo 'logs') 'http.pid'
$existing = $null
if (Test-Path -LiteralPath $pidFile) {
  $existing = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile -Raw).Trim()) -ErrorAction SilentlyContinue
}
if (-not $existing) {
  $p = Start-Process -FilePath $python.Source `
    -ArgumentList @('-m', 'http.server', '8000', '--bind', '127.0.0.1') `
    -WorkingDirectory $sshDir -PassThru -WindowStyle Hidden
  New-Directory (Split-Path -Parent $pidFile)
  Set-Content -LiteralPath $pidFile -Value $p.Id -Encoding ASCII
  Write-Ok "HTTP server en 127.0.0.1:8000 (PID $($p.Id))"
} else {
  Write-Info "HTTP server ya corriendo (PID $($existing.Id))"
}

Write-Host ''
Write-Host 'En la consola del live (Ctrl+Alt+F3, login root sin password):' -ForegroundColor Cyan
Write-Host '  curl -s http://10.0.2.2:8000/bootstrap.sh -o /tmp/b.sh' -ForegroundColor White
Write-Host '  bash /tmp/b.sh' -ForegroundColor White
Write-Host ''
Write-Host 'Luego, desde el host:' -ForegroundColor Cyan
Write-Host '  .\build.ps1 wait-ssh' -ForegroundColor White
Write-Host '  .\build.ps1 push' -ForegroundColor White
Write-Host ''
Write-Host 'Para detener el servidor: detener el PID del archivo logs\http.pid' -ForegroundColor DarkGray
exit 0

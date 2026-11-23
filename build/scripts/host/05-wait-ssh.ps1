# =============================================================================
# Ronin - wait for guest SSH
# =============================================================================
param(
  [int]$TimeoutSeconds = 300
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$port = [int](Get-ConfigValue $config 'SSH_PORT' '2222')

Write-Step "Esperando SSH en 127.0.0.1:$port"
if (-not (Wait-TcpPort -Port $port -TimeoutSeconds $TimeoutSeconds)) {
  Write-Fail "El puerto no abrio en $TimeoutSeconds s."
  Write-Info 'Revisar: .\build.ps1 down; logs\*-serial.log; consola QEMU.'
  exit 1
}
Write-Ok 'Puerto abierto.'

$user = Get-ConfigValue $config 'TARGET_USER' 'davosoler'
$rootCode = Invoke-Ssh -Config $config -User 'root' -Command 'echo RONIN_SSH_OK'
if ($rootCode -eq 0) {
  Write-Ok 'SSH root OK.'
  exit 0
}

Write-Warn 'SSH root fallo (puede estar deshabilitado tras 95-finalize).'
$userCode = Invoke-Ssh -Config $config -User $user -Command 'echo RONIN_SSH_OK'
if ($userCode -eq 0) {
  Write-Ok "SSH usuario $user OK."
  exit 0
}

Write-Fail 'SSH no autentico ni como root ni como usuario.'
exit 1

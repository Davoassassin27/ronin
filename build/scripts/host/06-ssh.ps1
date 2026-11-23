# =============================================================================
# Ronin - SSH to guest
# =============================================================================
param(
  [string]$User = 'root',
  [string]$Command = ''
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$ssh = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
if (-not $ssh) { throw 'ssh.exe no encontrado.' }

$sshArgs = Get-SshArgs -Config $config -User $User -Command $Command
& $ssh @sshArgs
exit $LASTEXITCODE

# =============================================================================
# Ronin - run a guest script over SSH
# =============================================================================
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Script,
  [string]$User = 'root',
  [switch]$Sudo,
  [switch]$Tty
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$config = Get-BuildConfig
$guestDir = '/root/build-scripts/guest'
$remote = "$guestDir/$Script"
if ($Script -notmatch '\.sh$') { $remote = "$guestDir/$Script.sh" }

$inner = "test -f $remote || { echo 'No existe $remote'; exit 2; }; bash $remote"
if ($Sudo) { $inner = "sudo -n bash $remote" }
$command = $inner

if ($Tty) {
  $ssh = (Get-Command ssh.exe -ErrorAction SilentlyContinue).Source
  $sshArgs = Get-SshArgs -Config $config -User $User -Command $command
  $sshArgs = @('-t') + $sshArgs
  & $ssh @sshArgs
  exit $LASTEXITCODE
}

$code = Invoke-Ssh -Config $config -User $User -Command $command
exit $code

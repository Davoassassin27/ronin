# =============================================================================
# Ronin - unit tests + trazabilidad UX
# Ejecuta tests de guest (bash) y checks estáticos del host; deja JSON en
# reports/ y un log JSONL de experiencia de usuario en logs/.
# =============================================================================
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$reports = Join-Path $repo 'reports'
$logs = Join-Path $repo 'logs'
New-Item -ItemType Directory -Force -Path $reports, $logs | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonOut = Join-Path $reports "unit-$stamp.json"
$uxOut = Join-Path $logs "ronin-ux-$stamp.jsonl"

$results = New-Object System.Collections.Generic.List[object]
$pass = 0
$fail = 0

function Add-Result {
  param([string]$Name, [bool]$Ok, [string]$Detail = '')
  if ($Ok) { $script:pass++ } else { $script:fail++ }
  $results.Add([pscustomobject]@{ name = $Name; status = $(if ($Ok) { 'pass' } else { 'fail' }); detail = $Detail })
  Write-Host ("{0,-4} {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail)
  $entry = [ordered]@{
    ts        = (Get-Date).ToString('o')
    level     = $(if ($Ok) { 'pass' } else { 'fail' })
    component = 'unittest-host'
    message   = $Name
    context   = $Detail
    code      = $(if ($Ok) { 0 } else { 1 })
  }
  Add-Content -LiteralPath $uxOut -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}

Write-Host '== Ronin unit tests ==' -ForegroundColor Cyan

# --- 1. Tests de guest (bash) -------------------------------------------------
$bashPath = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath)) {
  $bash = Get-Command bash.exe -ErrorAction SilentlyContinue
  if ($bash) { $bashPath = $bash.Source }
}
if ($bashPath -and (Test-Path -LiteralPath $bashPath)) {
  $guestTest = Join-Path $repo 'tests\unit\guest\run-guest-tests.sh'
  $lib = Join-Path $repo 'build\guest\lib.sh'
  $guestJson = Join-Path $logs "unit-guest-$stamp.json"
  $env:UNIT_JSON = ($guestJson -replace '\\', '/')
  $output = & $bashPath ($guestTest -replace '\\', '/') ($lib -replace '\\', '/') 2>&1
  $code = $LASTEXITCODE
  Remove-Item Env:\UNIT_JSON -ErrorAction SilentlyContinue
  $output | ForEach-Object { Write-Host "  $_" }
  Add-Result 'guest_tests_exit' ($code -eq 0) "exit=$code"
  if (Test-Path -LiteralPath $guestJson) {
    $g = Get-Content -LiteralPath $guestJson -Raw | ConvertFrom-Json
    foreach ($t in $g.tests) { Add-Result "guest/$($t.name)" ($t.status -eq 'pass') $t.detail }
  } else {
    Add-Result 'guest_tests_report' $false 'no se generó el JSON de tests de guest'
  }
} else {
  Add-Result 'bash_available' $false 'bash.exe no encontrado'
}

# --- 2. Identidad Ronin (sin restos de Work OS) -------------------------------
# Se excluyen los propios tests y rename-to-ronin.sh: necesitan mencionar el
# nombre viejo y el /dev/vda3 histórico para poder detectarlos/corregirlos.
$excluded = @('rename-to-ronin.sh', 'run-unit-tests.ps1', 'run-guest-tests.sh')
$textExt = @('.md', '.ps1', '.sh', '.env', '.json', '.yml', '.yaml', '.conf', '.service')
$stale = Get-ChildItem -LiteralPath $repo -Recurse -File |
  Where-Object { $textExt -contains $_.Extension } |
  Where-Object { $excluded -notcontains $_.Name } |
  Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\logs\\' -and $_.FullName -notmatch '\\reports\\' } |
  Select-String -Pattern 'Work OS|WORK_OS' |
  ForEach-Object { "$($_.Filename):$($_.LineNumber)" }
$staleCount = @($stale).Count
Add-Result 'identity_ronin' ($staleCount -eq 0) ($(if ($staleCount) { $stale -join ', ' } else { 'sin restos' }))

# --- 3. El entry de boot debe ser ronin.conf ----------------------------------
$configure = Get-Content -LiteralPath (Join-Path $repo 'build\guest\30-configure.sh') -Raw
$bootOk = $configure -match 'entries/ronin\.conf' -and $configure -match 'default ronin\.conf'
Add-Result 'boot_entry_ronin' $bootOk

# --- 4. Trazabilidad UX presente en verify y migración ------------------------
$verify = Get-Content -LiteralPath (Join-Path $repo 'build\guest\90-verify.sh') -Raw
$migrate = Get-Content -LiteralPath (Join-Path $repo 'build\guest\migrate-to-nvme.sh') -Raw
Add-Result 'ux_trace_verify' ($verify -match 'ux_log' -and $verify -match 'detect_disk_layout')
Add-Result 'ux_trace_migrate' ($migrate -match 'ux_run mount' -and $migrate -match 'ux_log')

# --- Reporte -----------------------------------------------------------------
$summary = [ordered]@{
  schema = 1
  timestamp = (Get-Date).ToString('o')
  pass = $pass
  fail = $fail
  results = $results.ToArray()
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonOut -Encoding UTF8

Write-Host ''
Write-Host ("UNIT PASS={0} FAIL={1}" -f $pass, $fail) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
Write-Host "Reporte: $jsonOut"
Write-Host "UX log:  $uxOut"
if ($fail -gt 0) { exit 1 }
exit 0

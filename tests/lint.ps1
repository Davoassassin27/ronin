# =============================================================================
# Ronin - local lint (PowerShell syntax + bash -n + JSON)
# =============================================================================
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skip = '\\\.git\\|\\kensei\\(data|models|\.venv|reports|out|\.pytest_cache|\.ruff_cache)\\'
$errors = 0

Write-Host '== PowerShell syntax ==' -ForegroundColor Cyan
$psFiles = Get-ChildItem -LiteralPath $repo -Recurse -Filter '*.ps1' -File |
  Where-Object { $_.FullName -notmatch $skip }
foreach ($file in $psFiles) {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
  if ($parseErrors -and $parseErrors.Count -gt 0) {
    $errors++
    Write-Host "  [FAIL] $($file.FullName)" -ForegroundColor Red
    $parseErrors | ForEach-Object { Write-Host "         $($_.Message)" -ForegroundColor Red }
  } else {
    Write-Host "  [OK]   $($file.Name)" -ForegroundColor Green
  }
}

Write-Host ''
Write-Host '== Bash syntax ==' -ForegroundColor Cyan
$bashPath = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bashPath)) {
  $bash = Get-Command bash.exe -ErrorAction SilentlyContinue
  if ($bash) { $bashPath = $bash.Source }
}
if ($bashPath -and (Test-Path -LiteralPath $bashPath)) {
  $shFiles = Get-ChildItem -LiteralPath $repo -Recurse -Filter '*.sh' -File |
    Where-Object { $_.FullName -notmatch $skip }
  foreach ($file in $shFiles) {
    $posixPath = $file.FullName.Replace('\', '/')
    & $bashPath -n $posixPath
    if ($LASTEXITCODE -ne 0) {
      $errors++
      Write-Host "  [FAIL] $($file.FullName)" -ForegroundColor Red
    } else {
      Write-Host "  [OK]   $($file.Name)" -ForegroundColor Green
    }
  }
} else {
  Write-Host '  [WARN] bash.exe no encontrado; se omite bash -n' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '== JSON ==' -ForegroundColor Cyan
$jsonFiles = Get-ChildItem -LiteralPath $repo -Recurse -Filter '*.json' -File |
  Where-Object { $_.FullName -notmatch $skip }
foreach ($file in $jsonFiles) {
  try {
    Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
    Write-Host "  [OK]   $($file.Name)" -ForegroundColor Green
  } catch {
    $errors++
    Write-Host "  [FAIL] $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
  }
}

Write-Host ''
if ($errors -gt 0) {
  Write-Host "Lint FAIL: $errors error(es)" -ForegroundColor Red
  exit 1
}
Write-Host 'Lint OK' -ForegroundColor Green
exit 0

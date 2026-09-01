$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
Write-Host ""
Write-Host "  SureshJ Photography - Photo Download" -ForegroundColor Cyan
Write-Host "  ====================================" -ForegroundColor Cyan
Write-Host ""

function Fail($m) { Write-Host ""; Write-Host "  $m" -ForegroundColor Red; Write-Host ""; Read-Host "  Press Enter to close" | Out-Null; exit 1 }

$cfgPath = Join-Path $here "config.txt"
if (-not (Test-Path $cfgPath)) { Fail "ERROR: config.txt not found next to this file." }
$cfg = @{}
foreach ($line in Get-Content $cfgPath) {
  $t = $line.Trim()
  if ($t -eq "" -or $t.StartsWith("#")) { continue }
  $i = $t.IndexOf("=")
  if ($i -gt 0) { $cfg[$t.Substring(0,$i).Trim().ToUpper()] = $t.Substring($i+1).Trim() }
}
$dest = $cfg["DESTINATION"]; $link = $cfg["LINK"]
$tr = if ($cfg["TRANSFERS"]) { $cfg["TRANSFERS"] } else { "4" }
if (-not $dest) { Fail "ERROR: config.txt is missing the DESTINATION line." }
if (-not $link) { Fail "ERROR: config.txt is missing the LINK line." }
if (-not $link.EndsWith("/")) { $link += "/" }

# a Mac/Linux path in config is no use here - expand ~ or fall back
if ($dest -like "~*") { $dest = $dest -replace '^~', $HOME }
if ($dest -match '^/') {
  $dest = Join-Path $HOME "Downloads\Photos-from-Suresh"
  Write-Host "  No Windows folder set in config.txt, so using:" -ForegroundColor Yellow
  Write-Host "    $dest" -ForegroundColor Yellow
  Write-Host "  (edit the DESTINATION line in config.txt to change it)" -ForegroundColor Yellow
  Write-Host ""
}
$dest = $dest -replace '/','\'

Write-Host "  Saving to : $dest"
Write-Host "  At a time : $tr files"
Write-Host ""

$rclone = $null
$local = Join-Path $here "rclone.exe"
if (Test-Path $local) { $rclone = $local }
if (-not $rclone) { $c = Get-Command rclone -ErrorAction SilentlyContinue; if ($c) { $rclone = $c.Source } }
if (-not $rclone) {
  Write-Host "  rclone not found - downloading it (about 20 MB, one time)..." -ForegroundColor Yellow
  try {
    $zip = Join-Path $env:TEMP "rclone-current.zip"
    $ex  = Join-Path $env:TEMP "rclone-extract"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
    if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
    Expand-Archive $zip -DestinationPath $ex -Force -ErrorAction Stop
    $found = Get-ChildItem $ex -Recurse -Filter rclone.exe | Select-Object -First 1
    if (-not $found) { throw "rclone.exe not found in download" }
    Copy-Item $found.FullName $local -Force
    $rclone = $local
    Write-Host "  rclone ready." -ForegroundColor Green
  } catch {
    Write-Host "  Could not download rclone automatically." -ForegroundColor Red
    Fail "Please get it from https://rclone.org/downloads/ and put rclone.exe next to this file."
  }
}
Write-Host ""

if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
$logDir = Join-Path $here "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$copyLog  = Join-Path $logDir "download-$stamp.log"
$checkLog = Join-Path $logDir "verify-$stamp.log"
$combined = Join-Path $here  "verify-result.txt"

Write-Host "  Downloading... you can stop and re-run this any time, it resumes." -ForegroundColor Cyan
Write-Host ""
& $rclone copy ":http:" $dest --http-url $link --transfers $tr --progress --retries 5 --low-level-retries 20 --log-file $copyLog --log-level INFO
$copyExit = $LASTEXITCODE
Write-Host ""
Write-Host "  Checking every file against the server..." -ForegroundColor Cyan
& $rclone check $dest ":http:" --http-url $link --size-only --combined $combined --log-file $checkLog --log-level INFO
$checkExit = $LASTEXITCODE

$bad = @()
if (Test-Path $combined) { $bad = @(Get-Content $combined | Where-Object { $_ -and $_ -notmatch '^= ' }) }
$have = @(Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue).Count

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
if ($copyExit -eq 0 -and $checkExit -eq 0 -and $bad.Count -eq 0) {
  Write-Host "   SUCCESS - all files downloaded and verified." -ForegroundColor Green
  Write-Host "   Files on your disk : $have"
  Write-Host "   Folder             : $dest"
  Remove-Item $combined -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "   NOT FINISHED YET" -ForegroundColor Yellow
  if ($bad.Count -gt 0) { Write-Host "   $($bad.Count) file(s) missing or incomplete." -ForegroundColor Yellow }
  Write-Host "   Files on your disk : $have"
  Write-Host ""
  Write-Host "   Just run DOWNLOAD.bat again - it will finish the rest." -ForegroundColor Yellow
  Write-Host "   (details: verify-result.txt and the logs folder)"
}
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "  Press Enter to close" | Out-Null

$ErrorActionPreference = "Continue"
# SureshJ Photography - download (Windows)
# 21 Sep 2026: checks the link first (expired / offline said plainly), fetches the
# LIVE file list every run, says what you have and what is left, checks free space
# against what is LEFT, and tells Suresh automatically on success.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
Write-Host ""
Write-Host "  SureshJ Photography - Download" -ForegroundColor Cyan
Write-Host "  ==============================" -ForegroundColor Cyan
Write-Host ""

function Fail($m) { Write-Host ""; Write-Host "  $m" -ForegroundColor Red; Write-Host ""; Read-Host "  Press Enter to close" | Out-Null; exit 1 }
function Gb($b) { "{0:N1}" -f ($b/1GB) }
function Http-Code($u) {
  try { $r = Invoke-WebRequest $u -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop; return [int]$r.StatusCode }
  catch { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode } else { return 0 } }
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

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
if (-not $link) { Fail "ERROR: config.txt is missing the LINK line." }
if (-not $link.EndsWith("/")) { $link += "/" }
$base = $link -replace 'raw/$',''

if ($dest -like "~*") { $dest = $dest -replace '^~', $HOME }
if (-not $dest -or $dest -match '^/') {
  $dest = Join-Path $HOME "Downloads\Photos-from-Suresh"
  Write-Host "  No Windows folder set in config.txt, so using:" -ForegroundColor Yellow
  Write-Host "    $dest" -ForegroundColor Yellow
  Write-Host ""
}
$dest = $dest -replace '/','\'

# ---- 1. is the link alive? ----
$code = Http-Code $link
if ($code -eq 410) { Fail "YOUR LINK HAS EXPIRED.`n  Nothing is wrong with your computer. Please message Suresh -`n  he can reopen it, and then you just run this again." }
if ($code -eq 0)   { Fail "CANNOT REACH THE SERVER - check your internet, then run this again." }
if ($code -ne 200) { Fail "THE SERVER SAID NO (code $code). Please message Suresh." }

Write-Host "  Saving to : $dest"
Write-Host ""

$rclone = $null
$localRc = Join-Path $here "rclone.exe"
if (Test-Path $localRc) { $rclone = $localRc }
if (-not $rclone) { $c = Get-Command rclone -ErrorAction SilentlyContinue; if ($c) { $rclone = $c.Source } }
if (-not $rclone) {
  Write-Host "  Getting the download helper (about 20 MB, one time)..." -ForegroundColor Yellow
  try {
    $zip = Join-Path $env:TEMP "rclone-current.zip"
    $ex  = Join-Path $env:TEMP "rclone-extract"
    Invoke-WebRequest "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile $zip -UseBasicParsing -ErrorAction Stop
    if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
    Expand-Archive $zip -DestinationPath $ex -Force -ErrorAction Stop
    $found = Get-ChildItem $ex -Recurse -Filter rclone.exe | Select-Object -First 1
    if (-not $found) { throw "rclone.exe not found in download" }
    Copy-Item $found.FullName $localRc -Force
    $rclone = $localRc
    Write-Host "  Ready." -ForegroundColor Green
  } catch {
    Fail "Could not get rclone automatically. Please get it from https://rclone.org/downloads/ and put rclone.exe next to this file."
  }
  Write-Host ""
}

if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
$logDir = Join-Path $here "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# ---- 2. what does the job contain, and what do you already have? ----
Write-Host "  Comparing your folder with Suresh's list..." -ForegroundColor Cyan
$wantN = 0; $wantB = [long]0; $haveN = 0; $haveB = [long]0; $leftN = 0; $leftB = [long]0
$need = [long]0; $haveList = $false
try {
  $mt = (Invoke-WebRequest ($base + "manifest.txt") -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).Content
  if ($mt -is [byte[]]) { $mt = [Text.Encoding]::UTF8.GetString($mt) }
  if ($mt -match '(?m)^# Files: ') {
    [IO.File]::WriteAllText((Join-Path $here "MANIFEST.txt"), $mt, (New-Object Text.UTF8Encoding($false)))  # VERIFY checks the current list
    $haveList = $true
    foreach ($line in ($mt -split "`n")) {
      $line = $line.TrimEnd("`r")
      if ($line -match '^# Files: (\d+)') { $wantN = [long]$Matches[1]; continue }
      if ($line -match '^# Bytes: (\d+)') { $wantB = [long]$Matches[1]; continue }
      if ($line.StartsWith("#") -or $line -eq "") { continue }
      $p = $line -split "`t", 2
      if ($p.Count -lt 2) { continue }
      $sz = [long]$p[0]
      $f = Join-Path $dest ($p[1] -replace '/','\')
      $fi = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
      if ($fi -and $fi.Length -eq $sz) { $haveN++; $haveB += $sz } else { $leftN++; $leftB += $sz }
    }
    Write-Host ""
    Write-Host ("  This job      : {0} files, {1} GB" -f $wantN, (Gb $wantB))
    Write-Host ("  You have      : {0} files, {1} GB" -f $haveN, (Gb $haveB))
    Write-Host ("  Still to get  : {0} files, {1} GB" -f $leftN, (Gb $leftB)) -ForegroundColor Yellow
    Write-Host ""
    $need = $leftB
  }
} catch {}
if (-not $haveList) {
  $leftN = 1
  try {
    $sz = (Invoke-WebRequest ($base + "size.json") -UseBasicParsing -TimeoutSec 25).Content
    $m = [regex]::Match("$sz", '"bytes"\s*:\s*(\d+)')
    if ($m.Success) { $need = [long]$m.Groups[1].Value }
  } catch {}
}

# ---- 3. room for what is left? ----
if ($need -gt 0) {
  $free = 0
  try { $free = ([System.IO.DriveInfo]::new((Get-Item -LiteralPath $dest).Root.FullName)).AvailableFreeSpace } catch {}
  if ($free -gt 0 -and $free -lt $need) {
    Write-Host "  ****************************************************" -ForegroundColor Red
    Write-Host ("   NOT ENOUGH SPACE in $dest") -ForegroundColor Red
    Write-Host ("   Needs {0} GB more, only {1} GB free." -f (Gb $need), (Gb $free)) -ForegroundColor Red
    Write-Host "  ****************************************************" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Drives on this computer, and their free space:" -ForegroundColor Yellow
    foreach ($d in ([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -ne 'CDRom' })) {
      $mark = if ($d.AvailableFreeSpace -ge $need) { "  <-- this one fits" } else { "" }
      Write-Host ("    {0,-6} {1,8:N0} GB free{2}" -f $d.Name, ($d.AvailableFreeSpace/1GB), $mark)
    }
    Write-Host ""
    Write-Host "  To use one of those, open config.txt and set for example:" -ForegroundColor Yellow
    Write-Host "    DESTINATION=E:\Jobs" -ForegroundColor Yellow
    Write-Host ""
    $ans = Read-Host "  Continue anyway? (y/n)"
    if ("$ans".Trim() -notmatch '^[Yy]') { Write-Host ""; Write-Host "  Stopped. Nothing downloaded."; Write-Host ""; Read-Host "  Press Enter to close" | Out-Null; exit 0 }
    Write-Host ""
  }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$copyLog  = Join-Path $logDir "download-$stamp.log"
$checkLog = Join-Path $logDir "verify-$stamp.log"
$combined = Join-Path $here  "verify-result.txt"

$copyExit = 0
if ($leftN -gt 0) {
  Write-Host "  Downloading... you can stop and re-run this any time - it carries on" -ForegroundColor Cyan
  Write-Host "  from where it stopped. (The totals below count only what is left.)" -ForegroundColor Cyan
  Write-Host ""
  & $rclone copy ":http:" $dest --http-url $link --transfers $tr --progress --retries 5 --low-level-retries 20 --log-file $copyLog --log-level INFO
  $copyExit = $LASTEXITCODE
} else {
  Write-Host "  You already have everything - just double-checking." -ForegroundColor Green
}

# ---- 4. check every file against the server (extra files of yours are fine) ----
Write-Host ""
Write-Host "  Checking every file against the server..." -ForegroundColor Cyan
Remove-Item $combined -Force -ErrorAction SilentlyContinue
& $rclone check ":http:" $dest --http-url $link --size-only --one-way --combined $combined --log-file $checkLog --log-level INFO
$checkExit = $LASTEXITCODE
$bad = @()
if (Test-Path $combined) { $bad = @(Get-Content $combined | Where-Object { $_ -match '^[-*!] ' }) }
$code2 = Http-Code $link

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
if ($copyExit -eq 0 -and $checkExit -eq 0 -and $bad.Count -eq 0) {
  Write-Host "   SUCCESS - all files downloaded and verified." -ForegroundColor Green
  if ($wantN -gt 0) { Write-Host ("   Files : {0}  ({1} GB)" -f $wantN, (Gb $wantB)) }
  Write-Host "   Folder: $dest"
  Remove-Item $combined -Force -ErrorAction SilentlyContinue
  try {
    $payload = @{ complete=$true; files=$wantN; bytes=$wantB; expectedFiles=$wantN; expectedBytes=$wantB; missing=0; wrongSize=0; folder="$dest" } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri ($base + "confirm") -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 20 | Out-Null
    Write-Host ""
    Write-Host "   Suresh has been told automatically. Nothing else to do." -ForegroundColor Green
  } catch {}
} elseif ($code2 -eq 410) {
  Write-Host "   YOUR LINK EXPIRED while downloading." -ForegroundColor Yellow
  Write-Host "   Please message Suresh - he can reopen it, then run this again."
  Write-Host "   Everything you already have is kept."
} else {
  Write-Host "   NOT FINISHED YET" -ForegroundColor Yellow
  if ($bad.Count -gt 0) { Write-Host "   $($bad.Count) file(s) still missing or incomplete." -ForegroundColor Yellow }
  Write-Host ""
  Write-Host "   Run DOWNLOAD.bat again - it carries on from where it stopped." -ForegroundColor Yellow
  Write-Host "   If it keeps saying this, send Suresh the file verify-result.txt"
}
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "  Press Enter to close" | Out-Null

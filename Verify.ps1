$ErrorActionPreference = "Continue"
# SureshJ Photography - check your files against Suresh's list (Windows)
# 21 Sep 2026: checks against the LIVE list on the server; falls back to the
# MANIFEST.txt in the zip when offline or the link has expired.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
Write-Host ""
Write-Host "  Checking your files against Suresh's list" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
function Fail($m){ Write-Host ""; Write-Host "  $m" -ForegroundColor Red; Write-Host ""; Read-Host "  Press Enter to close" | Out-Null; exit 1 }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

$dest = ""; $link = ""
if (Test-Path "config.txt") {
  foreach ($line in Get-Content "config.txt") {
    $t = $line.Trim(); if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $i = $t.IndexOf("="); if ($i -le 0) { continue }
    $k = $t.Substring(0,$i).Trim().ToUpper(); $v = $t.Substring($i+1).Trim()
    if ($k -eq "DESTINATION") { $dest = $v }
    if ($k -eq "LINK") { $link = $v }
  }
}

$srcName = "the list in your zip"
if ($link) {
  if (-not $link.EndsWith("/")) { $link += "/" }
  try {
    $mt = (Invoke-WebRequest (($link -replace 'raw/$','') + "manifest.txt") -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop).Content
    if ($mt -is [byte[]]) { $mt = [Text.Encoding]::UTF8.GetString($mt) }
    if ($mt -match '(?m)^# Files: ') {
      [IO.File]::WriteAllText((Join-Path $here "MANIFEST.txt"), $mt, (New-Object Text.UTF8Encoding($false)))
      $srcName = "Suresh's current list"
    }
  } catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 410) {
      Write-Host "  (Your link has expired - checking against the list in your zip.)" -ForegroundColor Yellow
      Write-Host ""
    }
  }
}
if (-not (Test-Path "MANIFEST.txt")) { Fail "ERROR: MANIFEST.txt is not next to this file." }

if ($dest -like "~*") { $dest = $dest -replace '^~', $HOME }
if ($dest -match '^/') { $dest = "" }
$dest = $dest -replace '/','\'
if (-not $dest -or -not (Test-Path -LiteralPath $dest)) {
  Write-Host "  Which folder are the files in?"
  Write-Host "  (drag the folder into this window, then press Enter)" -ForegroundColor DarkGray
  $dest = (Read-Host "  Folder").Trim().Trim('"')
}
if (-not (Test-Path -LiteralPath $dest)) { Fail "That folder does not exist: $dest" }

$man = Get-Content "MANIFEST.txt"
$job   = ($man | Where-Object { $_ -like '# Job: *' }   | Select-Object -First 1) -replace '^# Job: ',''
$wantN = [long](($man | Where-Object { $_ -like '# Files: *' } | Select-Object -First 1) -replace '^# Files: ','')
$wantB = [long](($man | Where-Object { $_ -like '# Bytes: *' } | Select-Object -First 1) -replace '^# Bytes: ','')

Write-Host "  Job     : $job"
Write-Host "  Folder  : $dest"
Write-Host "  Against : $srcName"
Write-Host ""
Write-Host "  Reading your files..." -ForegroundColor DarkGray

$missing = New-Object System.Collections.Generic.List[string]
$wrong   = New-Object System.Collections.Generic.List[string]
$haveN = 0; $haveB = [long]0
foreach ($line in $man) {
  if ($line.StartsWith("#") -or $line.Trim() -eq "") { continue }
  $parts = $line -split "`t", 2
  if ($parts.Count -lt 2) { continue }
  $size = [long]$parts[0]
  $f = Join-Path $dest ($parts[1] -replace '/','\')
  $fi = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
  if (-not $fi) { $missing.Add($parts[1]); continue }
  if ($fi.Length -ne $size) { $wrong.Add("$($parts[1]) (expected $size bytes, has $($fi.Length))") }
  else { $haveN++; $haveB += $fi.Length }
}

$gb = { param($b) "{0:N1}" -f ($b/1GB) }
$out = New-Object System.Collections.Generic.List[string]
$out.Add("RESULT - SureshJ Photography")
$out.Add("Job     : $job")
$out.Add("Folder  : $dest")
$out.Add("Checked : $(Get-Date -f 'yyyy-MM-dd HH:mm')  against $srcName")
$out.Add("")
$out.Add("Suresh sent : $wantN files   $(& $gb $wantB) GB")
$out.Add("You have    : $haveN files   $(& $gb $haveB) GB")
$out.Add("")
if ($missing.Count -eq 0 -and $wrong.Count -eq 0) {
  $out.Add("COMPLETE - every file is present and the right size.")
} else {
  $out.Add("NOT COMPLETE - run DOWNLOAD again, it carries on from where it stopped.")
  if ($missing.Count -gt 0) { $out.Add("  $($missing.Count) file(s) missing") }
  if ($wrong.Count -gt 0)   { $out.Add("  $($wrong.Count) file(s) the wrong size (download did not finish)") }
  $out.Add("")
  if ($missing.Count -gt 0) {
    $out.Add("MISSING FILES:")
    $missing | Select-Object -First 200 | ForEach-Object { $out.Add($_) }
    if ($missing.Count -gt 200) { $out.Add("  ...and $($missing.Count-200) more") }
  }
  if ($wrong.Count -gt 0) {
    $out.Add(""); $out.Add("WRONG SIZE:")
    $wrong | Select-Object -First 100 | ForEach-Object { $out.Add($_) }
  }
}
$out | Out-File -LiteralPath (Join-Path $here "RESULT.txt") -Encoding utf8

$sent = $false
if ($link) {
  try {
    $payload = @{
      complete      = ($missing.Count -eq 0 -and $wrong.Count -eq 0)
      files         = $haveN
      bytes         = $haveB
      expectedFiles = $wantN
      expectedBytes = $wantB
      missing       = $missing.Count
      wrongSize     = $wrong.Count
      folder        = "$dest"
    } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri (($link -replace 'raw/$','') + "confirm") -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 20 | Out-Null
    $sent = $true
  } catch {}
}
foreach ($l in $out) {
  $col = if ($l -like "COMPLETE*") { "Green" } elseif ($l -like "NOT COMPLETE*") { "Yellow" } else { "Gray" }
  Write-Host "  $l" -ForegroundColor $col
}
Write-Host ""
Write-Host "  ============================================" -ForegroundColor Cyan
if ($sent) {
  Write-Host "   Done. Suresh already has this result." -ForegroundColor Green
} else {
  Write-Host "   A file called RESULT.txt is now in this folder."
  Write-Host "   Please send RESULT.txt to Suresh." -ForegroundColor Yellow
}
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "  Press Enter to close" | Out-Null

# Publish-Update.ps1 - compile Lang-Guard and push the update to every PC (via GitHub).
# Usage: right-click > Run with PowerShell (or: powershell -File Publish-Update.ps1)
# Bump VERSION in LangGuard.ahk first - PCs update when the published version differs.
$ErrorActionPreference = "Stop"
$d = Split-Path -Parent $MyInvocation.MyCommand.Path
$ahkBase = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
$compiler = "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe"

$src = [IO.File]::ReadAllText("$d\LangGuard.ahk")
if ($src -notmatch 'VERSION := "([\d.]+)"') { throw "VERSION not found in LangGuard.ahk" }
$ver = $Matches[1]
Write-Host "Publishing Lang-Guard v$ver ..."

& $compiler /in "$d\LangGuard.ahk" /out "$d\Share\LangGuard.exe" /base $ahkBase /silent verbose
Start-Sleep 4
if (-not (Test-Path "$d\Share\LangGuard.exe")) { throw "compile failed" }

New-Item -ItemType Directory -Force "$d\latest" | Out-Null
Copy-Item "$d\Share\LangGuard.exe" "$d\latest\LangGuard.exe" -Force
[IO.File]::WriteAllText("$d\latest\version.txt", $ver)

Compress-Archive -Path "$d\Share\*" -DestinationPath "$d\Lang-Guard-Share.zip" -Force

git -C $d add -A
git -C $d commit -m "Release v$ver"
git -C $d push origin main

# update this PC immediately too
Get-Process LangGuard -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
if (Test-Path "$env:LOCALAPPDATA\Lang-Guard") {
    Copy-Item "$d\latest\LangGuard.exe" "$env:LOCALAPPDATA\Lang-Guard\LangGuard.exe" -Force
    Start-Process "$env:LOCALAPPDATA\Lang-Guard\LangGuard.exe"
}
Write-Host "Published v$ver. Other PCs pick it up within ~6 hours or at next login."

# Installs the panel for the current user. Run once per laptop, then restart Premiere.
# Window > Extensions > Live Collab
param([switch]$Junction)  # dev machine only: link to the repo instead of copying
$ErrorActionPreference = 'Stop'
reg add HKCU\Software\Adobe\CSXS.11 /v PlayerDebugMode /t REG_SZ /d 1 /f | Out-Null
$src = (Resolve-Path (Join-Path $PSScriptRoot '..\panel')).Path
$dst = Join-Path $env:APPDATA 'Adobe\CEP\extensions\com.hacklanta.premierecollab'
New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
if (Test-Path $dst) { cmd /c rmdir "$dst" 2>$null; if (Test-Path $dst) { Remove-Item -Recurse -Force $dst } }
if ($Junction) { cmd /c mklink /J "$dst" "$src" | Out-Null }
else { robocopy $src $dst /MIR | Out-Null }
Write-Host "Installed to $dst. PlayerDebugMode=1 set. Restart Premiere."
if (-not (Test-Path 'C:\Program Files\Adobe\Adobe Premiere Pro 2022')) { Write-Warning 'Premiere Pro 2022 not found at the default path.' }

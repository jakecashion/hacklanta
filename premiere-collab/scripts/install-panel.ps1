# install-panel.ps1 - run on each laptop (no admin needed).
#   powershell -ExecutionPolicy Bypass -File scripts\install-panel.ps1          # copy (robocopy /MIR)
#   powershell -ExecutionPolicy Bypass -File scripts\install-panel.ps1 -Link    # junction to the repo (dev machine)
param([switch]$Link)

$ErrorActionPreference = 'Stop'
$id   = 'com.hacklanta.premierecollab'
$src  = (Resolve-Path (Join-Path $PSScriptRoot '..\panel')).Path
$root = Join-Path $env:APPDATA 'Adobe\CEP\extensions'
$dst  = Join-Path $root $id

# 1. Allow unsigned panels in CEP 11
New-Item -Path 'HKCU:\Software\Adobe\CSXS.11' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Adobe\CSXS.11' -Name PlayerDebugMode -Value '1' -Type String
Write-Host 'PlayerDebugMode = 1 (CSXS.11)'

# 2. Put the panel in the extensions folder
New-Item -ItemType Directory -Force -Path $root | Out-Null
if ($Link) {
  if (Test-Path $dst) { cmd /c rmdir "$dst" | Out-Null }
  cmd /c mklink /J "$dst" "$src" | Out-Null
  Write-Host "Junction: $dst -> $src"
} else {
  robocopy "$src" "$dst" /MIR /NFL /NDL /NJH /NJS | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
  Write-Host "Copied panel to $dst"
}

Write-Host 'Restart Premiere, then Window > Extensions > Tandem'

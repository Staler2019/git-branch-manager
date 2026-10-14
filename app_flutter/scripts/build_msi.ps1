<#
.SYNOPSIS
  Packages a `flutter build windows --release` bundle as a Windows Installer
  package with WiX Toolset 5. The one command both a developer machine and
  release.yml run, so the MSI a user installs is the one that was tested.

.PARAMETER Version
  x.y.z. Windows Installer compares the first three fields and caps them at
  255.255.65535; anything else would either fail to build or, worse, build an
  MSI that never upgrades.

.PARAMETER ReleaseDir
  The bundle to package. Defaults to Flutter's own output directory.

.PARAMETER OutFile
  Where the .msi goes.

.EXAMPLE
  pwsh app_flutter/scripts/build_msi.ps1 -Version 0.51.0 -OutFile dist/x.msi

  Requires: dotnet tool install --global wix --version 5.0.2
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$ReleaseDir,
  [Parameter(Mandatory = $true)][string]$OutFile
)

$ErrorActionPreference = 'Stop'

# Defaulted here rather than in param(): Windows PowerShell 5.1 has no
# $PSScriptRoot yet while it binds parameter defaults.
if (-not $ReleaseDir) {
  $ReleaseDir = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release'
}

if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$' -or
    [int]$Matches[1] -gt 255 -or [int]$Matches[2] -gt 255 -or
    [int]$Matches[3] -gt 65535) {
  throw "Version '$Version' is not a Windows Installer version (x.y.z, at most 255.255.65535)."
}

$release = (Resolve-Path -LiteralPath $ReleaseDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $release 'gbm_flutter.exe'))) {
  throw "No gbm_flutter.exe in $release; run flutter build windows --release first."
}
# gbm_capi.dll is bundled by windows/CMakeLists.txt; an MSI without it installs
# an app that cannot open a repository.
if (-not (Test-Path -LiteralPath (Join-Path $release 'gbm_capi.dll'))) {
  throw "No gbm_capi.dll in $release."
}

$source = Join-Path $PSScriptRoot '..\windows\installer\Package.wxs'
$outDir = Split-Path -Parent $OutFile
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# -pdbtype none: by default WiX writes a .wixpdb beside the .msi, and
# release.yml publishes everything in that directory.
& wix build $source -arch x64 -pdbtype none -d "Version=$Version" -d "ReleaseDir=$release" -o $OutFile
if ($LASTEXITCODE -ne 0) {
  throw "wix build failed with exit code $LASTEXITCODE."
}
Write-Output "Built $OutFile"

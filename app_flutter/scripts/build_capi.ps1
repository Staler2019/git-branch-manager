# Phase A native-library build for the Flutter UI (Windows). See
# build_capi.sh's header comment -- same script, PowerShell for the CI
# Windows runner and Windows dev machines.
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$BuildDir = Join-Path $RepoRoot "build\capi-only"
$OutDir = Join-Path $RepoRoot "app_flutter\build\native"

Push-Location $RepoRoot
try {
    cmake --preset capi-only
    cmake --build --preset capi-only --target gbm_capi
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item (Join-Path $BuildDir "src\capi\gbm_capi.dll") $OutDir -Force
Write-Host "Copied gbm_capi.dll -> $OutDir\"

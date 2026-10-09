<#
  setup_airsim.ps1 - downloads a prebuilt AirSim Unreal environment
  (default: "Blocks") from the microsoft/AirSim GitHub releases, extracts
  it, and writes AIRSIM_BINARY_PATH into scripts/.env.

  NOTE: keep this file plain ASCII (see the comment at the top of
  start.ps1 for why).
#>

param(
    [string]$EnvName = "Blocks"
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$DownloadDir = Join-Path $RootDir "airsim_env"
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

Write-Host "[setup_airsim.ps1] Looking up latest AirSim Windows release..."

$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/AirSim/releases" -Headers @{ "User-Agent" = "drone-census-sim" }

$targetAsset = $null
$targetRelease = $null

foreach ($release in $releases) {
    foreach ($asset in $release.assets) {
        if ($asset.name -like "$EnvName*.zip" -and $asset.name -notlike "*linux*") {
            $targetAsset = $asset
            $targetRelease = $release
            break
        }
    }
    if ($targetAsset) { break }
}

if (-not $targetAsset) {
    Write-Host "[setup_airsim.ps1] Could not find a Windows build of '$EnvName' in AirSim releases."
    Write-Host "[setup_airsim.ps1] Visit https://github.com/microsoft/AirSim/releases and download one manually,"
    Write-Host "[setup_airsim.ps1] then set AIRSIM_BINARY_PATH in scripts\.env to the extracted .exe path."
    exit 1
}

Write-Host "[setup_airsim.ps1] Found $($targetAsset.name) in release $($targetRelease.tag_name)"

$zipPath = Join-Path $DownloadDir $targetAsset.name
Write-Host "[setup_airsim.ps1] Downloading (this may take a few minutes)..."
Invoke-WebRequest -Uri $targetAsset.browser_download_url -OutFile $zipPath

Write-Host "[setup_airsim.ps1] Extracting..."
Expand-Archive -Path $zipPath -DestinationPath $DownloadDir -Force

$exe = Get-ChildItem -Path $DownloadDir -Recurse -Filter "*.exe" |
    Where-Object { $_.Name -notlike "*UnrealCEFSubProcess*" -and $_.Name -notlike "*CrashReport*" } |
    Select-Object -First 1

if (-not $exe) {
    Write-Host "[setup_airsim.ps1] Extraction completed but no usable .exe was found under $DownloadDir."
    exit 1
}

Write-Host "[setup_airsim.ps1] AirSim binary ready at $($exe.FullName)"

$EnvFile = Join-Path $PSScriptRoot ".env"
$lines = @()
if (Test-Path $EnvFile) {
    $lines = Get-Content $EnvFile | Where-Object { $_ -notmatch "^AIRSIM_BINARY_PATH=" }
}
$lines += "AIRSIM_BINARY_PATH=$($exe.FullName)"
Set-Content -Path $EnvFile -Value $lines

Write-Host "[setup_airsim.ps1] Wrote AIRSIM_BINARY_PATH to scripts\.env"

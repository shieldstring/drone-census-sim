<#
  setup_airsim.ps1 - downloads a prebuilt AirSim Unreal environment for
  population census work.

  Default: CityEnviron (city with moving vehicles AND pedestrians).
  Alternatives: AirSimNH (smaller neighborhood), Blocks (empty - not for census).

  Usage:
    .\scripts\setup_airsim.ps1
    .\scripts\setup_airsim.ps1 -EnvName CityEnviron
    .\scripts\setup_airsim.ps1 -EnvName AirSimNH

  CityEnviron is multi-GB and split into .zip.001 / .002 parts. 7-Zip is
  required to extract those (https://www.7-zip.org/).

  NOTE: keep this file plain ASCII (see start.ps1 header).
#>

param(
    # CityEnviron = large city with pedestrians (default).
    # AirSimNH = urban neighborhood (smaller download).
    # Blocks = empty test cubes (NOT useful for census).
    [string]$EnvName = "CityEnviron"
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$DownloadDir = Join-Path $RootDir "airsim_env"
$EnvDir = Join-Path $DownloadDir $EnvName
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $EnvDir | Out-Null

Write-Host "[setup_airsim.ps1] Looking up AirSim Windows releases for '$EnvName'..."
Write-Host "[setup_airsim.ps1] Tip: CityEnviron has pedestrians; AirSimNH is urban streets; Blocks has NO people."

$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/AirSim/releases" -Headers @{ "User-Agent" = "drone-census-sim" }

# Collect matching assets (single .zip or multi-part .zip.001/.002/...)
$matched = @()
$targetRelease = $null

foreach ($release in $releases) {
    $assets = @($release.assets | Where-Object {
        ($_.name -like "$EnvName.zip" -or $_.name -like "$EnvName.zip.*") -and
        ($_.name -notlike "*linux*")
    })
    if ($assets.Count -gt 0) {
        $matched = $assets | Sort-Object Name
        $targetRelease = $release
        break
    }
}

if (-not $matched -or $matched.Count -eq 0) {
    Write-Host "[setup_airsim.ps1] Could not find '$EnvName' in AirSim releases."
    Write-Host "[setup_airsim.ps1] Try: -EnvName AirSimNH   or   -EnvName CityEnviron"
    Write-Host "[setup_airsim.ps1] Or download manually from:"
    Write-Host "[setup_airsim.ps1]   https://github.com/microsoft/AirSim/releases"
    Write-Host "[setup_airsim.ps1] then set AIRSIM_BINARY_PATH in scripts\.env"
    exit 1
}

Write-Host "[setup_airsim.ps1] Found $($matched.Count) file(s) in release $($targetRelease.tag_name)"

$downloaded = @()
foreach ($asset in $matched) {
    $outPath = Join-Path $EnvDir $asset.name
    if ((Test-Path $outPath) -and ((Get-Item $outPath).Length -gt 1000000)) {
        Write-Host "[setup_airsim.ps1] Already have $($asset.name) - skipping download"
    } else {
        Write-Host "[setup_airsim.ps1] Downloading $($asset.name) ($([math]::Round($asset.size/1MB)) MB)..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $outPath
    }
    $downloaded += $outPath
}

Write-Host "[setup_airsim.ps1] Extracting..."

$isMultiPart = ($matched | Where-Object { $_.name -like "*.zip.*" }).Count -gt 0
if ($isMultiPart) {
    $part1 = $downloaded | Where-Object { $_ -like "*.001" } | Select-Object -First 1
    if (-not $part1) { $part1 = $downloaded | Sort-Object | Select-Object -First 1 }

    $sevenZip = @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "7z"
    ) | Where-Object { $_ -eq "7z" -or (Test-Path $_) } | Select-Object -First 1

    if (-not $sevenZip) {
        Write-Host "[setup_airsim.ps1] ERROR: CityEnviron needs 7-Zip to extract split archives."
        Write-Host "[setup_airsim.ps1] Install from https://www.7-zip.org/ then re-run:"
        Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName CityEnviron"
        Write-Host "[setup_airsim.ps1] Or use the smaller urban map instead:"
        Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName AirSimNH"
        exit 1
    }

    & $sevenZip x -y "-o$EnvDir" $part1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[setup_airsim.ps1] 7-Zip extract failed (exit $LASTEXITCODE)."
        exit 1
    }
} else {
    $zipPath = $downloaded | Select-Object -First 1
    Expand-Archive -Path $zipPath -DestinationPath $EnvDir -Force
}

$exe = Get-ChildItem -Path $EnvDir -Recurse -Filter "*.exe" |
    Where-Object {
        $_.Name -notlike "*UnrealCEFSubProcess*" -and
        $_.Name -notlike "*CrashReport*" -and
        $_.Name -notlike "*UE4Prereq*"
    } |
    Sort-Object Length -Descending |
    Select-Object -First 1

if (-not $exe) {
    # Some packages launch via run.bat only
    $runBat = Get-ChildItem -Path $EnvDir -Recurse -Filter "run.bat" | Select-Object -First 1
    if ($runBat) {
        Write-Host "[setup_airsim.ps1] No .exe found; using run.bat at $($runBat.FullName)"
        $EnvFile = Join-Path $PSScriptRoot ".env"
        $lines = @()
        if (Test-Path $EnvFile) {
            $lines = Get-Content $EnvFile | Where-Object {
                $_ -notmatch "^AIRSIM_BINARY_PATH=" -and $_ -notmatch "^AIRSIM_ENV_NAME="
            }
        }
        $lines += "AIRSIM_ENV_NAME=$EnvName"
        $lines += "AIRSIM_BINARY_PATH=$($runBat.FullName)"
        Set-Content -Path $EnvFile -Value $lines
        Write-Host "[setup_airsim.ps1] Wrote AIRSIM_BINARY_PATH to scripts\.env"
        exit 0
    }
    Write-Host "[setup_airsim.ps1] Extraction completed but no usable .exe / run.bat under $EnvDir."
    exit 1
}

Write-Host "[setup_airsim.ps1] AirSim binary ready at $($exe.FullName)"

$EnvFile = Join-Path $PSScriptRoot ".env"
$lines = @()
if (Test-Path $EnvFile) {
    $lines = Get-Content $EnvFile | Where-Object {
        $_ -notmatch "^AIRSIM_BINARY_PATH=" -and $_ -notmatch "^AIRSIM_ENV_NAME="
    }
}
$lines += "AIRSIM_ENV_NAME=$EnvName"
$lines += "AIRSIM_BINARY_PATH=$($exe.FullName)"
Set-Content -Path $EnvFile -Value $lines

Write-Host "[setup_airsim.ps1] Wrote AIRSIM_BINARY_PATH + AIRSIM_ENV_NAME=$EnvName to scripts\.env"
if ($EnvName -eq "Blocks") {
    Write-Host "[setup_airsim.ps1] WARNING: Blocks has no pedestrians. Prefer CityEnviron or AirSimNH."
}

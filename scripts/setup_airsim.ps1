<#
  setup_airsim.ps1 - downloads a prebuilt AirSim Unreal environment for
  population census work.

  Default: CityEnviron (city with moving vehicles AND pedestrians).
  Alternatives: AirSimNH (smaller neighborhood), Blocks (empty - not for census).

  Usage:
    .\scripts\setup_airsim.ps1
    .\scripts\setup_airsim.ps1 -EnvName CityEnviron
    .\scripts\setup_airsim.ps1 -EnvName AirSimNH
    .\scripts\setup_airsim.ps1 -Force   # delete zips and re-download

  CityEnviron is multi-GB and split into .zip.001 / .002 parts. 7-Zip is
  required to extract those (https://www.7-zip.org/).

  NOTE: keep this file plain ASCII (see start.ps1 header).
#>

param(
    # CityEnviron = large city with pedestrians (default).
    # AirSimNH = urban neighborhood (smaller download).
    # Blocks = empty test cubes (NOT useful for census).
    [string]$EnvName = "CityEnviron",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$DownloadDir = Join-Path $RootDir "airsim_env"
$EnvDir = Join-Path $DownloadDir $EnvName
New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $EnvDir | Out-Null

function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "$Bytes bytes"
}

function Get-SevenZip {
    @(
        "${env:ProgramFiles}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "7z"
    ) | Where-Object { $_ -eq "7z" -or (Test-Path $_) } | Select-Object -First 1
}

function Download-Asset {
    param(
        [string]$Url,
        [string]$OutPath,
        [long]$ExpectedSize
    )

    $tmpPath = "$OutPath.partial"
    if (Test-Path $tmpPath) { Remove-Item -Force $tmpPath }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        # Prefer curl: more reliable for multi-GB GitHub assets than Invoke-WebRequest.
        & curl.exe -L --fail --retry 3 --retry-delay 5 -o $tmpPath $Url
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path $tmpPath) { Remove-Item -Force $tmpPath }
            throw "curl download failed (exit $LASTEXITCODE) for $Url"
        }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $tmpPath
    }

    if (-not (Test-Path $tmpPath)) {
        throw "Download produced no file: $OutPath"
    }

    $actual = (Get-Item $tmpPath).Length
    if ($ExpectedSize -gt 0 -and $actual -ne $ExpectedSize) {
        Remove-Item -Force $tmpPath
        throw ("Downloaded size mismatch for {0}: got {1}, expected {2}. Re-run the script." -f `
            (Split-Path $OutPath -Leaf), (Format-Bytes $actual), (Format-Bytes $ExpectedSize))
    }

    if (Test-Path $OutPath) { Remove-Item -Force $OutPath }
    Move-Item -Force $tmpPath $OutPath
}

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
$totalExpected = ($matched | Measure-Object -Property size -Sum).Sum
Write-Host "[setup_airsim.ps1] Expected total download: $(Format-Bytes $totalExpected)"

if ($Force) {
    Write-Host "[setup_airsim.ps1] -Force: removing previous zip parts under $EnvDir"
    Get-ChildItem -Path $EnvDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$EnvName.zip*" -or $_.Name -like "*.partial" } |
        Remove-Item -Force
}

$downloaded = @()
foreach ($asset in $matched) {
    $outPath = Join-Path $EnvDir $asset.name
    $needDownload = $true

    if ((Test-Path $outPath)) {
        $localSize = (Get-Item $outPath).Length
        if ($localSize -eq [long]$asset.size) {
            Write-Host "[setup_airsim.ps1] OK $($asset.name) ($(Format-Bytes $localSize)) - skipping download"
            $needDownload = $false
        } else {
            Write-Host "[setup_airsim.ps1] Incomplete/corrupt $($asset.name): local $(Format-Bytes $localSize), expected $(Format-Bytes $asset.size) - re-downloading"
            Remove-Item -Force $outPath
        }
    }

    if ($needDownload) {
        Write-Host "[setup_airsim.ps1] Downloading $($asset.name) ($(Format-Bytes $asset.size))..."
        try {
            Download-Asset -Url $asset.browser_download_url -OutPath $outPath -ExpectedSize ([long]$asset.size)
        } catch {
            Write-Host "[setup_airsim.ps1] ERROR: $_"
            Write-Host "[setup_airsim.ps1] Tip: retry with:"
            Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName $EnvName -Force"
            Write-Host "[setup_airsim.ps1] Or use the smaller map:"
            Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName AirSimNH -Force"
            exit 1
        }
        Write-Host "[setup_airsim.ps1] Saved $($asset.name) ($(Format-Bytes ((Get-Item $outPath).Length)))"
    }
    $downloaded += $outPath
}

# Final size check across all parts before extract
foreach ($asset in $matched) {
    $outPath = Join-Path $EnvDir $asset.name
    $localSize = (Get-Item $outPath).Length
    if ($localSize -ne [long]$asset.size) {
        Write-Host "[setup_airsim.ps1] ERROR: $($asset.name) still wrong size after download."
        Write-Host "[setup_airsim.ps1] Delete airsim_env\$EnvName\*.zip* and re-run with -Force."
        exit 1
    }
}

Write-Host "[setup_airsim.ps1] Extracting..."

$isMultiPart = ($matched | Where-Object { $_.name -like "*.zip.*" }).Count -gt 0
if ($isMultiPart) {
    $part1 = $downloaded | Where-Object { $_ -like "*.001" } | Select-Object -First 1
    if (-not $part1) { $part1 = $downloaded | Sort-Object | Select-Object -First 1 }

    $sevenZip = Get-SevenZip
    if (-not $sevenZip) {
        Write-Host "[setup_airsim.ps1] ERROR: CityEnviron needs 7-Zip to extract split archives."
        Write-Host "[setup_airsim.ps1] Install from https://www.7-zip.org/ then re-run:"
        Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName CityEnviron"
        Write-Host "[setup_airsim.ps1] Or use the smaller urban map instead:"
        Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName AirSimNH"
        exit 1
    }

    # Extract into EnvDir; open the .001 part so 7-Zip finds .002 automatically.
    & $sevenZip x -y "-o$EnvDir" $part1
    $extractCode = $LASTEXITCODE
    if ($extractCode -ne 0) {
        Write-Host "[setup_airsim.ps1] 7-Zip extract failed (exit $extractCode)."
        Write-Host "[setup_airsim.ps1] Usually means a truncated/corrupt download (Headers Error / Data Error)."
        Write-Host "[setup_airsim.ps1] Fix: delete the bad zips and re-download:"
        Write-Host "[setup_airsim.ps1]   Remove-Item -Recurse -Force .\airsim_env\$EnvName"
        Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName $EnvName -Force"
        Write-Host "[setup_airsim.ps1] Or switch to the smaller (~1.7 GB) map:"
        Write-Host "[setup_airsim.ps1]   .\scripts\setup_airsim.ps1 -EnvName AirSimNH -Force"
        # Remove zip parts so the next run does not trust them.
        foreach ($p in $downloaded) {
            if (Test-Path $p) { Remove-Item -Force $p }
        }
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

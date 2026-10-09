<#
  start.ps1 - one-command launcher for the drone census stack on Windows.

  Usage:
    .\scripts\start.ps1                  # pre-recorded video source (default)
    .\scripts\start.ps1 -Webcam          # live webcam source
    .\scripts\start.ps1 -Airsim          # live AirSim simulation source

  NOTE: this file must stay plain ASCII. Windows PowerShell 5.1 (the
  version that ships by default on most Windows machines) does not
  reliably read UTF-8 .ps1 files without a BOM, and a stray "smart"
  character (an em dash, a curly quote, etc.) gets misread as a different
  character - including a stray closing quote - which breaks the parser
  for the rest of the file. Keep every string and comment in this file
  limited to standard keyboard characters.
#>

param(
    [switch]$Airsim,
    [switch]$Webcam
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $RootDir "logs"
$DbDir = Join-Path $RootDir "data\db"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $DbDir | Out-Null

# Ensure local env files exist (copied from examples on first run)
$ScriptsEnv = Join-Path $PSScriptRoot ".env"
$ScriptsEnvExample = Join-Path $PSScriptRoot ".env.example"
if (-not (Test-Path $ScriptsEnv) -and (Test-Path $ScriptsEnvExample)) {
    Copy-Item $ScriptsEnvExample $ScriptsEnv
}

$BackendEnv = Join-Path $RootDir "backend\.env"
$BackendEnvExample = Join-Path $RootDir "backend\.env.example"
if (-not (Test-Path $BackendEnv) -and (Test-Path $BackendEnvExample)) {
    Copy-Item $BackendEnvExample $BackendEnv
}

$SampleVideo = Join-Path $RootDir "datasets\DroneCrowd\sample.mp4"
if (-not (Test-Path $SampleVideo)) {
    Write-Host "[start.ps1] ERROR: Missing sample video at datasets\DroneCrowd\sample.mp4"
    Write-Host "[start.ps1] Place any aerial/people video there as sample.mp4, or pass -Webcam."
    if (-not $Webcam -and -not $Airsim) {
        exit 1
    }
}

if ($Airsim) {
    $Mode = "airsim"
} elseif ($Webcam) {
    $Mode = "webcam"
} else {
    $Mode = "video"
}

Write-Host "[start.ps1] Mode: $Mode"
Write-Host "[start.ps1] Project root: $RootDir"

# ---- Resolve system Python, then ensure project .venv exists ----
function Resolve-SystemPython {
    $candidates = @(
        @{ Cmd = "python"; Args = @() },
        @{ Cmd = "py"; Args = @("-3") },
        @{ Cmd = "python3"; Args = @() }
    )
    foreach ($c in $candidates) {
        $cmd = Get-Command $c.Cmd -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        try {
            $allArgs = $c.Args + @("-c", "import sys; print(sys.executable)")
            $exe = & $c.Cmd @allArgs 2>$null
            if ($LASTEXITCODE -eq 0 -and $exe) {
                return @{ Cmd = $c.Cmd; PrefixArgs = $c.Args; Executable = $exe.Trim() }
            }
        } catch {
            continue
        }
    }
    return $null
}

$SystemPython = Resolve-SystemPython
if (-not $SystemPython) {
    Write-Host "[start.ps1] ERROR: Python 3 was not found."
    Write-Host "[start.ps1] Install from https://python.org/downloads and check Add Python to PATH."
    exit 1
}

$VenvDir = Join-Path $RootDir ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
    Write-Host "[start.ps1] Creating project virtual environment at .venv ..."
    & $SystemPython.Cmd @($SystemPython.PrefixArgs + @("-m", "venv", $VenvDir))
    if (-not (Test-Path $VenvPython)) {
        Write-Host "[start.ps1] ERROR: Failed to create .venv. Check that Python venv support is installed."
        exit 1
    }
}
Write-Host "[start.ps1] Using Python: $VenvPython"

foreach ($tool in @("node", "npm")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "[start.ps1] ERROR: '$tool' was not found. Install Node.js LTS from https://nodejs.org"
        exit 1
    }
}

# ---- Parse scripts/.env (simple KEY=VALUE lines, # comments ignored) ----
$EnvFile = Join-Path $PSScriptRoot ".env"
$AirsimPath = $null
$AirsimArgs = ""
$BootWait = 30
$AirsimHost = $null

function Read-DotEnv {
    param([string]$Path)

    $result = @{}
    if (-not (Test-Path $Path)) {
        return $result
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }
        if ($line -match "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$") {
            $result[$matches[1]] = $matches[2]
        }
    }

    return $result
}

$envValues = Read-DotEnv -Path $EnvFile
if ($envValues.ContainsKey("AIRSIM_BINARY_PATH")) { $AirsimPath = $envValues["AIRSIM_BINARY_PATH"] }
if ($envValues.ContainsKey("AIRSIM_BINARY_ARGS")) { $AirsimArgs = $envValues["AIRSIM_BINARY_ARGS"] }
if ($envValues.ContainsKey("AIRSIM_BOOT_WAIT")) { $BootWait = [int]$envValues["AIRSIM_BOOT_WAIT"] }
if ($envValues.ContainsKey("AIRSIM_HOST")) { $AirsimHost = $envValues["AIRSIM_HOST"] }

if ($AirsimHost) {
    $env:AIRSIM_HOST = $AirsimHost
}

$Jobs = @()

function Wait-Port {
    param(
        [int]$Port,
        [int]$TimeoutSeconds = 60
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne(500)
            if ($ok -and $client.Connected) {
                $client.EndConnect($iar)
                $client.Close()
                return $true
            }
            $client.Close()
        } catch {
            # keep waiting
        }
        Start-Sleep -Seconds 1
        $elapsed += 1
    }
    return $false
}

# ---- Step 1: MongoDB (optional - live dashboard still works without it) ----
$mongoCmd = Get-Command mongod -ErrorAction SilentlyContinue
if ($mongoCmd) {
    Write-Host "[start.ps1] Starting MongoDB..."
    $mongoJob = Start-Job -ScriptBlock {
        mongod --dbpath "$using:RootDir\data\db" 2>&1 | Out-File "$using:LogDir\mongod.log"
    }
    $Jobs += $mongoJob

    if (-not (Wait-Port -Port 27017 -TimeoutSeconds 30)) {
        Write-Host "[start.ps1] WARNING: MongoDB did not come up on port 27017 within 30s. Continuing anyway."
    }
} else {
    Write-Host "[start.ps1] WARNING: mongod not found on PATH. Skipping MongoDB."
    Write-Host "[start.ps1] Live dashboard will still work; history persistence is disabled."
    Write-Host "[start.ps1] Install MongoDB Community Server if you need saved snapshots."
}

# ---- Step 2: Backend ----
Write-Host "[start.ps1] Starting backend..."
$backendJob = Start-Job -ScriptBlock {
    Set-Location "$using:RootDir\backend"
    npm install --no-fund --no-audit
    npm start 2>&1 | Out-File "$using:LogDir\backend.log"
}
$Jobs += $backendJob

if (-not (Wait-Port -Port 8080 -TimeoutSeconds 90)) {
    Write-Host "[start.ps1] WARNING: backend did not come up on port 8080 within 90s. Continuing anyway."
    Write-Host "[start.ps1] Check logs\backend.log"
}

# ---- Step 3: AirSim (only if -Airsim was passed) ----
if ($Mode -eq "airsim") {
    $pathIsUsable = $AirsimPath -and (Test-Path $AirsimPath)

    if (-not $pathIsUsable) {
        Write-Host "[start.ps1] No usable AIRSIM_BINARY_PATH found. Running setup_airsim.ps1 to download it now."
        & (Join-Path $PSScriptRoot "setup_airsim.ps1")

        $envValues = Read-DotEnv -Path $EnvFile
        if ($envValues.ContainsKey("AIRSIM_BINARY_PATH")) { $AirsimPath = $envValues["AIRSIM_BINARY_PATH"] }
        $pathIsUsable = $AirsimPath -and (Test-Path $AirsimPath)
    }

    if (-not $pathIsUsable) {
        Write-Host "[start.ps1] AirSim setup did not produce a usable binary. Falling back to video mode."
        $Mode = "video"
    } else {
        Write-Host "[start.ps1] Launching AirSim from $AirsimPath"
        $argList = @()
        if ($AirsimArgs -and $AirsimArgs.Trim() -ne "") {
            $argList = $AirsimArgs -split "\s+"
        }
        Start-Process -FilePath $AirsimPath -ArgumentList $argList
        Write-Host "[start.ps1] Waiting $BootWait seconds for AirSim to finish loading..."
        Start-Sleep -Seconds $BootWait
    }
}

# ---- Step 4: Frontend ----
Write-Host "[start.ps1] Starting frontend..."
$frontendJob = Start-Job -ScriptBlock {
    Set-Location "$using:RootDir\frontend"
    npm install --no-fund --no-audit
    npm run dev 2>&1 | Out-File "$using:LogDir\frontend.log"
}
$Jobs += $frontendJob

Wait-Port -Port 5173 -TimeoutSeconds 90 | Out-Null

# ---- Step 5: AI pipeline ----
Write-Host "[start.ps1] Starting AI pipeline (mode: $Mode)..."

switch ($Mode) {
    "airsim" { $sourceArg = "airsim" }
    "webcam" { $sourceArg = "webcam:0" }
    default { $sourceArg = "video:datasets/DroneCrowd/sample.mp4" }
}

$aiJob = Start-Job -ScriptBlock {
    Set-Location $using:RootDir
    & $using:VenvPython -m pip install -r requirements.txt --quiet
    if ($using:Mode -eq "airsim") {
        & $using:VenvPython -m pip install -r requirements-airsim.txt --quiet
    }
    & $using:VenvPython -m ai_pipeline.counter --source $using:sourceArg 2>&1 |
        Out-File "$using:LogDir\ai_pipeline.log"
}
$Jobs += $aiJob

Write-Host ""
Write-Host "[start.ps1] All components launched."
Write-Host "[start.ps1] Dashboard:  http://localhost:5173"
Write-Host "[start.ps1] Backend:    http://localhost:8080"
Write-Host "[start.ps1] Logs:       $LogDir"
Write-Host "[start.ps1] Press Ctrl+C to stop everything."
Write-Host ""

try {
    # Keep the console alive and surface job failures
    while ($true) {
        $failed = $Jobs | Where-Object { $_.State -eq "Failed" }
        if ($failed) {
            Write-Host "[start.ps1] A background job failed. Check the logs folder."
            break
        }
        Start-Sleep -Seconds 2
    }
} finally {
    Write-Host "[start.ps1] Shutting down..."
    foreach ($job in $Jobs) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

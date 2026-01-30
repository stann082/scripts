# Clean-WindowsCaches.ps1
# Safe-by-default cleanup for temp + common app caches (Notion, JetBrains)
# Run in PowerShell. Some sections require Admin.

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Aggressive,   # if set, also clears a few extra caches
    [switch]$ComponentCleanup,  # Runs DISM StartComponentCleanup (WinSxS)
    [switch]$NoRecycleBin  # if set, don't empty recycle bin
)

function Remove-PathSafe {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) { return }

    Write-Host "Cleaning: $Path"
    try {
        # Remove children, not the root folder (avoids breaking apps expecting the directory)
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Failed (some files may be locked): $Path"
    }
}

function Stop-ServiceSafe {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Start-ServiceSafe {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Start-Service -Name $Name -ErrorAction SilentlyContinue
        }
    } catch { }
}

Write-Host "== Windows & App Cache Cleanup =="

# --- Core temp locations (user + system) ---
$paths = @(
    $env:TEMP,
    "$env:WINDIR\Temp"
)

# --- General "safe" app caches that balloon ---
$paths += @(
    "$env:LOCALAPPDATA\Temp",
    "$env:LOCALAPPDATA\CrashDumps"
)

# --- Windows Update download cache (requires Admin) ---
# Stops WU services temporarily to unlock files
$doWU = $true
if ($doWU) {
    Stop-ServiceSafe -Name "wuauserv"
    Stop-ServiceSafe -Name "bits"
    $paths += "$env:WINDIR\SoftwareDistribution\Download"
}

# --- Delivery Optimization cache (optional) ---
if ($Aggressive) {
    Stop-ServiceSafe -Name "DoSvc"
    $paths += "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache"
}

# Execute cleanup
foreach ($p in $paths | Sort-Object -Unique) {
    if ($PSCmdlet.ShouldProcess($p, "Delete contents")) {
        Remove-PathSafe -Path $p
    }
}

# Start services back up
Start-ServiceSafe -Name "bits"
Start-ServiceSafe -Name "wuauserv"
if ($Aggressive) { Start-ServiceSafe -Name "DoSvc" }

# Empty recycle bin (unless disabled)
if (-not $NoRecycleBin) {
    try {
        Write-Host "Emptying Recycle Bin..."
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Couldn't empty Recycle Bin (may require newer PowerShell / permissions)."
    }
}

if ($ComponentCleanup) {
    Write-Host "Running Windows component store cleanup (DISM StartComponentCleanup)..."
    try {
        Start-Process -FilePath "dism.exe" `
            -ArgumentList "/Online", "/Cleanup-Image", "/StartComponentCleanup" `
            -Wait `
            -NoNewWindow
    } catch {
        Write-Warning "DISM component cleanup failed."
    }
}

Write-Host "Done."

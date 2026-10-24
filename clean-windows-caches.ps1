<#
.SYNOPSIS
Safe-by-default cleanup of temp files and common caches on C:.

.DESCRIPTION
By default this deletes only user and system temp files older than -TempMinAgeDays, crash dumps and the
Windows Update download cache. Everything else is opt-in through switches. Every action honours -WhatIf,
so preview first. Run from an elevated PowerShell; without elevation, system locations, DISM, powercfg and
vssadmin are skipped and reported as such.

.PARAMETER Aggressive
Also clears Windows\SystemTemp, Windows\Panther files older than 30 days, Windows Error Reporting
archives and the Delivery Optimization cache. With -ComponentCleanup it adds DISM /ResetBase, after which
installed Windows updates can no longer be uninstalled.

.PARAMETER ComponentCleanup
Runs DISM /StartComponentCleanup to trim the WinSxS component store.

.PARAMETER EmptyRecycleBin
Empties the Recycle Bin. Irreversible, so it is off by default.

.PARAMETER DevCaches
Clears the NuGet, npm and pip caches. They are re-downloaded on demand. Tools that are not installed are skipped.

.PARAMETER BrowserCaches
Clears Chrome and Edge caches (Cache, Code Cache, GPUCache, Service Worker CacheStorage). Profiles, cookies
and passwords are not touched. A browser that is running is skipped.

.PARAMETER DisableHibernate
Runs powercfg /h off, which deletes hiberfil.sys (often 10+ GB) and disables hibernate and Fast Startup.
Re-enable with powercfg /h on.

.PARAMETER RestorePointMaxGB
Caps System Protection (restore point) storage on C: at this many GB. Windows deletes the oldest restore
points to fit. Valid range 1-1024.

.PARAMETER TempMinAgeDays
Only temp files older than this many days are deleted, so running apps keep their files. Default 1; use 0
to delete everything.

.PARAMETER Help
Shows this help (same as Get-Help on the script) and exits.

.PARAMETER WhatIf
Shows what would happen and changes nothing.

.EXAMPLE
.\clean-windows-caches.ps1 -WhatIf -Aggressive -DevCaches -BrowserCaches
Safe preview of everything except the risky switches.

.EXAMPLE
.\clean-windows-caches.ps1 -DevCaches -BrowserCaches
Typical run: default cleanup plus developer and browser caches.

.EXAMPLE
.\clean-windows-caches.ps1 -Aggressive -ComponentCleanup -DevCaches -BrowserCaches -DisableHibernate -RestorePointMaxGB 5
Full cleanup, including hibernation off and a 5 GB cap on restore points.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Aggressive,
    [switch]$ComponentCleanup,
    [switch]$EmptyRecycleBin,
    [switch]$DevCaches,
    [switch]$BrowserCaches,
    [switch]$DisableHibernate,
    [ValidateRange(1,1024)]
    [int]$RestorePointMaxGB,
    [ValidateRange(0,3650)]
    [int]$TempMinAgeDays = 1,
    [switch]$Help
)

if ($Help) { Get-Help $PSCommandPath -Detailed; return }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# -WhatIf only previews, so it may show admin-only items without elevation.
$canAdmin = $isAdmin -or $WhatIfPreference
$Results = New-Object System.Collections.Generic.List[object]

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} KB' -f ($Bytes / 1KB) }
}

function Add-Result([string]$Item, $Bytes, [string]$Status) {
    $Results.Add([pscustomobject]@{ Item = $Item; Bytes = [double]$Bytes; Size = $(if ($Bytes) { Format-Size $Bytes } else { '-' }); Status = $Status })
}

function Get-FolderBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $sum = (Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($sum) { $sum } else { 0 }
}

# Deletes files (older than MinAgeDays) and then empty folders under Path; keeps Path itself.
function Clear-Folder {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Path, [string]$Label = $Path, [int]$MinAgeDays = 0, [switch]$AdminOnly)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ($AdminOnly -and -not $canAdmin) { Add-Result $Label 0 'Skipped (needs admin)'; return }

    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
               Where-Object { $MinAgeDays -eq 0 -or $_.LastWriteTime -lt $cutoff })
    $bytes = ($files | Measure-Object Length -Sum).Sum
    if (-not $bytes) { $bytes = 0 }

    if (-not $PSCmdlet.ShouldProcess("$Label ($(Format-Size $bytes), $($files.Count) files)", 'Delete')) {
        Add-Result $Label $bytes $(if ($WhatIfPreference) { 'Would delete' } else { 'Declined' })
        return
    }

    $freed = 0; $failed = 0
    foreach ($f in $files) {
        try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len }
        catch { $failed++ }
    }
    Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $MinAgeDays -eq 0 -or $_.LastWriteTime -lt $cutoff } |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    Add-Result $Label $freed $(if ($failed) { "Deleted ($failed in use/skipped)" } else { 'Deleted' })
}

# Runs a tool's own cache-clear command; size comes from the folders it owns.
function Invoke-ToolClean {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Label, [string]$Exe, [string[]]$ToolArgs, [string[]]$SizePaths)

    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) { Add-Result $Label 0 'Skipped (not installed)'; return }
    $bytes = 0; foreach ($p in $SizePaths) { $bytes += Get-FolderBytes $p }

    if (-not $PSCmdlet.ShouldProcess("$Label ($(Format-Size $bytes))", "$Exe $($ToolArgs -join ' ')")) {
        Add-Result $Label $bytes $(if ($WhatIfPreference) { 'Would clear' } else { 'Declined' })
        return
    }
    & $Exe @ToolArgs *> $null
    Add-Result $Label $bytes $(if ($LASTEXITCODE -eq 0) { 'Cleared' } else { "Failed (exit $LASTEXITCODE)" })
}

Write-Host "== Windows & App Cache Cleanup =="
if (-not $isAdmin) {
    Write-Warning $(if ($WhatIfPreference) { 'Not elevated: preview only shows admin items.' }
                    else { 'Not elevated: system locations, DISM, powercfg and vssadmin will be skipped.' })
}
$freeBefore = (Get-PSDrive -Name C).Free
Write-Host ("Free on C: before: {0}" -f (Format-Size $freeBefore))
Write-Host ""

# --- Temp + crash dumps (user temp and %LOCALAPPDATA%\Temp are usually the same folder) ---
$tempPaths = @($env:TEMP, "$env:LOCALAPPDATA\Temp") | Sort-Object -Unique
foreach ($p in $tempPaths) { Clear-Folder -Path $p -MinAgeDays $TempMinAgeDays }
Clear-Folder -Path "$env:WINDIR\Temp" -MinAgeDays $TempMinAgeDays -AdminOnly
Clear-Folder -Path "$env:LOCALAPPDATA\CrashDumps"

# --- Windows Update download cache: stop services only if they were running, always restore ---
$stopped = @()
try {
    if ($canAdmin -and $PSCmdlet.ShouldProcess('wuauserv, bits', 'Stop temporarily')) {
        foreach ($n in 'wuauserv', 'bits') {
            $s = Get-Service -Name $n -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq 'Running') { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue; $stopped += $n }
        }
    }
    Clear-Folder -Path "$env:WINDIR\SoftwareDistribution\Download" -Label 'Windows Update downloads' -AdminOnly
} finally {
    foreach ($n in $stopped) { Start-Service -Name $n -ErrorAction SilentlyContinue }
}

# --- Aggressive extras ---
if ($Aggressive) {
    Clear-Folder -Path "$env:WINDIR\SystemTemp" -MinAgeDays $TempMinAgeDays -AdminOnly
    Clear-Folder -Path "$env:WINDIR\Panther" -MinAgeDays 30 -AdminOnly
    Clear-Folder -Path "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" -Label 'Error reports (archive)' -AdminOnly
    Clear-Folder -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" -Label 'Error reports (queue)' -AdminOnly

    $doPath = "$env:ProgramData\Microsoft\Windows\DeliveryOptimization\Cache"
    $doBytes = Get-FolderBytes $doPath
    if (-not $canAdmin) { Add-Result 'Delivery Optimization cache' $doBytes 'Skipped (needs admin)' }
    elseif ($PSCmdlet.ShouldProcess("Delivery Optimization cache ($(Format-Size $doBytes))", 'Delete-DeliveryOptimizationCache')) {
        Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
        Add-Result 'Delivery Optimization cache' $doBytes 'Cleared'
    } else { Add-Result 'Delivery Optimization cache' $doBytes 'Would clear' }
}

# --- Developer caches (re-downloaded on demand) ---
if ($DevCaches) {
    Invoke-ToolClean -Label 'NuGet caches' -Exe dotnet -ToolArgs 'nuget', 'locals', 'all', '--clear' `
        -SizePaths "$env:USERPROFILE\.nuget\packages", "$env:LOCALAPPDATA\NuGet\v3-cache", "$env:LOCALAPPDATA\NuGet\plugins-cache"
    Invoke-ToolClean -Label 'npm cache' -Exe npm -ToolArgs 'cache', 'clean', '--force' -SizePaths "$env:LOCALAPPDATA\npm-cache"
    Invoke-ToolClean -Label 'pip cache' -Exe pip -ToolArgs 'cache', 'purge' -SizePaths "$env:LOCALAPPDATA\pip\Cache"
}

# --- Browser caches only, never profiles; skipped while the browser is running ---
if ($BrowserCaches) {
    $browsers = @(
        @{ Name = 'Chrome'; Proc = 'chrome' ; Root = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
        @{ Name = 'Edge'  ; Proc = 'msedge' ; Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
    )
    foreach ($b in $browsers) {
        if (-not (Test-Path -LiteralPath $b.Root)) { continue }
        if (Get-Process -Name $b.Proc -ErrorAction SilentlyContinue) { Add-Result "$($b.Name) cache" 0 'Skipped (browser running)'; continue }
        Get-ChildItem -LiteralPath $b.Root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
            ForEach-Object {
                foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') {
                    Clear-Folder -Path (Join-Path $_.FullName $sub) -Label "$($b.Name) $($_.Name)\$sub"
                }
            }
    }
}

# --- Recycle Bin (irreversible) ---
if ($EmptyRecycleBin) {
    if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Empty')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Add-Result 'Recycle Bin' 0 'Emptied'
    } else { Add-Result 'Recycle Bin' 0 $(if ($WhatIfPreference) { 'Would empty' } else { 'Declined' }) }
}

# --- Component store (WinSxS) ---
if ($ComponentCleanup) {
    $dismArgs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
    if ($Aggressive) { $dismArgs += '/ResetBase' }   # installed updates can no longer be uninstalled
    if (-not $canAdmin) { Add-Result 'Component store (WinSxS)' 0 'Skipped (needs admin)' }
    elseif ($PSCmdlet.ShouldProcess('Component store (WinSxS)', "dism.exe $($dismArgs -join ' ')")) {
        & dism.exe @dismArgs | Out-Host
        Add-Result 'Component store (WinSxS)' 0 $(if ($LASTEXITCODE -eq 0) { 'Cleaned' } else { "Failed (exit $LASTEXITCODE)" })
    } else { Add-Result 'Component store (WinSxS)' 0 'Would run' }
}

# --- Hibernation file ---
if ($DisableHibernate) {
    $hib = Get-Item -LiteralPath "$env:SystemDrive\hiberfil.sys" -Force -ErrorAction SilentlyContinue
    if (-not $hib) { Add-Result 'Hibernation file' 0 'Skipped (already off)' }
    elseif (-not $canAdmin) { Add-Result 'Hibernation file' $hib.Length 'Skipped (needs admin)' }
    elseif ($PSCmdlet.ShouldProcess("hiberfil.sys ($(Format-Size $hib.Length))", 'powercfg /h off (disables hibernate and Fast Startup)')) {
        & powercfg.exe /h off
        Add-Result 'Hibernation file' $hib.Length $(if ($LASTEXITCODE -eq 0) { 'Disabled' } else { "Failed (exit $LASTEXITCODE)" })
    } else { Add-Result 'Hibernation file' $hib.Length 'Would disable' }
}

# --- System Protection (restore point) storage cap ---
if ($PSBoundParameters.ContainsKey('RestorePointMaxGB')) {
    $label = "Restore point storage on C: (cap $RestorePointMaxGB GB)"
    if (-not $canAdmin) { Add-Result $label 0 'Skipped (needs admin)' }
    elseif ($PSCmdlet.ShouldProcess('System Protection on C:', "Limit to $RestorePointMaxGB GB; oldest restore points are deleted")) {
        & vssadmin.exe resize shadowstorage /for=C: /on=C: "/maxsize=${RestorePointMaxGB}GB" | Out-Null
        Add-Result $label 0 $(if ($LASTEXITCODE -eq 0) { 'Resized' } else { "Failed (exit $LASTEXITCODE)" })
    } else { Add-Result $label 0 'Would resize' }
}

# --- Summary ---
Write-Host ""
$Results | Sort-Object Bytes -Descending | Format-Table Item, Size, Status -AutoSize
if ($WhatIfPreference) {
    $est = ($Results | Where-Object { $_.Status -like 'Would*' } | Measure-Object Bytes -Sum).Sum
    Write-Host ("Preview only, nothing changed. Estimated reclaimable: {0} (excludes DISM/restore-point savings)" -f (Format-Size $est))
} else {
    $freeAfter = (Get-PSDrive -Name C).Free
    Write-Host ("Free on C: after: {0}   Freed: {1}" -f (Format-Size $freeAfter), (Format-Size ([math]::Max([long]0, $freeAfter - $freeBefore))))
}

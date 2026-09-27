#region Functions

function formatDuration($startTime) {
    if ($startTime -eq $null) {
        return "N/A"
    }

    $timeSpan = New-TimeSpan -Start $startTime
    $duration = ""
    if ($timeSpan.Days -gt 0) {
        $duration += "{0} days " -f $timeSpan.Days
    }
    if ($timeSpan.Hours -gt 0) {
        $duration += "{0} hours " -f $timeSpan.Hours
    }
    if ($timeSpan.Minutes -gt 0) {
        $duration += "{0} minutes" -f $timeSpan.Minutes
    }
    if ($duration -eq "") {
        $duration += "{0} seconds" -f $timeSpan.Seconds
    }
    return $duration.Trim()
}

function formatBytes($bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

$descriptionCache = @{}

function getDescription($path) {
    if (-not $path) {
        return $null
    }
    if (-not $descriptionCache.ContainsKey($path)) {
        try {
            $descriptionCache[$path] = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileDescription
        } catch {
            $descriptionCache[$path] = $null
        }
    }
    return $descriptionCache[$path]
}

function showInfo($process, $cimProcesses) {
    $id = $process.Id
    $cim = $cimProcesses[[uint32]$id]

    echo "$($process.ProcessName) [$id]; Duration: $(formatDuration $process.StartTime)"

    # CIM's path is much cheaper than $process.Path, which opens the process's main module
    $path = if ($cim) { $cim.ExecutablePath }
    if (-not $path) { $path = $process.Path }
    echo "    Path:        $(if ($path) { $path } else { 'N/A (access denied or system process)' })"

    $description = getDescription $path
    if ($description -and $description -ne $process.ProcessName) {
        echo "    Description: $description"
    }

    if ($cim -and $cim.CommandLine) {
        $commandLine = $cim.CommandLine.Trim()
        if ($commandLine.Length -gt 300) {
            $commandLine = $commandLine.Substring(0, 300) + "..."
        }
        echo "    Command:     $commandLine"
    }

    if ($process.StartTime) {
        echo "    Started:     $($process.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    }

    if ($cim -and $cim.ParentProcessId -ne $cim.ProcessId) {
        $parentId = $cim.ParentProcessId
        $parent = $cimProcesses[$parentId]
        # Parent ids aren't cleared when the parent exits, so a newer process may have reused the id
        $parentName = if ($parent -and $parent.CreationDate -le $cim.CreationDate) { $parent.Name } else { "exited" }
        echo "    Parent:      $parentName [$parentId]"
    }

    $cpu = if ($process.TotalProcessorTime) { "{0:N1}s" -f $process.TotalProcessorTime.TotalSeconds } else { "N/A" }
    echo "    Memory:      $(formatBytes $process.WorkingSet64) (private: $(formatBytes $process.PrivateMemorySize64))"
    echo "    CPU time:    $cpu; Threads: $($process.Threads.Count); Handles: $($process.HandleCount)"
    echo ""
}

#endregion

if ($args.Count -eq 0) {
    echo "Must specify a process... (e.g. .\process-info.ps1 notepad)"
    echo "Additional arguments:     -a, --all:      Show all running processes"
    echo "Additional arguments:     -k, --kill:     Kill specified processes`n"
    exit 1
}

if ($args.Count -eq 1 -and ($args[0] -eq "--kill" -or $args[0] -eq "-k")) {
    echo "Must specify a process to kill... (e.g. .\process-info.ps1 notepad --kill)`n"
    exit 1
}

if ($args.Count -eq 1 -and ($args[0] -eq "--all" -or $args[0] -eq "-a")) {
    $processArgs = (Get-Process).ProcessName |sort -unique
} else {
    $processArgs = $args
}

if (($args.Contains("--all") -or $args.Contains("-a")) -and ($args.Contains("--kill") -or $args.Contains("-k"))) {
    echo "Can't kill all processes at once, are you crazy?!"
    exit 1
}

if ($args.Contains("--kill") -or $args.Contains("-k")) {
    foreach ($processArg in $processArgs) {
        $names = (Get-Process "*$processArg*" -ErrorAction 'silentlycontinue').ProcessName |sort -unique
        foreach ($name in $names) {
            echo "Killing $name..."
            Stop-Process -Name $name -Force
        }
    }

    exit 0
}

# Collect matches first so a process matched by several patterns is only shown once
$processes = @{}
foreach ($processArg in $processArgs) {
    foreach ($process in (Get-Process "*$processArg*" -ErrorAction 'silentlycontinue')) {
        $processes[$process.Id] = $process
    }
}

if ($processes.Count -eq 0) {
    exit 0
}

# Command line and parent aren't exposed by Get-Process, so query CIM once and look up by id
$cimProcesses = @{}
foreach ($cim in (Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine, CreationDate)) {
    $cimProcesses[$cim.ProcessId] = $cim
}

foreach ($process in ($processes.Values |sort ProcessName, Id)) {
    showInfo $process $cimProcesses
}

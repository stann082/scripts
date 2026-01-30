$icuePath = "C:\Program Files\Corsair\Corsair iCUE5 Software\iCUE.exe"
$processName = "iCUE"

Write-Host "Checking for running instance of iCUE..."

# Kill the process if it's running
$running = Get-Process -Name $processName -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "iCUE is running. Killing process..."
    Stop-Process -Name $processName -Force
    Start-Sleep -Seconds 3
} else {
    Write-Host "iCUE is not running."
}

# Restart the app
if (Test-Path $icuePath) {
    Write-Host "Restarting iCUE..."
    Start-Process -FilePath $icuePath
} else {
    Write-Error "iCUE executable not found at '$icuePath'"
}


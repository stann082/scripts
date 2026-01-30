# Define a timeout period in seconds (e.g., 60 seconds)
$timeout = 60
$waitTime = 1
$startTime = Get-Date

# Loop to check if nordvpn-service.exe is running
while (-not (Get-Process -Name "nordvpn-service" -ErrorAction SilentlyContinue)) {
    # Calculate the elapsed time
    $elapsedTime = (Get-Date) - $startTime
    
    # If the timeout period is exceeded, log an event and exit the loop
    if ($elapsedTime.TotalSeconds -ge $timeout) {
        $eventLogMessage = "NordVPN service did not start within the timeout period of $timeout seconds."
        Write-EventLog -LogName Application -Source "NordVPN Script" -EventID 1002 -EntryType Warning -Message $eventLogMessage
        exit
    }
    
    # Wait for a short interval before checking again
    Start-Sleep -Seconds $waitTime
}

# Execute the nordvpn -c command once the service is running
Start-Process "nordvpn" -ArgumentList '-c -g "Chicago"'

# Log success to the Event Log
$eventLogMessage = "NordVPN service started and connected successfully."
Write-EventLog -LogName Application -Source "NordVPN Script" -EventID 1003 -EntryType Information -Message $eventLogMessage

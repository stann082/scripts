<#
Usage:
    update-file-date.ps1 <file_path> <date>

    <date> accepts 'yyyy-MM-dd' or 'yyyy-MM-dd HH:mm'
    (time defaults to 00:00 if omitted)
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Date
)

# --- Guard clauses ---------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($FilePath)) {
    Write-Error "File path must not be empty."
    exit 1
}

if (-not (Test-Path -LiteralPath $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

$item = Get-Item -LiteralPath $FilePath -Force
if ($item.PSIsContainer) {
    Write-Error "Path points to a directory, not a file: $FilePath"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Date)) {
    Write-Error "Date must not be empty."
    exit 1
}

$parsedDate = [DateTime]::MinValue
$formats = @('yyyy-MM-dd HH:mm', 'yyyy-MM-dd')
$parsed = $false

foreach ($format in $formats) {
    if ([DateTime]::TryParseExact(
            $Date,
            $format,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$parsedDate)) {
        $parsed = $true
        break
    }
}

if (-not $parsed) {
    Write-Error "Invalid date format: '$Date'. Expected 'yyyy-MM-dd' or 'yyyy-MM-dd HH:mm'."
    exit 1
}

# --- Apply -------------------------------------------------------------

try {
    $item.CreationTime = $parsedDate
    $item.LastWriteTime = $parsedDate
}
catch {
    Write-Error "Failed to update timestamps on '$FilePath': $_"
    exit 1
}

Get-Item -LiteralPath $FilePath | Select-Object Name, CreationTime, LastWriteTime

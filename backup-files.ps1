$sourceDir = Join-Path $env:USERPROFILE ".keepass"
$destDir   = "E:\cepheus_bkp\KeePass Backups"

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Source folder not found: $sourceDir"
}

if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$zipName   = "keepass_bkp_{0}.zip" -f $timestamp
$zipPath   = Join-Path $destDir $zipName
$itemsToZip = Join-Path $sourceDir "*"
Compress-Archive -Path $itemsToZip -DestinationPath $zipPath -Force

Write-Host "Backup created:" $zipPath

<#
.SYNOPSIS
    Sets the Windows desktop wallpaper from the command line.

.DESCRIPTION
    Writes the fit style to HKCU:\Control Panel\Desktop, then calls the Win32
    SystemParametersInfo API so the change applies immediately and persists
    across reboots.

.PARAMETER Path
    Path to the image file. Relative paths are resolved to absolute, since the
    API silently ignores relative paths.

.PARAMETER Style
    How the image is fitted to the screen. Defaults to Fill.

.EXAMPLE
    .\Set-Wallpaper.ps1 -Path .\bg.jpg

.EXAMPLE
    .\Set-Wallpaper.ps1 -Path C:\Pictures\ultrawide.png -Style Span

.NOTES
    Must run in the target user's interactive session — this will not work from
    a SYSTEM-level scheduled task or a remote service. Windows Spotlight or a
    "Prevent changing desktop background" policy will override the setting.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [ValidateSet('Fill', 'Fit', 'Stretch', 'Tile', 'Center', 'Span')]
    [string]$Style = 'Fill'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Validate the image -----------------------------------------------------

$resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
if (-not $resolved) {
    throw "File not found: $Path"
}
$file = $resolved.ProviderPath

if (Test-Path -LiteralPath $file -PathType Container) {
    throw "Path is a directory, not an image file: $file"
}

$supported = '.bmp', '.dib', '.jpg', '.jpeg', '.jfif', '.png', '.gif', '.tif', '.tiff', '.wdp'
$ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
if ($supported -notcontains $ext) {
    Write-Warning "'$ext' is not a format Windows normally accepts as wallpaper. Trying anyway."
}

# --- Apply the fit style ----------------------------------------------------

$styleMap = @{
    Fill    = @{ WallpaperStyle = '10'; TileWallpaper = '0' }
    Fit     = @{ WallpaperStyle = '6';  TileWallpaper = '0' }
    Stretch = @{ WallpaperStyle = '2';  TileWallpaper = '0' }
    Tile    = @{ WallpaperStyle = '0';  TileWallpaper = '1' }
    Center  = @{ WallpaperStyle = '0';  TileWallpaper = '0' }
    Span    = @{ WallpaperStyle = '22'; TileWallpaper = '0' }
}

$desktopKey = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty -Path $desktopKey -Name WallpaperStyle -Value $styleMap[$Style].WallpaperStyle
Set-ItemProperty -Path $desktopKey -Name TileWallpaper  -Value $styleMap[$Style].TileWallpaper

# --- Set the wallpaper ------------------------------------------------------

if (-not ('WinAPI.Wallpaper' -as [type])) {
    Add-Type -Namespace WinAPI -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
'@
}

$SPI_SETDESKWALLPAPER = 0x0014
$SPIF_UPDATEINIFILE   = 0x01   # persist to the user profile
$SPIF_SENDCHANGE      = 0x02   # broadcast WM_SETTINGCHANGE so it applies now

$ok = [WinAPI.Wallpaper]::SystemParametersInfo(
    $SPI_SETDESKWALLPAPER,
    0,
    $file,
    $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE
)

if (-not $ok) {
    $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $msg  = (New-Object System.ComponentModel.Win32Exception $code).Message
    throw "SystemParametersInfo failed: $msg (error $code)"
}

Write-Host "Wallpaper set to $file (style: $Style)." -ForegroundColor Green

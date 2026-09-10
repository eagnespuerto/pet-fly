<#
.SYNOPSIS
    Builds PetFly: exports the Summer/Godot project, then packages an
    installer and an update feed with Velopack.

.DESCRIPTION
    Produces, in dist\:

        PetFly-win-Setup.exe        the installer users run
        PetFly-win-Portable.zip     no-install version
        PetFly-<ver>-full.nupkg     the update package
        releases.win.json           the feed the game checks for updates

    Publish the contents of dist\ to a static URL and set that URL as
    application/config/update_feed in project.godot; the game then offers
    updates in-game and applies them through Velopack's Update.exe.

.EXAMPLE
    pwsh tools\build.ps1
    pwsh tools\build.ps1 -Version 1.1.0 -SkipExport
#>
[CmdletBinding()]
param(
    # Defaults to application/config/version from project.godot.
    [string]$Version,
    [string]$Summer = "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe",
    [switch]$SkipExport,
    [switch]$SkipPack
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root "build\export"
$dist = Join-Path $root "dist"

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# --- version ---------------------------------------------------------------
if (-not $Version) {
    $line = Select-String -Path (Join-Path $root "project.godot") -Pattern '^config/version="([^"]+)"'
    if (-not $line) { throw "No config/version in project.godot; pass -Version." }
    $Version = $line.Matches[0].Groups[1].Value
}
Step "PetFly $Version"

if (-not (Test-Path $Summer)) { throw "Summer Engine not found at $Summer" }

# --- export ----------------------------------------------------------------
if (-not $SkipExport) {
    Step "Exporting with Summer Engine"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    # Import first so a clean checkout has its .godot cache built. Note: do
    # NOT redirect stderr here. Windows PowerShell wraps a native command's
    # stderr in ErrorRecords, which trips $ErrorActionPreference = "Stop" even
    # when the exe exits 0 - and Summer writes an informational notice there.
    & $Summer --headless --path $root --import | Out-Null
    & $Summer --headless --path $root --export-release "Windows Desktop" (Join-Path $stage "PetFly.exe") | Out-Null

    $exe = Join-Path $stage "PetFly.exe"
    if (-not (Test-Path $exe)) { throw "Export failed: $exe was not produced." }
    $mb = [math]::Round((Get-Item $exe).Length / 1MB, 1)
    Step "Exported PetFly.exe ($mb MB)"
}

# --- package ---------------------------------------------------------------
if ($SkipPack) { Step "Skipping packaging"; return }

$vpk = Join-Path $env:USERPROFILE ".dotnet\tools\vpk.exe"
if (-not (Test-Path $vpk)) {
    Warn "Velopack CLI not found. Install it with:"
    Warn "  dotnet tool install -g vpk"
    throw "vpk is required to build the installer."
}

# vpk needs a .NET 8 runtime. Summer ships one, so prefer that over whatever
# happens to be on PATH.
$summerDotnet = Split-Path -Parent $Summer | Join-Path -ChildPath "dotnet"
if (Test-Path (Join-Path $summerDotnet "dotnet.exe")) {
    $env:DOTNET_ROOT = $summerDotnet
    $env:PATH = "$summerDotnet;$env:PATH"
}

Step "Packaging with Velopack"
New-Item -ItemType Directory -Path $dist -Force | Out-Null

$notes = Join-Path $root "docs\RELEASE_NOTES.md"
$vpkArgs = @(
    "pack",
    "--packId", "PetFly",
    "--packVersion", $Version,
    "--packDir", $stage,
    "--mainExe", "PetFly.exe",
    "--packTitle", "PetFly",
    "--packAuthors", "PetFly",
    "--outputDir", $dist,
    "--channel", "win",
    "--shortcuts", "Desktop,StartMenuRoot"
)
$icon = Join-Path $root "installer\PetFly.ico"
if (Test-Path $icon) { $vpkArgs += @("--icon", $icon) }
if (Test-Path $notes) { $vpkArgs += @("--releaseNotes", $notes) }

& $vpk @vpkArgs
if ($LASTEXITCODE -ne 0) { throw "vpk pack failed with exit code $LASTEXITCODE" }

Step "Done. Artifacts in $dist"
Get-ChildItem $dist | Sort-Object Name | ForEach-Object {
    "    {0,-40} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB)
}

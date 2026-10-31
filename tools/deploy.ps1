<#
.SYNOPSIS
  Copies the shipped addon files into the WoW Forever AddOns folder.

.PARAMETER GamePath
  WoW Forever client folder, i.e. the one containing "Interface".
  Defaults to $env:REAGENTATLAS_GAME_PATH.

.EXAMPLE
  .\tools\deploy.ps1 -GamePath "C:\Games\World of Warcraft\_forever_"
#>
param(
    [string]$GamePath = $env:REAGENTATLAS_GAME_PATH
)

$ErrorActionPreference = 'Stop'

$AddonName = 'ReagentAtlas'
$ShipDirs = @('Data', 'Modules', 'UI', 'Media')
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $GamePath) {
    throw "No game path. Pass -GamePath or set REAGENTATLAS_GAME_PATH to the Forever client folder (the one containing 'Interface')."
}
if (-not (Test-Path -LiteralPath $GamePath -PathType Container)) {
    throw "Game path not found: $GamePath"
}

$AddOnsDir = Join-Path $GamePath 'Interface\AddOns'
if (-not (Test-Path -LiteralPath $AddOnsDir)) {
    New-Item -ItemType Directory -Path $AddOnsDir | Out-Null
}
$Target = Join-Path $AddOnsDir $AddonName

# Start from a clean folder so files deleted from the repo don't linger in-game.
if (Test-Path -LiteralPath $Target) {
    Remove-Item -LiteralPath $Target -Recurse -Force
}
New-Item -ItemType Directory -Path $Target | Out-Null

$copied = 0
Get-ChildItem -LiteralPath $RepoRoot -File | Where-Object { $_.Extension -in '.toc', '.lua' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Target
    $copied++
}

foreach ($dir in $ShipDirs) {
    $src = Join-Path $RepoRoot $dir
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $Target -Recurse
        $copied += (Get-ChildItem -LiteralPath $src -File -Recurse).Count
    }
}

Write-Host "Deployed $copied files to $Target"

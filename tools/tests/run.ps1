# Runs the offline Lua tests using the LuaLS binary from the VS Code extension
# as the interpreter (no standalone Lua install needed).
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Exe = Get-ChildItem "$env:USERPROFILE\.vscode\extensions\sumneko.lua-*\server\bin\lua-language-server.exe" |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $Exe) { throw "LuaLS (sumneko.lua) VS Code extension not found." }

& $Exe.FullName (Join-Path $PSScriptRoot 'run.lua') $RepoRoot
exit $LASTEXITCODE

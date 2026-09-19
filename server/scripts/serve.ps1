<#
SafeTAcademy AI backend - the runner that Task Scheduler launches.
Can also be run by hand:  powershell -ExecutionPolicy Bypass -File scripts\serve.ps1

It does exactly three things:

  1. turn server/.env into PROCESS environment variables
     The server itself deliberately does NOT read .env (see README "部署") -
     that is what keeps "where do the keys come from" a single decision.
     Something outside has to feed them in, and on Linux that is systemd's
     EnvironmentFile. This script is the Windows equivalent.

  2. locate node.exe
     The managed runtime sits in a VERSIONED folder (22.22.2-3), so a hardcoded
     path would silently break on the next upgrade. We pick the highest version
     present and fall back to whatever is on PATH.

  3. start node and wait for it, appending stdout/stderr to logs/backend.log
     The process lives exactly as long as this script does. Task Scheduler owns
     the lifetime; stop it with  manage-autostart.ps1 -Action Stop.

Environment overrides (optional):
  SAFETA_NODE   full path to node.exe
  SAFETA_LOG    full path to the log file
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ServerDir = Split-Path -Parent $PSScriptRoot          # .../server
$EnvFile   = Join-Path $ServerDir '.env'
$Entry     = Join-Path $ServerDir 'src\index.js'
$LogDir    = Join-Path $ServerDir 'logs'
$LogFile   = if ($env:SAFETA_LOG) { $env:SAFETA_LOG } else { Join-Path $LogDir 'backend.log' }
$MaxLogBytes = 5MB

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Log {
    param([string]$Message)
    $line = '[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $Message
    Write-Host $line
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }
        [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, $Utf8NoBom)
    } catch {
        # A log write must never take the service down.
    }
}

function Import-DotEnv {
    param([string]$Path)
    $loaded = 0
    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
        if ($line.StartsWith('export ')) { $line = $line.Substring(7).Trim() }
        $eq = $line.IndexOf('=')
        if ($eq -le 0) { continue }
        $name = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        $loaded++
    }
    return $loaded
}

function Resolve-NodePath {
    if ($env:SAFETA_NODE -and (Test-Path -LiteralPath $env:SAFETA_NODE)) {
        return $env:SAFETA_NODE
    }
    $versionsRoot = Join-Path $env:USERPROFILE '.workbuddy\binaries\node\versions'
    if (Test-Path -LiteralPath $versionsRoot) {
        $best = $null
        $bestKey = -1
        foreach ($dir in Get-ChildItem -LiteralPath $versionsRoot -Directory -ErrorAction SilentlyContinue) {
            # Folder names look like "22.22.2-3"; compare numerically so that
            # 22 does not sort below 9 the way a plain string sort would.
            $m = [regex]::Match($dir.Name, '^(\d+)\.(\d+)\.(\d+)')
            if (-not $m.Success) { continue }
            $key = [int]$m.Groups[1].Value * 1000000 + [int]$m.Groups[2].Value * 1000 + [int]$m.Groups[3].Value
            if ($key -gt $bestKey) {
                $bestKey = $key
                $best = $dir
            }
        }
        if ($best) {
            $exe = Join-Path $best.FullName 'node.exe'
            if (Test-Path -LiteralPath $exe) { return $exe }
        }
    }
    $onPath = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    return $null
}

function Rotate-Log {
    if (-not (Test-Path -LiteralPath $LogFile)) { return }
    if ((Get-Item -LiteralPath $LogFile).Length -le $MaxLogBytes) { return }
    $previous = $LogFile + '.1'
    if (Test-Path -LiteralPath $previous) {
        Remove-Item -LiteralPath $previous -Force
    }
    Move-Item -LiteralPath $LogFile -Destination $previous
}

function Get-ConfiguredPort {
    if ($env:PORT) {
        $parsed = 0
        if ([int]::TryParse($env:PORT, [ref]$parsed) -and $parsed -gt 0) { return $parsed }
    }
    return 8787
}

# ------------------------------------------------------------------ main

Write-Log '--- starting ---'

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Write-Log "FATAL: $EnvFile not found. Copy .env.example to .env and fill it in."
    exit 2
}
if (-not (Test-Path -LiteralPath $Entry)) {
    Write-Log "FATAL: $Entry not found."
    exit 2
}

$node = Resolve-NodePath
if (-not $node) {
    Write-Log 'FATAL: node.exe not found. Set SAFETA_NODE to its full path.'
    exit 2
}

$keyCount = Import-DotEnv -Path $EnvFile
$port = Get-ConfiguredPort

Write-Log "node     : $node"
Write-Log "env file : $EnvFile ($keyCount keys loaded)"
Write-Log "port     : $port"
Write-Log "log file : $LogFile"

if (-not $env:APP_TOKEN) {
    Write-Log 'WARNING: APP_TOKEN is empty - authentication is DISABLED.'
}

Rotate-Log

$busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    $holder = ($busy | Select-Object -ExpandProperty OwningProcess -Unique) -join ', '
    Write-Log "already listening on port $port (pid $holder); nothing to do."
    exit 0
}

# cmd.exe performs the redirection so the bytes reach the file untouched.
# PowerShell's own redirection re-encodes the stream, which turns the server's
# UTF-8 JSON logs into mojibake. The command deliberately starts with `cd`
# rather than a quote: cmd strips the outer quote pair when a /c string begins
# with one, which would corrupt a path containing spaces.
$commandLine = 'cd /d "' + $ServerDir + '" && "' + $node + '" "' + $Entry + '" >> "' + $LogFile + '" 2>&1'

Write-Log 'launching node...'
& cmd.exe /c $commandLine
$exitCode = $LASTEXITCODE

Write-Log "--- node exited with code $exitCode ---"
exit $exitCode

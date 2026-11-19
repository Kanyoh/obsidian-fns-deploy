<#
.SYNOPSIS
  Manage the portable Fast Note Sync Service installation.

.EXAMPLE
  .\manage.ps1 status
  .\manage.ps1 backup
  .\manage.ps1 update -Version 3.6.1
#>
param(
    [ValidateSet('start', 'stop', 'restart', 'status', 'backup', 'update', 'logs', 'uninstall', 'open')]
    [string]$Action = 'status',
    [string]$Version = "",
    [switch]$KeepFiles
)

$ErrorActionPreference = 'SilentlyContinue'
$Dir = $PSScriptRoot
$Exe = Join-Path $Dir 'fast-note-sync-service.exe'
$Config = Join-Path $Dir 'config\config.yaml'
$Logs = Join-Path $Dir 'logs'

function Get-Port {
    if (Test-Path $Config) {
        $m = [regex]::Match((Get-Content $Config -Raw), '(?m)^\s*http-port:\s*":(\d+)"')
        if ($m.Success) { return [int]$m.Groups[1].Value }
    }
    return 9000
}

function Get-ServerProcess {
    Get-CimInstance Win32_Process -Filter "Name='fast-note-sync-service.exe'" |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $Exe) }
}

function Start-Server {
    if (Get-ServerProcess) { Write-Host "already running"; return }
    New-Item -ItemType Directory -Force -Path $Logs | Out-Null
    $out = Join-Path $Logs 'stdout.log'
    $err = Join-Path $Logs 'stderr.log'
    $p = Start-Process -FilePath $Exe -ArgumentList @('run', '-c', 'config\config.yaml') -WorkingDirectory $Dir -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    Set-Content -Path (Join-Path $Dir 'fns.pid') -Value $p.Id
    Write-Host "started pid=$($p.Id) port=$(Get-Port)"
}

function Stop-Server {
    $procs = Get-ServerProcess
    if (-not $procs) { Write-Host "not running"; return }
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force }
    Start-Sleep -Seconds 2
    Write-Host "stopped"
}

function Show-Status {
    $port = Get-Port
    $procs = Get-ServerProcess
    if ($procs) {
        foreach ($p in $procs) { Write-Host "process: pid=$($p.ProcessId) started=$($p.CreationDate)" }
    } else {
        Write-Host "process: not running"
    }
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 5
        Write-Host "http:    OK $($r.StatusCode) http://127.0.0.1:$port/"
    } catch {
        Write-Host "http:    FAIL $($_.Exception.Message)"
    }
}

function Do-Backup {
    $port = Get-Port
    $wasRunning = [bool](Get-ServerProcess)
    if ($wasRunning) { Stop-Server | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path $Dir 'backups'
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $zip = Join-Path $backupDir "fns-backup-$stamp.zip"
    $items = @()
    foreach ($name in @('config', 'storage')) {
        $path = Join-Path $Dir $name
        if (Test-Path $path) { $items += $path }
    }
    if ($items.Count -eq 0) { Write-Host "nothing to back up"; return }
    Compress-Archive -Path $items -DestinationPath $zip -Force
    Write-Host "backup: $zip"
    Get-ChildItem $backupDir -Filter 'fns-backup-*.zip' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 7 | Remove-Item -Force
    if ($wasRunning) { Start-Server | Out-Null }
}

function Do-Update {
    if (-not $Version) { Write-Host "usage: manage.ps1 update -Version 3.6.1"; return }
    $asset = "fast-note-sync-service-$Version-windows-amd64.tar.gz"
    $url = "https://gh-proxy.com/https://github.com/haierkeys/fast-note-sync-service/releases/download/$Version/$asset"
    $tmp = Join-Path $env:TEMP $asset
    Write-Host "downloading $Version ..."
    & curl.exe -sL --max-time 900 --retry 3 --retry-all-errors -C - -o $tmp $url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { Write-Host "download failed"; return }
    $extract = Join-Path $env:TEMP ("fns-update-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    & tar.exe -xzf $tmp -C $extract
    if (-not (Test-Path (Join-Path $extract 'fast-note-sync-service.exe'))) { Write-Host "bad archive"; return }
    Stop-Server | Out-Null
    Copy-Item (Join-Path $extract 'fast-note-sync-service.exe') $Exe -Force
    Write-Host "binary updated"
    Start-Server | Out-Null
    Show-Status
}

switch ($Action) {
    'start'     { Start-Server }
    'stop'      { Stop-Server }
    'restart'   { Stop-Server | Out-Null; Start-Server }
    'status'    { Show-Status }
    'backup'    { Do-Backup }
    'update'    { Do-Update }
    'logs'      { Get-Content (Join-Path $Logs 'stdout.log') -Tail 50 -Wait }
    'open'      { Start-Process "http://127.0.0.1:$(Get-Port)/" }
    'uninstall' {
        Stop-Server | Out-Null
        & schtasks.exe /Delete /TN "FNS-ObsidianSync" /F | Out-Null
        if (-not $KeepFiles) { Remove-Item $Dir -Recurse -Force }
        Write-Host "uninstalled"
    }
}

<#
.SYNOPSIS
  One-click installer for Fast Note Sync Service on Windows (no Docker, no admin required).

.DESCRIPTION
  Downloads the official Windows build, extracts it into a portable folder,
  writes a config with a random auth key and the requested port, registers a
  logon scheduled task (optional) and starts the service.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
  .\install.ps1 -Port 9000 -InstallDir "C:\FNS" -Tailscale
#>
param(
    [int]$Port = 9000,
    [string]$InstallDir = "$env:LOCALAPPDATA\FNS",
    [string]$Version = "3.6.1",
    [ValidateSet('auto', 'github', 'ghproxy')]
    [string]$Mirror = 'auto',
    [string]$LocalArchive = "",
    [switch]$SkipFirewall,
    [switch]$NoTask,
    [switch]$NoStart,
    [switch]$Tailscale
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -eq 'ARM64') {
    Write-Warn "Windows ARM64 detected; official builds are amd64 (will run under emulation)."
}
$asset = "fast-note-sync-service-$Version-windows-amd64.tar.gz"
$official = "https://github.com/haierkeys/fast-note-sync-service/releases/download/$Version/$asset"
$mirrorUrl = "https://gh-proxy.com/$official"

Write-Step "Checking prerequisites"
if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    throw "tar.exe not found (Windows 10 1803+ is required)."
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "curl.exe not found (Windows 10 1803+ is required)."
}
Write-Ok "tar.exe / curl.exe OK"

Write-Step "Preparing $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir, "$InstallDir\config", "$InstallDir\logs", "$InstallDir\backups" | Out-Null
$zipPath = Join-Path $env:TEMP $asset

function Download-Asset($url, $out) {
    if (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }
    $curlArgs = @('-sL', '--max-time', '900', '--retry', '3', '--retry-all-errors', '-C', '-', '-o', $out, '-w', '%{http_code}', $url)
    $code = & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out) -or (Get-Item $out).Length -lt 10MB) {
        return $false
    }
    return $true
}

Write-Step "Preparing package"
$ok = $false
if ($LocalArchive) {
    if (-not (Test-Path $LocalArchive)) { throw "LocalArchive not found: $LocalArchive" }
    Copy-Item $LocalArchive $zipPath -Force
    $ok = $true
    Write-Ok "using local archive: $LocalArchive"
} else {
    Write-Step "Downloading $asset"
    if ($Mirror -ne 'github') {
        Write-Host "    trying mirror: gh-proxy.com"
        $ok = Download-Asset $mirrorUrl $zipPath
    }
    if (-not $ok -and $Mirror -ne 'ghproxy') {
        Write-Host "    trying official GitHub"
        $ok = Download-Asset $official $zipPath
    }
    if (-not $ok) { throw "Download failed. Re-run with -Mirror ghproxy, -LocalArchive <file>, or download manually from the Releases page." }
    Write-Ok ("downloaded " + [math]::Round((Get-Item $zipPath).Length / 1MB, 1) + " MB")
}

Write-Step "Extracting"
$tmp = Join-Path $env:TEMP ("fns-extract-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
& tar.exe -xzf $zipPath -C $tmp
if ($LASTEXITCODE -ne 0) { throw "Extraction failed." }
Copy-Item (Join-Path $tmp 'fast-note-sync-service.exe') (Join-Path $InstallDir 'fast-note-sync-service.exe') -Force
Unblock-File (Join-Path $InstallDir 'fast-note-sync-service.exe') -ErrorAction SilentlyContinue
$templateConfig = Join-Path $tmp 'config\config.yaml'
if (-not (Test-Path $templateConfig)) { throw "config.yaml not found in the release archive." }

Write-Step "Writing config (port $Port, random auth key)"
$configText = Get-Content $templateConfig -Raw -Encoding UTF8
$keyBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($keyBytes)
$authKey = [Convert]::ToBase64String($keyBytes)

$configText = [regex]::Replace($configText, '(?m)^(\s*http-port:\s*)":\d+"', ('${1}":' + $Port + '"'))
$configText = [regex]::Replace($configText, '(?m)^(\s*auth-token-key:\s*).*$', ('${1}' + $authKey))
$configText = [regex]::Replace($configText, '(?m)^(\s*level:\s*)warn\s*$', '${1}info')
$configPath = Join-Path $InstallDir 'config\config.yaml'
[System.IO.File]::WriteAllText($configPath, $configText, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "config: $configPath"

Write-Step "Installing management script"
Copy-Item (Join-Path $PSScriptRoot 'manage.ps1') (Join-Path $InstallDir 'manage.ps1') -Force
Write-Ok "manage.ps1 -> $InstallDir"

if (-not $NoTask) {
    Write-Step "Registering logon scheduled task (no admin required)"
    $action = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallDir\manage.ps1`" start"
    & schtasks.exe /Create /SC ONLOGON /TN "FNS-ObsidianSync" /TR $action /RL LIMITED /F | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "task FNS-ObsidianSync created (starts at every logon)" }
    else { Write-Warn "could not create scheduled task; add it manually or run manage.ps1 start" }
}

if (-not $SkipFirewall) {
    Write-Step "Firewall (LAN access)"
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        & netsh.exe advfirewall firewall delete rule name="FNS Obsidian Sync" | Out-Null
        & netsh.exe advfirewall firewall add rule name="FNS Obsidian Sync" dir=in action=allow protocol=TCP localport=$Port | Out-Null
        Write-Ok "inbound TCP $Port allowed"
    } else {
        Write-Warn "not elevated: skip firewall rule. LAN devices may not connect;"
        Write-Warn "run this installer as Administrator once, or use Tailscale (recommended)."
    }
}

if (-not $NoStart) {
    Write-Step "Starting service"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallDir 'manage.ps1') start
    Start-Sleep -Seconds 3
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 10
        Write-Ok "HTTP $($r.StatusCode) on http://127.0.0.1:$Port/"
    } catch {
        Write-Warn "service did not answer yet; check $InstallDir\logs"
    }
}

Write-Step "Access URLs"
$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress
Write-Host "    Local:  http://127.0.0.1:$Port"
foreach ($ip in $ips) { Write-Host "    LAN:    http://$($ip):$Port" }

if ($Tailscale) {
    Write-Step "Tailscale"
    $ts = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if (-not $ts) {
        Write-Warn "tailscale not found. Install it from https://tailscale.com/download and run:"
        Write-Warn "  tailscale up"
        Write-Warn "  tailscale serve --bg $Port"
    } else {
        & tailscale.exe serve --bg $Port | Out-Host
        $st = & tailscale.exe status --json | ConvertFrom-Json
        if ($st.Self.DNSName) {
            $dns = $st.Self.DNSName.TrimEnd('.')
            Write-Ok "Tailnet HTTPS: https://$dns"
        }
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open the Local/LAN URL above and register your account (e.g. Wink)."
Write-Host "  2. Web UI -> Vaults -> Copy API Config."
Write-Host "  3. Obsidian -> Fast Note Sync -> paste the config."
Write-Host "  4. For access outside the office, see docs/03-remote-access-tailscale.md"
Write-Host ""
Write-Host "Manage:  powershell -File `"$InstallDir\manage.ps1`" status|stop|start|backup|logs"

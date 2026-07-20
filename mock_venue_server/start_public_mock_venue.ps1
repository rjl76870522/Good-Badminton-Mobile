param(
    [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$serverPidFile = Join-Path $PSScriptRoot '.server.pid'
$tunnelPidFile = Join-Path $PSScriptRoot '.tunnel.pid'
$serverOutLog = Join-Path $PSScriptRoot 'server.out.log'
$serverErrLog = Join-Path $PSScriptRoot 'server.err.log'
$tunnelOutLog = Join-Path $PSScriptRoot 'tunnel.out.log'
$tunnelErrLog = Join-Path $PSScriptRoot 'tunnel.err.log'

function Stop-ManagedProcess([string] $pidFile) {
    if (Test-Path $pidFile) {
        $processId = (Get-Content -Raw $pidFile).Trim()
        if ($processId) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $processId -Timeout 5 -ErrorAction SilentlyContinue
        }
        Remove-Item -Force $pidFile -ErrorAction SilentlyContinue
    }
}

try {
    if (Test-Path $serverPidFile) {
        throw 'Mock Venue Server may already be running. Run stop_mock_venue_server.bat first.'
    }

    $python = Get-Command python -ErrorAction Stop
    $cloudflaredCommand = Get-Command cloudflared -ErrorAction SilentlyContinue
    $cloudflaredPath = if ($cloudflaredCommand) {
        $cloudflaredCommand.Source
    } elseif (Test-Path 'C:\Program Files (x86)\cloudflared\cloudflared.exe') {
        'C:\Program Files (x86)\cloudflared\cloudflared.exe'
    } elseif (Test-Path 'C:\Program Files\cloudflared\cloudflared.exe') {
        'C:\Program Files\cloudflared\cloudflared.exe'
    } else {
        throw 'cloudflared was not found. Install the Cloudflare cloudflared client first.'
    }

    Write-Host 'Starting Mock Venue Server on local port 9000...'
    $server = Start-Process -FilePath $python.Source `
        -ArgumentList '-m', 'uvicorn', 'mock_venue_server.main:app', '--host', '0.0.0.0', '--port', '9000' `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput $serverOutLog `
        -RedirectStandardError $serverErrLog -PassThru
    Set-Content -LiteralPath $serverPidFile -Value $server.Id

    $serverReady = $false
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        try {
            $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 'http://127.0.0.1:9000/venue'
            if ($response.StatusCode -eq 200) {
                $serverReady = $true
                break
            }
        } catch {
            # Uvicorn is still starting.
        }
    }
    if (-not $serverReady) {
        throw 'The local server did not start. See mock_venue_server/server.err.log.'
    }

    Write-Host 'Creating a temporary public URL. Please wait...'
    Remove-Item -Force $tunnelOutLog, $tunnelErrLog -ErrorAction SilentlyContinue
    $tunnel = Start-Process -FilePath $cloudflaredPath `
        -ArgumentList 'tunnel', '--url', 'http://127.0.0.1:9000', '--protocol', 'http2', '--no-autoupdate' `
        -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput $tunnelOutLog `
        -RedirectStandardError $tunnelErrLog -PassThru
    Set-Content -LiteralPath $tunnelPidFile -Value $tunnel.Id

    $publicUrl = $null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $tunnelLog = @(
            Get-Content -Raw $tunnelOutLog -ErrorAction SilentlyContinue
            Get-Content -Raw $tunnelErrLog -ErrorAction SilentlyContinue
        ) -join "`n"
        $matches = [regex]::Matches(
            $tunnelLog,
            'https://[a-z0-9-]+\.trycloudflare\.com',
            'IgnoreCase'
        )
        if ($matches.Count -gt 0) {
            $publicUrl = $matches[$matches.Count - 1].Value
            break
        }
    }
    if (-not $publicUrl) {
        throw 'No public URL was received. See mock_venue_server/tunnel.err.log.'
    }

    & $python.Source (Join-Path $PSScriptRoot 'generate_qr.py') $publicUrl
    if ($LASTEXITCODE -ne 0) {
        throw 'QR code generation failed.'
    }

    Write-Host ''
    Write-Host 'Mock Venue Server is public and ready.' -ForegroundColor Green
    Write-Host "Public URL: $publicUrl"
    Write-Host 'QR code updated. Opening the QR page in your browser.'
    if (-not $NoBrowser) {
        Start-Process $publicUrl
    }
} catch {
    Write-Host "Startup failed: $($_.Exception.Message)" -ForegroundColor Red
    Stop-ManagedProcess $tunnelPidFile
    Stop-ManagedProcess $serverPidFile
    exit 1
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe module..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe

$scriptPath = Join-Path $PSScriptRoot "NetSpeed.ps1"
$exePath    = Join-Path $PSScriptRoot "NetSpeed.exe"

Write-Host "Compiling $scriptPath -> $exePath ..." -ForegroundColor Cyan

Invoke-ps2exe -inputFile $scriptPath `
              -outputFile $exePath `
              -noConsole `
              -STA `
              -winFormsDPIAware `
              -title "NetSpeed" `
              -description "NetSpeed Network Speed Monitor" `
              -version "1.0.0.0"

Write-Host "Done! Output: $exePath" -ForegroundColor Green

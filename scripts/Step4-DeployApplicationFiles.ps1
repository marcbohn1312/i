#Requires -Version 5.1
<#
    Step4-DeployApplicationFiles.ps1
    Kopiert die optixxl-Anwendungsdateien aus dem Installer-Payload nach $INSTDIR\app.
#>

param(
    [Parameter(Mandatory)][string]$SourceDir,
    [Parameter(Mandatory)][string]$InstallDir,
    [string]$AppVersion = '0.0.0'
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step4-DeployApplicationFiles'
Initialize-Log

try {
    $appDir = Join-Path $InstallDir 'app'
    $versionMarker = Join-Path $appDir 'version.txt'

    if ((Test-Path -LiteralPath $versionMarker) -and
        (Get-Content -LiteralPath $versionMarker -Raw).Trim() -eq $AppVersion) {
        Write-Log "$stepName: Version $AppVersion bereits deployt, ueberspringe."
        Set-StepCompleted -StepName $stepName
        exit 0
    }

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Quellverzeichnis nicht gefunden: $SourceDir"
    }

    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    Copy-Item -Path (Join-Path $SourceDir '*') -Destination $appDir -Recurse -Force
    Set-Content -LiteralPath $versionMarker -Value $AppVersion -Encoding UTF8

    Set-StepCompleted -StepName $stepName
    Write-Log "$stepName: Anwendungsdateien Version $AppVersion nach '$appDir' deployt."
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

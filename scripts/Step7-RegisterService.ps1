#Requires -Version 5.1
<#
    Step7-RegisterService.ps1
    Registriert die optixxl-Anwendung als Windows-Dienst und startet ihn.
#>

param(
    [string]$ServiceName = 'optixxl',
    [Parameter(Mandatory)][string]$BinaryPath
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step7-RegisterService'
Initialize-Log

try {
    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $existing) {
        if (-not (Test-Path -LiteralPath $BinaryPath)) {
            throw "Dienst-Binary nicht gefunden: $BinaryPath"
        }

        Invoke-ExternalTool -FilePath (Join-Path $env:WINDIR 'System32\sc.exe') -ArgumentList @(
            'create', $ServiceName,
            'binPath=', $BinaryPath,
            'start=', 'auto',
            'DisplayName=', 'optixxl'
        )
        Write-Log "$stepName: Dienst '$ServiceName' registriert."
    }
    else {
        Write-Log "$stepName: Dienst '$ServiceName' existiert bereits, ueberspringe Registrierung."
    }

    $service = Get-Service -Name $ServiceName
    if ($service.Status -ne 'Running') {
        Start-Service -Name $ServiceName
        Write-Log "$stepName: Dienst '$ServiceName' gestartet."
    }
    else {
        Write-Log "$stepName: Dienst '$ServiceName' laeuft bereits."
    }

    Set-StepCompleted -StepName $stepName
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

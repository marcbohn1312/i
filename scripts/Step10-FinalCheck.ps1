#Requires -Version 5.1
<#
    Step10-FinalCheck.ps1
    Prueft am Ende der Installation, dass alle vorherigen Schritte tatsaechlich einen
    funktionsfaehigen Zustand hinterlassen haben, und schreibt eine Zusammenfassung ins
    install.log. Ueberspringt sich NICHT selbst -- laeuft bei jedem Installer-Durchlauf,
    da er nur prueft und nichts veraendert.
#>

param(
    [string]$InstanceName = 'OPTIXXL',
    [string]$DatabaseName = 'optixxl',
    [string]$ShareName = 'OptixxlFreigabe',
    [string]$ServiceName = 'optixxl',
    [Parameter(Mandatory)][string]$InstallDir
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step10-FinalCheck'
Initialize-Log

$checks = [ordered]@{}

try {
    $sqlService = Get-Service -Name "MSSQL`$$InstanceName" -ErrorAction SilentlyContinue
    $checks['SQL-Dienst laeuft'] = ($sqlService -and $sqlService.Status -eq 'Running')

    $regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    $checks['SQL-Instanz registriert'] = (Test-Path -LiteralPath $regPath) -and
        ($null -ne (Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue).$InstanceName)

    $checks['Anwendungsdateien deployt'] = Test-Path -LiteralPath (Join-Path $InstallDir 'app\version.txt')

    $checks['Freigabe vorhanden'] = $null -ne (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)

    $appService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $checks['Anwendungsdienst laeuft'] = ($appService -and $appService.Status -eq 'Running')

    $checks['Startmenue-Verknuepfung vorhanden'] = Test-Path -LiteralPath (
        Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'Programs\optixxl\optixxl.lnk')

    $failed = $checks.GetEnumerator() | Where-Object { -not $_.Value }

    Write-Log "$stepName: Zusammenfassung:"
    foreach ($entry in $checks.GetEnumerator()) {
        $status = if ($entry.Value) { 'OK' } else { 'FEHLT' }
        Write-Log ("  [{0}] {1}" -f $status, $entry.Key)
    }

    if ($failed) {
        throw "Abschlusspruefung fehlgeschlagen: $($failed.Name -join ', ')"
    }

    Set-StepCompleted -StepName $stepName
    Write-Log "$stepName: alle Pruefungen erfolgreich, Installation abgeschlossen."
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

#Requires -Version 5.1
<#
    Uninstall.ps1

    Wird vom optixxl-Deinstallationsassistenten aufgerufen und nutzt dieselben, vom
    Installer bereits nach $INSTDIR\scripts deployten Hilfsfunktionen (Common.ps1), um
    alles rueckgaengig zu machen, was die Step1-10-Skripte angelegt haben. Jeder Block ist
    einzeln idempotent: fehlt das jeweilige Ziel bereits, wird der Block uebersprungen statt
    einen Fehler zu werfen.
#>

param(
    [Parameter(Mandatory)][string]$InstallDir,
    [string]$InstanceName = 'OPTIXXL',
    [string]$ShareName = 'OptixxlFreigabe',
    [string]$LocalUserName = 'OptixxlFreigabe',
    [string]$ServiceName = 'optixxl',
    [switch]$RemoveSqlInstance
)

. "$PSScriptRoot\Common.ps1"

Initialize-Log
Write-Log "Deinstallation gestartet fuer InstallDir='$InstallDir'."

$errors = @()

# Anwendungsdienst
try {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -eq 'Running') { Stop-Service -Name $ServiceName -Force }
        Invoke-ExternalTool -FilePath (Join-Path $env:WINDIR 'System32\sc.exe') -ArgumentList @('delete', $ServiceName)
        Write-Log "Dienst '$ServiceName' entfernt."
    }
    else {
        Write-Log "Dienst '$ServiceName' nicht vorhanden, ueberspringe."
    }
}
catch { $errors += $_; Write-Log "Fehler beim Entfernen des Dienstes: $($_.Exception.Message)" -Level ERROR }

# Freigabe + lokaler Benutzer
try {
    if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
        Remove-SmbShare -Name $ShareName -Force
        Write-Log "Freigabe '$ShareName' entfernt."
    }
    if (Get-LocalUser -Name $LocalUserName -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $LocalUserName
        Write-Log "Lokaler Benutzer '$LocalUserName' entfernt."
    }
}
catch { $errors += $_; Write-Log "Fehler beim Entfernen von Freigabe/Benutzer: $($_.Exception.Message)" -Level ERROR }

# Firewall-Regeln
try {
    Get-NetFirewallRule -DisplayName 'optixxl*' -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-NetFirewallRule -DisplayName $_.DisplayName
        Write-Log "Firewall-Regel '$($_.DisplayName)' entfernt."
    }
}
catch { $errors += $_; Write-Log "Fehler beim Entfernen der Firewall-Regeln: $($_.Exception.Message)" -Level ERROR }

# Verknuepfungen
try {
    $startMenuDir = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'Programs\optixxl'
    if (Test-Path -LiteralPath $startMenuDir) {
        Remove-Item -LiteralPath $startMenuDir -Recurse -Force
        Write-Log "Startmenue-Ordner '$startMenuDir' entfernt."
    }
    $desktopLink = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'optixxl.lnk'
    if (Test-Path -LiteralPath $desktopLink) {
        Remove-Item -LiteralPath $desktopLink -Force
        Write-Log "Desktop-Verknuepfung entfernt."
    }
}
catch { $errors += $_; Write-Log "Fehler beim Entfernen der Verknuepfungen: $($_.Exception.Message)" -Level ERROR }

# SQL-Server-Instanz (standardmaessig NICHT entfernt, da andere Anwendungen sie mitnutzen
# koennten -- nur auf ausdruecklichen Wunsch per -RemoveSqlInstance).
if ($RemoveSqlInstance) {
    try {
        $setupExe = Get-ChildItem -Path "${env:ProgramFiles}\Microsoft SQL Server" -Filter 'setup.exe' `
            -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($setupExe) {
            Invoke-ExternalTool -FilePath $setupExe.FullName -ArgumentList @(
                '/ACTION=Uninstall', '/QUIET', "/INSTANCENAME=$InstanceName", '/FEATURES=SQLENGINE'
            )
            Write-Log "SQL-Server-Instanz '$InstanceName' deinstalliert."
        }
        else {
            Write-Log "setup.exe fuer SQL-Server-Deinstallation nicht gefunden, ueberspringe." -Level WARN
        }
    }
    catch { $errors += $_; Write-Log "Fehler beim Entfernen der SQL-Instanz: $($_.Exception.Message)" -Level ERROR }
}
else {
    Write-Log "SQL-Server-Instanz '$InstanceName' wird beibehalten (kein -RemoveSqlInstance angegeben)."
}

# Schritt-Marker zuruecksetzen
try {
    $markerDir = Join-Path $env:ProgramData 'optixxl\steps'
    if (Test-Path -LiteralPath $markerDir) {
        Remove-Item -LiteralPath $markerDir -Recurse -Force
    }
}
catch { $errors += $_; Write-Log "Fehler beim Zuruecksetzen der Schritt-Marker: $($_.Exception.Message)" -Level ERROR }

if ($errors.Count -gt 0) {
    Write-Log "Deinstallation mit $($errors.Count) Fehler(n) beendet." -Level ERROR
    exit 1
}

Write-Log "Deinstallation erfolgreich abgeschlossen."
exit 0

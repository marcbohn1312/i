#Requires -Version 5.1
<#
    Step1-InstallSqlServer.ps1

    Installiert SQL Server 2025 Express unbeaufsichtigt aus dem eingebetteten
    "Direct Package" (SQLEXPR_x64_DEU.exe, ca. 754 MB), das der Installer nach
    $INSTDIR\scripts\SQLEXPR_x64_DEU.exe entpackt hat.

    STATUS: aktuell verfolgter, NOCH NICHT verifizierter Bug
    -----------------------------------------------------------------------
    Das SQL-Server-2025-Express-Setup schlaegt unbeaufsichtigt fehl:
        ExitCode -2068578301 (0x84B40003), kein Bootstrap-Log vorhanden.

    Aus einem realen install.log diagnostiziert (noch nicht durch einen frischen Testlauf
    bestaetigt): Das "Direct Package" entpackt sich beim Start selbst in einen Unterordner
    relativ zu seinem eigenen Pfad bzw. dem CWD des startenden Prozesses. Vorher (ohne den
    WorkingDirectory-Fix in Common.ps1) landete das in einem sehr tiefen Pfad unterhalb von
    $INSTDIR\scripts -- vermutlich WEIT ueber MAX_PATH, was Windows Installer/SQL-Setup ohne
    aussagekraeftige Fehlermeldung abbrechen laesst.

    Zwei Gegenmassnahmen sind hier bereits eingebaut, aber ebenfalls noch nicht auf echter
    Hardware verifiziert:
      1. Invoke-ExternalTool (Common.ps1) setzt WorkingDirectory jetzt explizit auf den
         Ordner der .exe.
      2. Zusaetzlich wird dem Direct Package hier per /X:<kurzer Pfad> ein kurzes,
         garantiert flaches Extraktionsverzeichnis vorgegeben, statt sich auf das implizite
         Verhalten des Packages zu verlassen.

    Naechster Schritt laut Statusbericht: frisches install.log von einer echten
    Testmaschine mit Admin-Rechten holen und pruefen, ob die geloggte Kommandozeile /
    das Arbeitsverzeichnis jetzt stimmen und ob der ExitCode verschwindet.
#>

param(
    [string]$InstanceName = 'OPTIXXL',
    [string]$SaPassword,
    [ValidateSet('SQL', 'Windows')][string]$SecurityMode = 'SQL'
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step1-InstallSqlServer'
Initialize-Log

function Test-SqlInstanceInstalled {
    param([string]$InstanceName)
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    if (-not (Test-Path -LiteralPath $regPath)) { return $false }
    $null -ne (Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue).$InstanceName
}

try {
    if (Test-StepCompleted -StepName $stepName -and (Test-SqlInstanceInstalled -InstanceName $InstanceName)) {
        Write-Log "$stepName: SQL-Instanz '$InstanceName' existiert bereits, ueberspringe."
        exit 0
    }

    if (Test-SqlInstanceInstalled -InstanceName $InstanceName) {
        Write-Log "$stepName: SQL-Instanz '$InstanceName' bereits vorhanden (Marker fehlte noch), setze Marker nach."
        Set-StepCompleted -StepName $stepName
        exit 0
    }

    if (-not $SaPassword) {
        throw "Parameter -SaPassword ist erforderlich (wird vom Installer aus der UI/Silent-Antwortdatei uebergeben)."
    }

    $packageExe = Join-Path $PSScriptRoot 'SQLEXPR_x64_DEU.exe'
    if (-not (Test-Path -LiteralPath $packageExe)) {
        throw "Direct Package nicht gefunden: $packageExe"
    }

    Remove-MarkOfTheWeb -Path $packageExe

    # Schritt A: Nur entpacken, in ein kurzes, flaches Verzeichnis (Workaround fuer den
    # noch unverifizierten Bug mit sehr tiefen Extraktionspfaden).
    $extractPath = Join-Path $env:SystemDrive 'optixxl-sqlsrc'
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

    Invoke-ExternalTool -FilePath $packageExe -ArgumentList @(
        '/X:' + $extractPath,
        '/Q'
    )

    $setupExe = Join-Path $extractPath 'setup.exe'
    if (-not (Test-Path -LiteralPath $setupExe)) {
        throw "setup.exe nach Extraktion nicht gefunden unter $extractPath"
    }

    # Schritt B: eigentliche unbeaufsichtigte Installation.
    Invoke-ExternalTool -FilePath $setupExe -ArgumentList @(
        '/ACTION=Install'
        '/QUIET'
        '/IACCEPTSQLSERVERLICENSETERMS'
        '/FEATURES=SQLENGINE'
        "/INSTANCENAME=$InstanceName"
        '/SECURITYMODE=SQL'
        "/SAPWD=$SaPassword"
        '/SQLSYSADMINACCOUNTS=BUILTIN\Administrators'
        '/TCPENABLED=1'
        '/NPENABLED=0'
    )

    if (-not (Test-SqlInstanceInstalled -InstanceName $InstanceName)) {
        throw "setup.exe meldete Erfolg, aber Instanz '$InstanceName' ist nicht in der Registry registriert."
    }

    Set-StepCompleted -StepName $stepName
    Write-Log "$stepName: SQL Server 2025 Express Instanz '$InstanceName' erfolgreich installiert."
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR

    $bootstrapLogDir = "${env:ProgramFiles}\Microsoft SQL Server\160\Setup Bootstrap\Log"
    if (Test-Path -LiteralPath $bootstrapLogDir) {
        Write-Log "Bootstrap-Log-Verzeichnis vorhanden: $bootstrapLogDir (Inhalt manuell pruefen)."
    }
    else {
        Write-Log "Kein Bootstrap-Log-Verzeichnis unter '$bootstrapLogDir' gefunden -- deckt sich mit dem bekannten, noch ungeklaerten ExitCode -2068578301." -Level WARN
    }

    exit 1
}

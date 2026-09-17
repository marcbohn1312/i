#Requires -Version 5.1
<#
    Step5-CreateShare.ps1

    Legt den lokalen Benutzer "OptixxlFreigabe" sowie die gleichnamige SMB-Freigabe an
    und beschraenkt den Zugriff auf diesen Benutzer.

    Geloester Bug: Das Freigabe-Passwort enthaelt ein Euro-Zeichen ("Fr€igegeben"). Wird
    das Passwort im .nsi-Skript per $€-Escape geschrieben, kommt bei der Uebergabe an
    dieses Skript (ueber die Kommandozeile, quer durch NSIS -> Sysnative-PowerShell ->
    ConvertTo-SecureString) ein falsches Byte an, und New-LocalUser schlaegt mit einer
    Policy-Fehlermeldung fehl, die nichts mit dem eigentlichen Encoding-Problem zu tun hat.
    Fix (im .nsi-Skript): Datei mit UTF-8-BOM speichern und das Euro-Zeichen als echte
    UTF-8-Byte-Sequenz im Quelltext belassen statt es zu escapen. Dieses Skript hier
    erwartet entsprechend eine bereits korrekt decodierte PowerShell-[string].
#>

param(
    [Parameter(Mandatory)][string]$SharePassword,
    [string]$ShareLocalPath,
    [string]$ShareName = 'OptixxlFreigabe',
    [string]$LocalUserName = 'OptixxlFreigabe'
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step5-CreateShare'
Initialize-Log

try {
    if (-not $ShareLocalPath) {
        $ShareLocalPath = Join-Path $env:ProgramData 'optixxl\Freigabe'
    }
    New-Item -ItemType Directory -Path $ShareLocalPath -Force | Out-Null

    $user = Get-LocalUser -Name $LocalUserName -ErrorAction SilentlyContinue
    if (-not $user) {
        $securePassword = ConvertTo-SecureString -String $SharePassword -AsPlainText -Force
        New-LocalUser -Name $LocalUserName -Password $securePassword `
            -FullName 'optixxl Freigabe-Konto' -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
        Write-Log "$stepName: Lokaler Benutzer '$LocalUserName' angelegt."
    }
    else {
        Write-Log "$stepName: Lokaler Benutzer '$LocalUserName' existiert bereits, Passwort wird nicht veraendert."
    }

    $share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if (-not $share) {
        New-SmbShare -Name $ShareName -Path $ShareLocalPath -FullAccess $LocalUserName | Out-Null
        Write-Log "$stepName: Freigabe '$ShareName' auf '$ShareLocalPath' angelegt (Vollzugriff nur fuer '$LocalUserName')."
    }
    else {
        Write-Log "$stepName: Freigabe '$ShareName' existiert bereits, ueberspringe."
    }

    Set-StepCompleted -StepName $stepName
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

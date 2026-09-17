#Requires -Version 5.1
<#
    Common.ps1

    Gemeinsame Hilfsfunktionen fuer alle Step*.ps1-Skripte des optixxl-Installations-
    und -Deinstallationsassistenten. Wird von jedem Step-Skript per Dot-Sourcing
    eingebunden:

        . "$PSScriptRoot\Common.ps1"
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Der NSIS-Installer setzt vor jedem RunStep-Aufruf die Umgebungsvariable
# OPTIXXL_INSTALL_LOG auf einen festen Pfad (z. B. "$INSTDIR\install.log"), damit alle
# Schritte in dieselbe Datei schreiben. Ist die Variable nicht gesetzt (z. B. beim
# manuellen Testen eines einzelnen Step-Skripts), wird auf ProgramData ausgewichen.

if ($env:OPTIXXL_INSTALL_LOG) {
    $script:LogPath = $env:OPTIXXL_INSTALL_LOG
}
else {
    $script:LogPath = Join-Path $env:ProgramData 'optixxl\install.log'
}

function Initialize-Log {
    param([string]$Path = $script:LogPath)

    $script:LogPath = $Path
    $logDir = Split-Path -Path $Path -Parent
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO'
    )

    Initialize-Log -Path $script:LogPath
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
}

# ---------------------------------------------------------------------------
# Schritt-Idempotenz
# ---------------------------------------------------------------------------
# Jeder Schritt hinterlaesst nach erfolgreichem Durchlauf einen Marker unter
# $env:ProgramData\optixxl\steps\<Name>.done. Der Marker ist nur ein schneller
# Vorab-Check -- die eigentliche Idempotenz-Pruefung macht jedes Step*.ps1 zusaetzlich
# gegen das reale System (SQL-Instanz, Datenbank, Freigabe, Dienst, ...), bevor es sich
# tatsaechlich selbst ueberspringt.

function Test-StepCompleted {
    param([Parameter(Mandatory)][string]$StepName)
    $marker = Join-Path $env:ProgramData "optixxl\steps\$StepName.done"
    Test-Path -LiteralPath $marker
}

function Set-StepCompleted {
    param([Parameter(Mandatory)][string]$StepName)
    $markerDir = Join-Path $env:ProgramData 'optixxl\steps'
    if (-not (Test-Path -LiteralPath $markerDir)) {
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $markerDir "$StepName.done") -Value (Get-Date -Format 'o') -Encoding UTF8
}

# ---------------------------------------------------------------------------
# WOW64 / Sysnative
# ---------------------------------------------------------------------------
# Geloester Bug: Der Installer ist ein 32-Bit-NSIS-Prozess. Startet er darin ganz normal
# "powershell.exe", greift die WOW64-Dateisystem-Umleitung, und es laeuft in Wahrheit die
# 32-Bit-PowerShell aus SysWOW64 -- mit falscher $env:ProgramFiles-Sicht und falscher
# Registry-Umleitung (HKLM\SOFTWARE\WOW6432Node statt HKLM\SOFTWARE). Fix: expliziter
# Aufruf ueber den Sysnative-Alias, der die Umleitung umgeht und garantiert die
# 64-Bit-PowerShell startet. Wird von den .nsi-Skripten beim RunStep-Aufruf verwendet;
# hier zusaetzlich verfuegbar, falls ein Step selbst weitere PowerShell-Prozesse startet.

function Get-Real64BitPowerShellPath {
    $sysnative = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if ([Environment]::Is64BitOperatingSystem -and (Test-Path -LiteralPath $sysnative)) {
        return $sysnative
    }
    return Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

# ---------------------------------------------------------------------------
# Kommandozeilen-Quoting
# ---------------------------------------------------------------------------
# Geloester Bug: Unter Windows PowerShell 5.1 / .NET 4.8 bleibt
# [System.Diagnostics.ProcessStartInfo]::ArgumentList $null (empirisch verifiziert, in der
# .NET-4.8-Doku nicht dokumentiert). Wer trotzdem $psi.ArgumentList.Add(...) aufruft, bekommt
# keine Exception, sondern eine leere Kommandozeile -- der externe Prozess startet ohne jedes
# Argument. Fix: Argumente werden manuell zu einem einzigen, korrekt gequoteten String
# zusammengesetzt (Regeln von CommandLineToArgvW) und in $psi.Arguments geschrieben.

function ConvertTo-CommandLineArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Argument)

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    $backslashCount = 0

    for ($i = 0; $i -lt $Argument.Length; $i++) {
        $ch = $Argument[$i]
        if ($ch -eq '\') {
            $backslashCount++
            continue
        }
        if ($ch -eq '"') {
            [void]$sb.Append('\' * ($backslashCount * 2 + 1))
            [void]$sb.Append('"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$sb.Append('\' * $backslashCount)
            $backslashCount = 0
        }
        [void]$sb.Append($ch)
    }
    if ($backslashCount -gt 0) {
        [void]$sb.Append('\' * ($backslashCount * 2))
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-CommandLine {
    param([string[]]$ArgumentList)
    if (-not $ArgumentList -or $ArgumentList.Count -eq 0) { return '' }
    ($ArgumentList | ForEach-Object { ConvertTo-CommandLineArgument $_ }) -join ' '
}

# ---------------------------------------------------------------------------
# Invoke-ExternalTool
# ---------------------------------------------------------------------------

function Invoke-ExternalTool {
    <#
        .SYNOPSIS
        Startet ein externes Programm (z. B. SQLEXPR_x64_DEU.exe, sqlcmd.exe) robust und
        protokolliert Kommandozeile, Arbeitsverzeichnis und ExitCode.

        .PARAMETER WorkingDirectory
        Optional. Default: der Ordner, in dem FilePath liegt. Geloester Bug: vorher wurde
        WorkingDirectory nicht gesetzt, wodurch selbstentpackende Installer (z. B. das SQL-
        Server-"Direct Package") relativ zum aktuellen PowerShell-CWD entpackten -- das war
        teils ein sehr tiefer Pfad unterhalb von $INSTDIR\scripts. Falls das ermittelte
        Arbeitsverzeichnis nicht existiert/nicht beschreibbar ist, wird auf $env:TEMP
        ausgewichen.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [int[]]$AllowedExitCodes = @(0)
    )

    if (-not $WorkingDirectory) {
        $WorkingDirectory = Split-Path -Path $FilePath -Parent
    }
    if (-not $WorkingDirectory -or -not (Test-Path -LiteralPath $WorkingDirectory)) {
        Write-Log "Arbeitsverzeichnis '$WorkingDirectory' nicht verwendbar, weiche auf `$env:TEMP aus." -Level WARN
        $WorkingDirectory = $env:TEMP
    }

    $commandLine = ConvertTo-CommandLine -ArgumentList $ArgumentList

    # Protokolliert die tatsaechlich an den Prozess uebergebene, fertig gequotete
    # Kommandozeile (nicht nur die rohe, ungequotete Parameterliste) -- damit ein
    # eventueller Quoting-Fehler im naechsten Log sichtbar wird.
    Write-Log "Starte: `"$FilePath`" $commandLine  (WorkingDirectory: $WorkingDirectory)"

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.Arguments = $commandLine
        $psi.WorkingDirectory = $WorkingDirectory
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        [void]$proc.Start()

        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($stdout) { Write-Log "STDOUT: $stdout" -Level DEBUG }
        if ($stderr) { Write-Log "STDERR: $stderr" -Level DEBUG }

        $exitCode = $proc.ExitCode
    }
    catch {
        Write-Log "[Diagnostics.Process] fehlgeschlagen ($($_.Exception.Message)), Start-Process-Fallback." -Level WARN
        $proc = Start-Process -FilePath $FilePath -ArgumentList $commandLine `
            -WorkingDirectory $WorkingDirectory -Wait -PassThru -NoNewWindow
        $exitCode = $proc.ExitCode
    }

    Write-Log ('Beendet mit ExitCode {0} (0x{0:X8}) : {1}' -f $exitCode, $FilePath)

    if ($exitCode -notin $AllowedExitCodes) {
        throw "Externes Tool '$FilePath' beendete sich mit unerwartetem ExitCode $exitCode (0x$('{0:X8}' -f $exitCode))."
    }

    return $exitCode
}

# ---------------------------------------------------------------------------
# Mark-of-the-Web
# ---------------------------------------------------------------------------
# Geloester Bug: Heruntergeladene bzw. entpackte EXEs tragen unter Umstaenden den
# Zone.Identifier-ADS ("Mark of the Web"). SmartScreen blockiert den unbeaufsichtigten
# Start dann ohne brauchbare Fehlermeldung im Log. Fix: Unblock-File vor jedem
# Invoke-ExternalTool auf Dateien, die nicht garantiert aus dem eigenen, vom Installer
# signierten Paket stammen.

function Remove-MarkOfTheWeb {
    param([Parameter(Mandatory)][string]$Path)
    try {
        Unblock-File -LiteralPath $Path -ErrorAction Stop
        Write-Log "Mark-of-the-Web entfernt: $Path"
    }
    catch {
        Write-Log "Unblock-File fehlgeschlagen fuer '$Path': $($_.Exception.Message)" -Level WARN
    }
}

# ---------------------------------------------------------------------------
# OptixxlFreigabe
# ---------------------------------------------------------------------------
# Schreibweise historisch uneinheitlich (teils "optixxlFreigabe"). Ab jetzt ausschliesslich
# "OptixxlFreigabe" -- fuer Freigabenamen, lokalen lokalen Benutzernamen und alle Log-/UI-Texte.

$script:OptixxlFreigabeName = 'OptixxlFreigabe'

function Get-OptixxlFreigabeName {
    $script:OptixxlFreigabeName
}

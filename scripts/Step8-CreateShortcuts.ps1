#Requires -Version 5.1
<#
    Step8-CreateShortcuts.ps1
    Legt Start-Menue- und Desktop-Verknuepfungen fuer optixxl an.
#>

param(
    [Parameter(Mandatory)][string]$TargetExe,
    [switch]$CreateDesktopShortcut
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step8-CreateShortcuts'
Initialize-Log

function New-AppShortcut {
    param([string]$Path, [string]$TargetExe)
    if (Test-Path -LiteralPath $Path) { return $false }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $TargetExe
    $shortcut.WorkingDirectory = Split-Path -Path $TargetExe -Parent
    $shortcut.Save()
    return $true
}

try {
    if (-not (Test-Path -LiteralPath $TargetExe)) {
        throw "Ziel-Executable nicht gefunden: $TargetExe"
    }

    $startMenuDir = Join-Path ([Environment]::GetFolderPath('CommonStartMenu')) 'Programs\optixxl'
    New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
    $startMenuLink = Join-Path $startMenuDir 'optixxl.lnk'

    if (New-AppShortcut -Path $startMenuLink -TargetExe $TargetExe) {
        Write-Log "$stepName: Startmenue-Verknuepfung angelegt: $startMenuLink"
    }
    else {
        Write-Log "$stepName: Startmenue-Verknuepfung existiert bereits, ueberspringe."
    }

    if ($CreateDesktopShortcut) {
        $desktopLink = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'optixxl.lnk'
        if (New-AppShortcut -Path $desktopLink -TargetExe $TargetExe) {
            Write-Log "$stepName: Desktop-Verknuepfung angelegt: $desktopLink"
        }
        else {
            Write-Log "$stepName: Desktop-Verknuepfung existiert bereits, ueberspringe."
        }
    }

    Set-StepCompleted -StepName $stepName
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

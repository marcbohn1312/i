#Requires -Version 5.1
<#
    Step9-SetPermissions.ps1
    Setzt NTFS-Berechtigungen auf die Daten-/Log-Ordner fuer den Dienstbenutzer und
    das OptixxlFreigabe-Konto.
#>

param(
    [Parameter(Mandatory)][string]$InstallDir,
    [string]$LocalUserName = 'OptixxlFreigabe'
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step9-SetPermissions'
Initialize-Log

try {
    $dataDir = Join-Path $InstallDir 'data'
    $logDir = Join-Path $InstallDir 'logs'
    New-Item -ItemType Directory -Path $dataDir, $logDir -Force | Out-Null

    foreach ($dir in @($dataDir, $logDir)) {
        $acl = Get-Acl -Path $dir
        $identity = "$env:COMPUTERNAME\$LocalUserName"
        $alreadyGranted = $acl.Access | Where-Object {
            $_.IdentityReference.Value -eq $identity -and $_.FileSystemRights -match 'Modify'
        }

        if (-not $alreadyGranted) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identity, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
            Set-Acl -Path $dir -AclObject $acl
            Write-Log "$stepName: Modify-Recht fuer '$identity' auf '$dir' gesetzt."
        }
        else {
            Write-Log "$stepName: '$identity' hat bereits Modify-Recht auf '$dir', ueberspringe."
        }
    }

    Set-StepCompleted -StepName $stepName
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

#Requires -Version 5.1
<#
    Step6-ConfigureFirewall.ps1
    Oeffnet die fuer SMB (OptixxlFreigabe) und die optixxl-Anwendung benoetigten Ports.
#>

param(
    [int]$SmbPort = 445,
    [int]$AppPort = 8443
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step6-ConfigureFirewall'
Initialize-Log

function Set-FirewallRuleIfMissing {
    param([string]$DisplayName, [int]$Port)
    $rule = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName $DisplayName -Direction Inbound -Protocol TCP `
            -LocalPort $Port -Action Allow | Out-Null
        Write-Log "$script:stepName: Firewall-Regel '$DisplayName' angelegt."
    }
    else {
        Write-Log "$script:stepName: Firewall-Regel '$DisplayName' existiert bereits, ueberspringe."
    }
}

try {
    Set-FirewallRuleIfMissing -DisplayName 'optixxl SMB (OptixxlFreigabe)' -Port $SmbPort
    Set-FirewallRuleIfMissing -DisplayName 'optixxl Anwendungsdienst' -Port $AppPort

    Set-StepCompleted -StepName $stepName
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

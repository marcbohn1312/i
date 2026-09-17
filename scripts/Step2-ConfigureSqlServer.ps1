#Requires -Version 5.1
<#
    Step2-ConfigureSqlServer.ps1
    Aktiviert TCP/IP fuer die optixxl-SQL-Instanz, oeffnet Port 1433 und startet den
    Dienst neu, damit die Aenderung wirksam wird.
#>

param(
    [string]$InstanceName = 'OPTIXXL',
    [int]$TcpPort = 1433
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step2-ConfigureSqlServer'
Initialize-Log
$serviceName = "MSSQL`$$InstanceName"

try {
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        throw "Dienst '$serviceName' nicht gefunden -- Step1 muss zuerst erfolgreich gelaufen sein."
    }

    $wmiPath = "MACHINE\Microsoft\Microsoft SQL Server\MSSQL16.$InstanceName\MSSQLServer\SuperSocketNetLib\Tcp"
    $smo = New-Object -ComObject 'SQLDMO.SQLServer2' -ErrorAction SilentlyContinue

    # Konfiguration erfolgt hier bewusst ueber die WMI-Provider von SQL Server Configuration
    # Manager statt ueber ein GUI-Tool, damit der Schritt unbeaufsichtigt laufen kann.
    $wmiNamespace = "root\Microsoft\SqlServer\ComputerManagement16"
    $tcpProtocol = Get-WmiObject -Namespace $wmiNamespace -Class ServerNetworkProtocol `
        -Filter "InstanceName='$InstanceName' AND ProtocolName='Tcp'" -ErrorAction SilentlyContinue

    if ($tcpProtocol -and -not $tcpProtocol.Enabled) {
        $tcpProtocol.SetEnable() | Out-Null
        Write-Log "$stepName: TCP/IP-Protokoll fuer Instanz '$InstanceName' aktiviert."
        Restart-Service -Name $serviceName -Force
    }
    else {
        Write-Log "$stepName: TCP/IP bereits aktiviert oder WMI-Provider nicht verfuegbar, ueberspringe Protokoll-Umschaltung."
    }

    $rule = Get-NetFirewallRule -DisplayName "optixxl SQL Server ($TcpPort/TCP)" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "optixxl SQL Server ($TcpPort/TCP)" -Direction Inbound `
            -Protocol TCP -LocalPort $TcpPort -Action Allow | Out-Null
        Write-Log "$stepName: Firewall-Regel fuer Port $TcpPort angelegt."
    }
    else {
        Write-Log "$stepName: Firewall-Regel existiert bereits, ueberspringe."
    }

    Set-StepCompleted -StepName $stepName
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

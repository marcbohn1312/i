#Requires -Version 5.1
<#
    Step3-CreateDatabase.ps1
    Legt die optixxl-Anwendungsdatenbank und den zugehoerigen SQL-Login per sqlcmd an.
#>

param(
    [string]$InstanceName = 'OPTIXXL',
    [string]$DatabaseName = 'optixxl',
    [string]$SaPassword,
    [string]$AppLoginPassword
)

. "$PSScriptRoot\Common.ps1"

$stepName = 'Step3-CreateDatabase'
Initialize-Log

function Test-DatabaseExists {
    param([string]$ServerInstance, [string]$SaPassword, [string]$DatabaseName)
    $sqlcmd = Get-Command 'sqlcmd.exe' -ErrorAction SilentlyContinue
    if (-not $sqlcmd) { return $false }
    $result = & $sqlcmd.Path -S $ServerInstance -U sa -P $SaPassword -h -1 -W -Q `
        "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = '$DatabaseName';" 2>$null
    return ($LASTEXITCODE -eq 0 -and ($result -join '').Trim() -eq '1')
}

try {
    if (-not $SaPassword -or -not $AppLoginPassword) {
        throw "Parameter -SaPassword und -AppLoginPassword sind erforderlich."
    }

    $serverInstance = "localhost\$InstanceName"

    if (Test-DatabaseExists -ServerInstance $serverInstance -SaPassword $SaPassword -DatabaseName $DatabaseName) {
        Write-Log "$stepName: Datenbank '$DatabaseName' existiert bereits, ueberspringe."
        Set-StepCompleted -StepName $stepName
        exit 0
    }

    $sqlScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$DatabaseName')
    CREATE DATABASE [$DatabaseName];
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'optixxl_app')
    CREATE LOGIN [optixxl_app] WITH PASSWORD = N'$AppLoginPassword', CHECK_POLICY = ON;
GO
USE [$DatabaseName];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'optixxl_app')
    CREATE USER [optixxl_app] FOR LOGIN [optixxl_app];
ALTER ROLE db_owner ADD MEMBER [optixxl_app];
GO
"@

    $scriptPath = Join-Path $env:TEMP 'optixxl-create-database.sql'
    Set-Content -LiteralPath $scriptPath -Value $sqlScript -Encoding UTF8

    Invoke-ExternalTool -FilePath (Get-Command 'sqlcmd.exe').Path -ArgumentList @(
        '-S', $serverInstance,
        '-U', 'sa',
        '-P', $SaPassword,
        '-b',
        '-i', $scriptPath
    )

    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue

    if (-not (Test-DatabaseExists -ServerInstance $serverInstance -SaPassword $SaPassword -DatabaseName $DatabaseName)) {
        throw "sqlcmd meldete Erfolg, aber Datenbank '$DatabaseName' ist danach nicht auffindbar."
    }

    Set-StepCompleted -StepName $stepName
    Write-Log "$stepName: Datenbank '$DatabaseName' und Login 'optixxl_app' angelegt."
    exit 0
}
catch {
    Write-Log "$stepName fehlgeschlagen: $($_.Exception.Message)" -Level ERROR
    exit 1
}

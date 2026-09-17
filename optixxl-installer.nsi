; optixxl-installer.nsi
;
; Baut optixxl-Installationsassistent.exe -- reine Installation (~764 MB, SQL-Server-
; "Direct Package" fest eingebettet). Die Deinstallation ist bewusst ein separates Projekt
; (optixxl-deinstallationsassistent.nsi), das die hier deployten scripts\*.ps1 wiederverwendet.
;
; WICHTIG: Diese Datei muss als UTF-8 MIT BOM gespeichert werden (siehe "Unicode true" unten
; und die Doku zu ConvertTo-CommandLineArgument in scripts\Common.ps1). Grund: Das
; Freigabe-Passwort enthaelt ein Euro-Zeichen ("Fr€igegeben"). Fuer NSIS 3.x reicht dafuer die
; UTF-8-BOM am Dateianfang, damit der Compiler die Datei korrekt als UTF-8 statt als
; ANSI/Codepage-1252 einliest; das Euro-Zeichen steht unten als echte UTF-8-Byte-Sequenz im
; Quelltext, NICHT als $€-Escape (letzteres fuehrte historisch zu einem falschen Byte,
; siehe README.md, Bekannte Einschraenkungen).

Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

; ---------------------------------------------------------------------------
; Metadaten
; ---------------------------------------------------------------------------

!define PRODUCT_NAME "optixxl"
!define PRODUCT_PUBLISHER "optixxl"
!define INSTALLER_NAME "optixxl-Installationsassistent.exe"

; Schreibweise historisch uneinheitlich (war stellenweise "optixxlFreigabe") -- ab jetzt
; ausschliesslich "OptixxlFreigabe", siehe README.md Punkt zur Vereinheitlichung.
!define OPTIXXL_SHARE_NAME "OptixxlFreigabe"

; Echtes UTF-8-Euro-Zeichen im Quelltext (siehe Hinweis oben zur Datei-Kodierung).
!define OPTIXXL_SHARE_PASSWORD "Fr€igegeben"

Name "${PRODUCT_NAME}"
OutFile "${INSTALLER_NAME}"
InstallDir "$PROGRAMFILES64\optixxl-Installationsassistent"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

; nsDialogs-Variablen fuer Eingaben aus einer eigenen Passwort-Seite (Custom Page, hier aus
; Platzgruenden nicht ausformuliert -- muss vor der Install-Section per nsDialogs::Create
; gesetzt werden, bevor SqlSaPassword/AppLoginPassword verwendet werden).
Var SqlSaPassword
Var AppLoginPassword

; ---------------------------------------------------------------------------
; MUI2-Seiten
; ---------------------------------------------------------------------------

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "German"

; ---------------------------------------------------------------------------
; RunStep-Makro
; ---------------------------------------------------------------------------
; Ruft ein Step*.ps1-Skript unter $INSTDIR\scripts sequenziell auf. Jeder Schritt prueft
; selbst per Test-StepCompleted / eigener Systempruefung, ob sein Ziel schon existiert, und
; ueberspringt sich dann -- RunStep selbst bricht die Installation bei jedem ExitCode != 0
; ab, unabhaengig davon, ob uebersprungen wurde oder nicht (ein Skip endet immer mit exit 0).
;
; Geloester Bug (WOW64): Der Installer ist ein 32-Bit-Prozess. "powershell.exe" ohne
; Sysnative-Pfad wuerde hier die 32-Bit-PowerShell aus SysWOW64 starten (falsche
; $env:ProgramFiles-Sicht, falsche Registry-Umleitung). Deshalb expliziter Aufruf ueber
; $WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe.

!macro RunStep StepFileName StepArgs
    DetailPrint "Fuehre ${StepFileName} aus..."
    nsExec::ExecToLog '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\scripts\${StepFileName}" ${StepArgs}'
    Pop $0
    ${If} $0 != 0
        MessageBox MB_OK|MB_ICONSTOP "${StepFileName} ist mit Fehlercode $0 fehlgeschlagen. Details siehe $INSTDIR\install.log."
        Abort "${StepFileName} fehlgeschlagen (ExitCode $0)."
    ${EndIf}
!macroend

; ---------------------------------------------------------------------------
; Install-Sektion
; ---------------------------------------------------------------------------

Section "optixxl installieren" SEC_MAIN
    SetOutPath "$INSTDIR"

    ; install.log-Pfad fuer alle Step-Skripte festlegen (siehe Common.ps1: OPTIXXL_INSTALL_LOG).
    System::Call 'kernel32::SetEnvironmentVariable(t "OPTIXXL_INSTALL_LOG", t "$INSTDIR\install.log")'

    SetOutPath "$INSTDIR\scripts"
    File "scripts\Common.ps1"
    File "scripts\Step1-InstallSqlServer.ps1"
    File "scripts\Step2-ConfigureSqlServer.ps1"
    File "scripts\Step3-CreateDatabase.ps1"
    File "scripts\Step4-DeployApplicationFiles.ps1"
    File "scripts\Step5-CreateShare.ps1"
    File "scripts\Step6-ConfigureFirewall.ps1"
    File "scripts\Step7-RegisterService.ps1"
    File "scripts\Step8-CreateShortcuts.ps1"
    File "scripts\Step9-SetPermissions.ps1"
    File "scripts\Step10-FinalCheck.ps1"
    File "scripts\Uninstall.ps1"

    ; SQL-Server-2025-Express-"Direct Package" (SQLEXPR_x64_DEU.exe, ca. 754 MB). Liegt nicht
    ; im Git-Repository (siehe .gitignore) -- muss beim Bauen der EXE neben dieser .nsi-Datei
    ; unter payload\SQLEXPR_x64_DEU.exe bereitstehen.
    File "payload\SQLEXPR_x64_DEU.exe"

    ; Anwendungs-Payload (die eigentliche optixxl-Anwendung), ebenfalls nicht im Repo.
    SetOutPath "$INSTDIR\payload\app"
    File /r "payload\app\*.*"

    !insertmacro RunStep "Step1-InstallSqlServer.ps1" '-SaPassword "$SqlSaPassword"'
    !insertmacro RunStep "Step2-ConfigureSqlServer.ps1" ''
    !insertmacro RunStep "Step3-CreateDatabase.ps1" '-SaPassword "$SqlSaPassword" -AppLoginPassword "$AppLoginPassword"'
    !insertmacro RunStep "Step4-DeployApplicationFiles.ps1" '-SourceDir "$INSTDIR\payload\app" -InstallDir "$INSTDIR" -AppVersion "1.0.0"'
    !insertmacro RunStep "Step5-CreateShare.ps1" '-SharePassword "${OPTIXXL_SHARE_PASSWORD}"'
    !insertmacro RunStep "Step6-ConfigureFirewall.ps1" ''
    !insertmacro RunStep "Step7-RegisterService.ps1" '-BinaryPath "$INSTDIR\app\optixxl-service.exe"'
    !insertmacro RunStep "Step8-CreateShortcuts.ps1" '-TargetExe "$INSTDIR\app\optixxl.exe" -CreateDesktopShortcut'
    !insertmacro RunStep "Step9-SetPermissions.ps1" '-InstallDir "$INSTDIR"'
    !insertmacro RunStep "Step10-FinalCheck.ps1" '-InstallDir "$INSTDIR"'

    ; Kein WriteUninstaller hier: Die Deinstallation ist bewusst ein eigenstaendiges
    ; EXE-Projekt (optixxl-deinstallationsassistent.nsi), das dieselben scripts\*.ps1
    ; wiederverwendet. "Programs and Features" verweist deshalb auf jene EXE.
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\optixxl" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\optixxl" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\optixxl" "Publisher" "${PRODUCT_PUBLISHER}"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\optixxl" "UninstallString" "$INSTDIR\optixxl-Deinstallationsassistent.exe"
SectionEnd

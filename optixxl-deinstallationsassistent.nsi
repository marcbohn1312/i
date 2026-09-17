; optixxl-deinstallationsassistent.nsi
;
; Baut optixxl-Deinstallationsassistent.exe -- reine Deinstallation (~72 KB). Nutzt die vom
; Installer bereits deployten Skripte unter $INSTDIR\scripts (insbesondere Uninstall.ps1 und
; Common.ps1) und bringt selbst keine grossen Payloads mit.

Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"

!define PRODUCT_NAME "optixxl"
!define UNINSTALLER_NAME "optixxl-Deinstallationsassistent.exe"

Name "${PRODUCT_NAME} deinstallieren"
OutFile "${UNINSTALLER_NAME}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "German"

Var InstallDirFromRegistry

; ---------------------------------------------------------------------------
; .onInit -- Installationsverzeichnis aus der Registry lesen, die der Installer geschrieben
; hat. Ohne dieses Verzeichnis gibt es nichts zu deinstallieren, da hier bewusst keine
; eigenen scripts\*.ps1 mitgeliefert werden.
; ---------------------------------------------------------------------------

Function .onInit
    ReadRegStr $InstallDirFromRegistry HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\optixxl" "InstallLocation"
    ${If} $InstallDirFromRegistry == ""
        MessageBox MB_OK|MB_ICONSTOP "Keine optixxl-Installation gefunden (Registry-Eintrag fehlt). Deinstallation wird abgebrochen."
        Abort
    ${EndIf}
    ${IfNot} ${FileExists} "$InstallDirFromRegistry\scripts\Uninstall.ps1"
        MessageBox MB_OK|MB_ICONSTOP "$InstallDirFromRegistry\scripts\Uninstall.ps1 nicht gefunden. Die Installation scheint unvollstaendig oder beschaedigt zu sein."
        Abort
    ${EndIf}
FunctionEnd

; ---------------------------------------------------------------------------
; Uninstall-Sektion
; ---------------------------------------------------------------------------
; Gleicher WOW64/Sysnative-Fix wie im Installer: expliziter Aufruf ueber
; $WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe, damit auch aus dem 32-Bit-
; NSIS-Prozess heraus garantiert die 64-Bit-PowerShell startet.

Section "optixxl deinstallieren"
    System::Call 'kernel32::SetEnvironmentVariable(t "OPTIXXL_INSTALL_LOG", t "$InstallDirFromRegistry\install.log")'

    DetailPrint "Fuehre Uninstall.ps1 aus..."
    nsExec::ExecToLog '"$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$InstallDirFromRegistry\scripts\Uninstall.ps1" -InstallDir "$InstallDirFromRegistry"'
    Pop $0
    ${If} $0 != 0
        MessageBox MB_OK|MB_ICONEXCLAMATION "Uninstall.ps1 ist mit Fehlercode $0 beendet. Details siehe $InstallDirFromRegistry\install.log. Verbleibende Dateien werden trotzdem entfernt."
    ${EndIf}

    DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\optixxl"
    RMDir /r "$InstallDirFromRegistry"
SectionEnd

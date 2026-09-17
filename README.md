# optixxl Installationsassistent / Deinstallationsassistent

> **Hinweis zu diesem Repository-Stand:** Diese Dateien sind aus einem Chat-Statusbericht
> rekonstruiert, nicht aus dem Original-Quellcode kopiert. Der tatsaechliche, mit allen
> Fixes versehene Quellcode liegt aktuell nur lokal unter
> `C:\Users\mbohn\Desktop\optixxl Installer\optixxl-installer-quellcode.zip` sowie zweimal
> als gepatchte `Common.ps1` verschickt. Sobald diese Dateien verfuegbar sind, sollten sie
> den Stand hier ersetzen. Die 754-MB-Rohdatei `SQLEXPR_x64_DEU.exe` und die eigentliche
> optixxl-Anwendungs-Payload sind grundsaetzlich nicht Teil dieses Repos (siehe
> `.gitignore`) und muessen beim Bauen lokal unter `payload/` bereitgestellt werden.

## Architektur

Zwei getrennte EXE-Projekte (NSIS 3.10, MUI2, nsDialogs):

- `optixxl-installer.nsi` → `optixxl-Installationsassistent.exe` (reine Installation,
  ~764 MB, SQL-Server-"Direct Package" fest eingebettet)
- `optixxl-deinstallationsassistent.nsi` → `optixxl-Deinstallationsassistent.exe` (reine
  Deinstallation, ~72 KB, nutzt die vom Installer bereits deployten Skripte unter
  `$INSTDIR\scripts`)

Alle Arbeitsschritte sind idempotente PowerShell-Skripte
(`scripts/Step1-InstallSqlServer.ps1` … `scripts/Step10-FinalCheck.ps1` +
`scripts/Common.ps1` mit gemeinsamen Hilfsfunktionen), die vom Installer sequenziell ueber
ein `RunStep`-Makro aufgerufen werden. Jeder Schritt prueft selbst, ob sein Ziel schon
existiert, und ueberspringt sich dann.

## Bekannte Einschraenkungen / Aenderungsprotokoll

1. `ProcessStartInfo.ArgumentList` ist `$null` unter PowerShell 5.1/.NET 4.8 (empirisch
   verifiziert, nicht dokumentiert) → `Invoke-ExternalTool` baut Argumente jetzt manuell
   als gequoteten String (`ConvertTo-CommandLineArgument`, `scripts/Common.ps1`).
2. WOW64-Umleitung: Der 32-Bit-NSIS-Prozess startet sonst 32-Bit-PowerShell (SysWOW64) →
   Registry-/`$env:ProgramFiles`-Probleme. Fix: Start ueber
   `$WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe` (in beiden `.nsi`-Dateien und
   in `Get-Real64BitPowerShellPath`).
3. Mark-of-the-Web/SmartScreen bei heruntergeladenen EXEs → `Unblock-File`
   (`Remove-MarkOfTheWeb` in `scripts/Common.ps1`).
4. Schreibweise "OptixxlFreigabe" vereinheitlicht (war stellenweise "optixxlFreigabe") --
   siehe `Get-OptixxlFreigabeName` sowie `scripts/Step5-CreateShare.ps1`.
5. Euro-Zeichen (€) im Freigabe-Passwort "Fr€igegeben" → UTF-8-BOM in der `.nsi` + echte
   UTF-8-Byte-Sequenz statt `$\u20AC`-Escape (siehe Kommentar am Kopf von
   `optixxl-installer.nsi`).

### Aktuell verfolgter, NOCH NICHT verifizierter Bug

SQL Server 2025 Express Setup schlaegt unbeaufsichtigt fehl
(`ExitCode -2068578301` / `0x84B40003`, kein Bootstrap-Log). Aus einem echten `install.log`
diagnostiziert: Das eingebettete "Direct Package" (`SQLEXPR_x64_DEU.exe`, 754 MB) entpackt
sich selbst nach `...\optixxl-Installationsassistent\scripts\SQLEXPR_x64_DEU\...` (in den
eigenen Skript-Ordner, mit sehr langen/tiefen Pfaden) statt in einen sinnvollen Ordner.

**Bereits umgesetzte Fixes** (in `scripts/Common.ps1`, `Invoke-ExternalTool`, und in
`scripts/Step1-InstallSqlServer.ps1`) — im hier rekonstruierten Quellcode enthalten, aber
**noch nicht auf echter Hardware verifiziert**, da ein Rebuild bislang scheiterte (die
754-MB-Rohdatei war von den bisherigen Rechnern aus nicht erreichbar):

- `$psi.WorkingDirectory` wird jetzt explizit auf den Ordner der jeweiligen `.exe` gesetzt
  (bzw. `-WorkingDirectory` beim `Start-Process`-Fallback), mit `$env:TEMP` als Ersatz.
- `install.log` protokolliert jetzt die tatsaechlich an den Prozess uebergebene, fertig
  gequotete Kommandozeile (vorher nur die rohe, ungequotete Parameterliste).
- Zusaetzlich entpackt `Step1-InstallSqlServer.ps1` das Direct Package jetzt explizit per
  `/X:<kurzer Pfad>` in ein flaches Verzeichnis (`%SystemDrive%\optixxl-sqlsrc`), statt sich
  auf das implizite Entpackverhalten des Packages zu verlassen.

## Blocker

Um die Fixes wirklich zu testen, wird eine Maschine benoetigt, auf der:

- die Installation administrativ ausgefuehrt werden kann, und
- idealerweise die 754-MB-SQL-Rohdatei verfuegbar ist, um die EXE mit den neuesten Fixes
  komplett neu zu bauen (sonst nur manueller `Common.ps1`-Patch moeglich).

## Naechster Schritt

Auf einer echten Testmaschine mit Admin-Rechten:

1. Aktuellen Quellcode entpacken und mit NSIS (`makensis`) neu bauen — oder, falls eine
   aeltere gebaute EXE dort schon liegt, nur `scripts/Common.ps1` manuell in
   `C:\Program Files\optixxl-Installationsassistent\scripts\` ueberschreiben.
2. Installation starten (Admin/UAC bestaetigen).
3. Frisches `install.log` liefern → Analyse der `Starte: "..." ...`-Zeile (zeigt jetzt
   Klartext-Kommandozeile + Arbeitsverzeichnis) klaert, ob der Fix wirkt.

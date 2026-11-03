@echo off
rem Crea un acceso directo en Inicio de Windows que vigila la app de Claude y abre el medidor.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Medidor Claude.lnk'); $s.TargetPath='powershell.exe'; $s.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0vigilar-claude.ps1\"'; $s.WindowStyle=7; $s.IconLocation='%~dp0medidor.ico'; $s.Save()"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0vigilar-claude.ps1"
echo Listo: el medidor se abrira solo cada vez que abras la app de Claude.

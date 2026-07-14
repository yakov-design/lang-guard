@echo off
rem Lang-Guard installer: copies the app locally, starts it, and sets it to run at login.
set DEST=%LOCALAPPDATA%\Lang-Guard
mkdir "%DEST%" 2>nul
copy /Y "%~dp0LangGuard.exe" "%DEST%\LangGuard.exe" >nul
powershell -NoProfile -Command "$ws=New-Object -ComObject WScript.Shell; $l=$ws.CreateShortcut($env:APPDATA+'\Microsoft\Windows\Start Menu\Programs\Startup\Lang-Guard.lnk'); $l.TargetPath=$env:LOCALAPPDATA+'\Lang-Guard\LangGuard.exe'; $l.Description='Lang-Guard HE/EN wrong-layout detector'; $l.Save()"
start "" "%DEST%\LangGuard.exe"
echo.
echo Lang-Guard is installed and running (look for its icon in the system tray).
echo It will start automatically every time Windows starts.
echo.
pause

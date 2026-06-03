@echo off
setlocal

echo ============================================================
echo  Bambu Studio Printer Installer - FirstBuild Makerspace
echo ============================================================
echo.

:: Create a temporary folder to hold downloaded files
set "TEMP_DIR=%TEMP%\BambuddyInstall_%RANDOM%"
mkdir "%TEMP_DIR%" 2>nul

echo Downloading installer from GitHub...
powershell -ExecutionPolicy Bypass -Command ^
  "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/FirstBuild/3D-Printing/main/Install-BambuddyCert.ps1' -OutFile '%TEMP_DIR%\Install-BambuddyCert.ps1' -UseBasicParsing"

if not exist "%TEMP_DIR%\Install-BambuddyCert.ps1" (
    echo.
    echo ERROR: Could not download the installer script.
    echo Please check your internet connection and try again.
    echo.
    pause
    exit /b 1
)

echo Running installer...
echo.
PowerShell.exe -ExecutionPolicy Bypass -File "%TEMP_DIR%\Install-BambuddyCert.ps1" %*

echo.
echo ============================================================
echo  Done! You can close this window.
echo ============================================================
pause

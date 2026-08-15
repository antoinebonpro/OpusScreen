@echo off
REM ---------------------------------------------------------------------------
REM  LumaFlux - compilation
REM
REM  Utilise le compilateur C# livre avec le .NET Framework 4, present sur
REM  toutes les installations de Windows : rien a installer.
REM ---------------------------------------------------------------------------

setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
if not exist "%FW%\csc.exe" set FW=%WINDIR%\Microsoft.NET\Framework\v4.0.30319

if not exist "%FW%\csc.exe" (
    echo Compilateur C# introuvable. Le .NET Framework 4 est-il installe ?
    exit /b 1
)

cd /d "%~dp0"

"%FW%\csc.exe" /nologo /target:winexe /out:LumaFlux.exe /platform:anycpu /optimize+ ^
    /r:"%FW%\System.dll" ^
    /r:"%FW%\System.Drawing.dll" ^
    /r:"%FW%\System.Windows.Forms.dll" ^
    /r:"%FW%\System.Management.dll" ^
    /r:"%FW%\System.Core.dll" ^
    src\*.cs

if errorlevel 1 (
    echo.
    echo *** Echec de la compilation ***
    exit /b 1
)

echo.
echo LumaFlux.exe genere avec succes.
endlocal

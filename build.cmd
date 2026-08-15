@echo off
REM ---------------------------------------------------------------------------
REM  OpusScreen - compilation
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

REM --- icone de l'application : dessinee par code, regeneree si elle manque ---
if not exist "assets\OpusScreen.ico" (
    echo Generation de l'icone...
    "%FW%\csc.exe" /nologo /target:exe /out:"%TEMP%\OpusScreenMakeIcon.exe" ^
        /r:"%FW%\System.Drawing.dll" tools\MakeIcon.cs
    if errorlevel 1 (
        echo *** Echec de la compilation du generateur d'icone ***
        exit /b 1
    )
    "%TEMP%\OpusScreenMakeIcon.exe" "assets\OpusScreen.ico"
    if errorlevel 1 (
        echo *** Echec de la generation de l'icone ***
        exit /b 1
    )
)

REM  L'icone est embarquee deux fois : en ressource Win32 pour que le shell la
REM  peigne dans la barre des taches et l'explorateur, et en ressource managee
REM  pour que le code puisse en tirer la taille exacte demandee par la fenetre.
"%FW%\csc.exe" /nologo /target:winexe /out:OpusScreen.exe /platform:anycpu /optimize+ ^
    /win32icon:assets\OpusScreen.ico ^
    /resource:assets\OpusScreen.ico,OpusScreen.ico ^
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
echo OpusScreen.exe genere avec succes.
endlocal

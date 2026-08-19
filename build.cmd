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

REM ---------------------------------------------------------------------------
REM  Icone de l'application.
REM
REM  Elle est derivee de assets\logo.png quand ce fichier existe, et tracee par
REM  code sinon. La regeneration a lieu des que le logo est plus recent que
REM  l'icone : sans cette comparaison, remplacer le logo ne changeait rien tant
REM  que l'ancienne icone trainait sur le disque.
REM ---------------------------------------------------------------------------
set MAKEICON=0
if not exist "assets\OpusScreen.ico" set MAKEICON=1
if exist "assets\logo.png" if not exist "assets\logo-embed.png" set MAKEICON=1
if exist "assets\logo.png" (
    for %%L in ("assets\logo.png") do for %%I in ("assets\OpusScreen.ico") do (
        if "%%~tL" GTR "%%~tI" set MAKEICON=1
    )
)

if "%MAKEICON%"=="1" (
    echo Generation de l'icone...
    "%FW%\csc.exe" /nologo /target:exe /out:"%TEMP%\OpusScreenMakeIcon.exe" ^
        /r:"%FW%\System.dll" /r:"%FW%\System.Drawing.dll" tools\MakeIcon.cs
    if errorlevel 1 (
        echo *** Echec de la compilation du generateur d'icone ***
        exit /b 1
    )
    "%TEMP%\OpusScreenMakeIcon.exe" "assets\OpusScreen.ico" "assets\logo.png"
    if errorlevel 1 (
        echo *** Echec de la generation de l'icone ***
        exit /b 1
    )
)

REM  L'icone est embarquee deux fois : en ressource Win32 pour que le shell la
REM  peigne dans la barre des taches et l'explorateur, et en ressource managee
REM  pour que le code puisse en tirer la taille exacte demandee par la fenetre.
REM
REM  Le logo est embarque dans sa version REDUITE : le fichier d'origine pese plus
REM  d'un megaoctet, soit plus que tout le reste de l'executable reuni, pour une
REM  image que la fenetre affiche sur quarante pixels de haut.
set LOGORES=
if exist "assets\logo-embed.png" set LOGORES=/resource:assets\logo-embed.png,OpusScreen.logo.png

"%FW%\csc.exe" /nologo /target:winexe /out:OpusScreen.exe /platform:anycpu /optimize+ ^
    /win32icon:assets\OpusScreen.ico ^
    /resource:assets\OpusScreen.ico,OpusScreen.ico ^
    %LOGORES% ^
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

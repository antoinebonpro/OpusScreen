@echo off
REM ---------------------------------------------------------------------------
REM  OpusScreen - protocole de verification
REM
REM  Compile chaque test avec les sources de l'application, puis l'execute.
REM  Un seul echec fait echouer l'ensemble : ce script est le filtre a passer
REM  avant toute mise en production.
REM
REM  Usage :  run-tests.cmd              les huit tests automatiques
REM           run-tests.cmd monitor      observation continue (Ctrl+C pour sortir)
REM           run-tests.cmd singe [n]    singe en mode REEL : il emprunte la souris
REM                                      et le clavier (n gestes, 400 par defaut).
REM                                      Bouger la souris ou Echap l'arrete.
REM           run-tests.cmd singe-messages [n] [graine]
REM                                      singe sans la souris, graine au choix
REM
REM  Note d'implementation : la sequence est ecrite a plat, sans "call :label".
REM  Une premiere version factorisee sautait silencieusement un test tout en
REM  annoncant un succes complet - un test qui ne s'execute pas est pire qu'un
REM  test absent, car il donne une fausse assurance.
REM ---------------------------------------------------------------------------

setlocal enabledelayedexpansion
cd /d "%~dp0"

set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
if not exist "%FW%\csc.exe" set FW=%WINDIR%\Microsoft.NET\Framework\v4.0.30319
if not exist "%FW%\csc.exe" (
    echo Compilateur C# introuvable. Le .NET Framework 4 est-il installe ?
    exit /b 1
)

set REFS=/r:"%FW%\System.dll" /r:"%FW%\System.Drawing.dll" /r:"%FW%\System.Windows.Forms.dll" /r:"%FW%\System.Management.dll" /r:"%FW%\System.Core.dll"

REM Program.cs porte le point d'entree de l'application : on l'ecarte pour que
REM chaque test fournisse le sien.
set SOURCES=
for %%F in (..\src\*.cs) do (
    if /I not "%%~nxF"=="Program.cs" set SOURCES=!SOURCES! "%%F"
)

if not exist bin mkdir bin
set FAILED=0
set RAN=0

if /I "%~1"=="monitor" goto monitor
if /I "%~1"=="singe" goto singe
if /I "%~1"=="singe-messages" goto singemessages

REM =========================================================== 1/8
echo.
echo ============================================================
echo  1/8  EngineTest  --  plan de luminosite, rampes, temperature, soleil
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\EngineTest.exe %REFS% EngineTest.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\EngineTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 2/8
echo.
echo ============================================================
echo  2/8  MatrixTest  --  saturation, filtres, daltonisme
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\MatrixTest.exe %REFS% MatrixTest.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\MatrixTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 3/8
echo.
echo ============================================================
echo  3/8  SafetyTest  --  restauration, bornes, configuration, contrastes
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\SafetyTest.exe %REFS% SafetyTest.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\SafetyTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 4/8
echo.
echo ============================================================
echo  4/8  DpstTest  --  detection DPST et LACE du pilote Intel
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\DpstTest.exe %REFS% DpstTest.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\DpstTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 5/8
echo.
echo ============================================================
echo  5/8  TaskbarTest  --  icone, raccourci et liste de taches
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\TaskbarTest.exe %REFS% TaskbarTest.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\TaskbarTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 6/8
echo.
echo ============================================================
echo  6/8  VisionTest  --  daltonisme, basse vision, identifiants d'ecran
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\VisionTest.exe %REFS% VisionTest.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\VisionTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 7/8
echo.
echo ============================================================
echo  7/8  UiTest  --  clics, molette, defilement, ecrans, daltonisme
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\UiTest.exe %REFS% UiTest.cs UiHarness.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\UiTest.exe
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== 8/8
REM  Le singe, en mode messages : des milliers de gestes au hasard, invariants
REM  verifies apres chacun. Graine fixe ici pour qu'un echec se rejoue a l'identique ;
REM  "run-tests.cmd singe-messages" explore avec une graine nouvelle a chaque fois.
echo.
echo ============================================================
echo  8/8  MonkeyTest  --  3000 gestes au hasard, invariants apres chacun
echo ============================================================
"%FW%\csc.exe" /nologo /target:exe /out:bin\MonkeyTest.exe %REFS% MonkeyTest.cs UiHarness.cs !SOURCES!
if errorlevel 1 (echo   *** ECHEC DE COMPILATION *** & set /a FAILED+=1) else (
    set /a RAN+=1
    bin\MonkeyTest.exe messages 3000 20260921
    if errorlevel 1 set /a FAILED+=1
)

REM =========================================================== bilan
echo.
echo ============================================================
echo   Tests executes : !RAN! / 8
echo   Echecs         : !FAILED!
if !RAN! NEQ 8 (
    echo   RESULTAT : INCOMPLET - un test n'a pas ete execute
    echo ============================================================
    exit /b 1
)
if !FAILED! NEQ 0 (
    echo   RESULTAT : ECHEC
    echo ============================================================
    exit /b 1
)
echo   RESULTAT : tous les tests passent
echo ============================================================
exit /b 0

:monitor
echo Compilation de l'outil d'observation...
"%FW%\csc.exe" /nologo /target:exe /out:bin\Monitor.exe %REFS% Monitor.cs !SOURCES!
if errorlevel 1 exit /b 1
echo.
echo Observation de la gamma et du retroeclairage. Ctrl+C pour arreter.
echo.
bin\Monitor.exe 600
exit /b 0

:singe
echo Compilation du singe...
"%FW%\csc.exe" /nologo /target:exe /out:bin\MonkeyTest.exe %REFS% MonkeyTest.cs UiHarness.cs !SOURCES!
if errorlevel 1 exit /b 1
set N=%~2
if "%N%"=="" set N=400
echo.
echo Le singe va emprunter la souris et le clavier. Bougez la souris ou appuyez
echo sur Echap pour l'arreter. Aucun reglage de la machine n'est touche.
echo.
bin\MonkeyTest.exe reel %N%
exit /b %errorlevel%

:singemessages
echo Compilation du singe...
"%FW%\csc.exe" /nologo /target:exe /out:bin\MonkeyTest.exe %REFS% MonkeyTest.cs UiHarness.cs !SOURCES!
if errorlevel 1 exit /b 1
set N=%~2
if "%N%"=="" set N=5000
bin\MonkeyTest.exe messages %N% %~3
exit /b %errorlevel%

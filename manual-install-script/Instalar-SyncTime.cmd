@echo off
setlocal

set "SYNC_TIME_INSTALLER=%~dp0Sync-TimeAtLogon.ps1"

if not exist "%SYNC_TIME_INSTALLER%" (
    echo ERRO: Sync-TimeAtLogon.ps1 nao foi encontrado ao lado deste arquivo.
    pause
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -Command ^
  "$ErrorActionPreference = 'Stop'; $installer = $env:SYNC_TIME_INSTALLER; $identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = New-Object Security.Principal.WindowsPrincipal($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { & $installer; exit 0 }; try { $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; $arguments = '-NoLogo -NoProfile -File ' + [char]34 + $installer + [char]34; $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -Wait -PassThru; exit $process.ExitCode } catch { Write-Error ('A instalacao nao foi concluida: ' + $_.Exception.Message); exit 1 }"

set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
    echo.
    echo A instalacao terminou com erro (codigo %RESULT%).
    echo Consulte o log em C:\ProgramData\FAFAR\SyncTime\Sync-TimeAtLogon.log.
    echo Se a tarefa ainda nao foi criada, verifique o bloqueio do PowerShell ou a permissao do UAC.
    echo.
    pause
    exit /b %RESULT%
)

echo Instalacao concluida. Consulte o log em C:\ProgramData\FAFAR\SyncTime\Sync-TimeAtLogon.log.
pause
exit /b 0

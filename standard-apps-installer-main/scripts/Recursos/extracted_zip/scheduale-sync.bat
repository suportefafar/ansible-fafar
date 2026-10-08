@echo off

:: Garante o System32 no PATH (algumas sessoes remotas chegam sem ele)
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%PATH%"

:: Name of the task
set TASKNAME=SyncTimeAtLogon

:: Path to your silent sync script
set SCRIPT=C:\sync-datetime\sync-datetime.bat

:: Trava as permissoes da pasta: a tarefa roda como SYSTEM, entao usuarios comuns
:: (alunos) so podem LER/EXECUTAR - nao podem alterar os scripts. SIDs independem de idioma.
:: SYSTEM (S-1-5-18) e Administradores (S-1-5-32-544): controle total | Usuarios (S-1-5-32-545): leitura
icacls "%~dp0." /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" >nul 2>&1

:: Delete existing task if it exists
schtasks /Delete /TN "%TASKNAME%" /F >nul 2>&1

:: Cria a tarefa para rodar a cada logon, como SYSTEM (funciona com qualquer usuario logado
:: ou nenhum, e sempre tem privilegio para acertar a hora) com privilegios maximos
schtasks /Create /TN "%TASKNAME%" /TR "\"%SCRIPT%\"" /SC ONLOGON /RU SYSTEM /RL HIGHEST /F
if %errorlevel% neq 0 (
    echo ERRO: nao foi possivel criar a tarefa "%TASKNAME%".
    exit /b 1
)

echo Task "%TASKNAME%" created successfully.
exit /b 0

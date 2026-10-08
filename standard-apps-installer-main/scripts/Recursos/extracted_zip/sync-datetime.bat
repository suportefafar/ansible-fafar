@echo off

:: Garante o System32 no PATH (algumas sessoes chegam sem ele)
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0;%PATH%"

set /a TENTATIVAS=0

:CHECK_REDE
:: Considera a rede pronta se o Cronos (interno) OU a internet (8.8.8.8) responder
ping -n 1 -w 2000 cronos.farmacia.ufmg.br >nul 2>&1
if %errorlevel% equ 0 goto REDE_OK
ping -n 1 -w 2000 8.8.8.8 >nul 2>&1
if %errorlevel% equ 0 goto REDE_OK

set /a TENTATIVAS+=1
:: Limite de ~3 min: depois segue mesmo assim (o servico registra em log o que falhar e repete em loop)
if %TENTATIVAS% geq 18 goto REDE_OK
echo Aguardando conexão de rede...
:: (ping como "sleep": o timeout.exe falha quando nao ha console, como em tarefa agendada)
ping -n 11 127.0.0.1 >nul 2>&1
goto CHECK_REDE

:REDE_OK
:: Espera 60 segundos para estabilizar a rede
echo Rede detectada. Aguardando 60 segundos para estabilizar...
ping -n 61 127.0.0.1 >nul 2>&1

:: Set timezone to São Paulo
tzutil /s "E. South America Standard Time" >nul 2>&1

:: Inicia o servico de sincronizacao. Ordem por ciclo (testa apos cada metodo):
::   Cronos NTP -> Cronos HTTP -> Windows (w32tm) -> NTP publico
::   o primeiro teste que confirmar a hora correta encerra o loop
::   registra tudo em .\logs\sync-hora_<data>.log
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-datetime.ps1"

exit

@echo off

:CHECK_INTERNET
:: Tenta pingar o Google (8.8.8.8) para ver se há internet
ping -n 1 8.8.8.8 >nul 2>&1
if %errorlevel% neq 0 (
    echo Aguardando conexão com a internet...
    timeout /t 10 /nobreak >nul
    goto CHECK_INTERNET
)

:: Internet detectada! Espera 60 segundos para estabilizar a rede
echo Internet detectada. Aguardando 60 segundos para estabilizar...
timeout /t 60 /nobreak >nul

:: Set timezone to São Paulo
tzutil /s "E. South America Standard Time" >nul 2>&1

:: Ensure Windows Time service is automatic and started
sc config w32time start= auto >nul 2>&1
net start w32time >nul 2>&1

:: Attempt sync with retries
echo Sincronizando relógio...
w32tm /resync /force >nul 2>&1

if %errorlevel% neq 0 (
    timeout /t 5 /nobreak >nul
    w32tm /resync /force >nul 2>&1
)

:: Final check and optional forced re-register if still fails
if %errorlevel% neq 0 (
    w32tm /unregister >nul 2>&1
    w32tm /register >nul 2>&1
    net start w32time >nul 2>&1
    timeout /t 5 /nobreak >nul
    w32tm /resync /force >nul 2>&1
)

exit

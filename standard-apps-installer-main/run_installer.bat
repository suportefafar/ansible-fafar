@echo off
setlocal enabledelayedexpansion

echo ======================================================
echo    BOTASTRAP: INICIANDO CONFIGURACAO DO LABORATORIO
echo ======================================================

:: 1. Verificar se o Python está instalado
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Python nao detectado. Tentando via winget...
    winget --version >nul 2>&1
    if %errorlevel% equ 0 (
        winget install -e --id Python.Python.3.11 --silent --accept-package-agreements --accept-source-agreements
    ) else (
        echo [INFO] Winget nao encontrado. Baixando Python via PowerShell...
        powershell -Command "$url = 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe'; $out = \"$env:TEMP\python-3.11.exe\"; Invoke-WebRequest -Uri $url -OutFile $out; Start-Process -FilePath $out -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1' -Wait"
    )
    
    :: Verificar novamente
    python --version >nul 2>&1
    if %errorlevel% neq 0 (
        echo [ERRO] Falha ao instalar Python. Tente instalar manualmente em python.org
        pause
        exit /b 1
    )
    :: Atualizar PATH para a sessao atual (Tentativa de detectar caminho padrao)
    set "PATH=%PATH%;C:\Program Files\Python311;C:\Program Files\Python311\Scripts;%LocalAppData%\Programs\Python\Python311;%LocalAppData%\Programs\Python\Python311\Scripts"
)

echo [OK] Python detectado: 
python --version

:: 2. Instalar dependencias (se houver)
if exist requirements.txt (
    echo [INFO] Instalando dependencias do Python...
    python -m pip install -r requirements.txt --quiet
)

:: 3. Rodar o script principal como Administrador
echo [INFO] Iniciando o Instalador Principal...
python src\main.py

echo.
echo ======================================================
echo    PROCESSO CONCLUIDO. VERIFIQUE OS LOGS EM 'logs/'
echo ======================================================
pause
endlocal

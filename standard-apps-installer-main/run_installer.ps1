# run_installer.ps1 - Bootstrapper para Laboratórios (UFMG)
$ErrorActionPreference = 'Stop'

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   BOOTSTRAP POWERSHELL: CONFIGURANDO LABORATORIO     " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

try {
    # 1. Verificar Privilégios de Administrador
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "======================================================" -ForegroundColor Red
        Write-Host " ERRO: ESTE SCRIPT PRECISA DE PERMISSAO DE ADMIN" -ForegroundColor Red
        Write-Host "======================================================" -ForegroundColor Red
        Write-Host "Por favor, clique com o direito e selecione 'Executar como Administrador'"
        Write-Host "ou abra o PowerShell como Admin e rode o script novamente."
        pause
        exit 1
    }

    # 2. Configurar Segurança (TLS 1.2)
    Write-Host "[1/4] Configurando segurança e protocolos..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 3. Verificar/Instalar Python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Python já detectado." -ForegroundColor Green
    } else {
        Write-Host "[2/4] Python não encontrado. Iniciando instalação..." -ForegroundColor Yellow
        $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
        $pyExe = "$env:TEMP\python_installer.exe"
        
        Write-Host "Baixando Python 3.11.9..." -ForegroundColor Gray
        (New-Object System.Net.WebClient).DownloadFile($pyUrl, $pyExe)
        
        Write-Host "Instalando silenciosamente... (Isso pode levar 1-2 minutos)" -ForegroundColor Gray
        Start-Process -FilePath $pyExe -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
        
        # Atualizar binários na sessão atual
        $env:Path += ";C:\Program Files\Python311;C:\Program Files\Python311\Scripts;"
        $env:Path += "$env:LocalAppData\Programs\Python\Python311;$env:LocalAppData\Programs\Python\Python311\Scripts"
        
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Write-Error "Falha crítica: Python foi instalado mas o comando 'python' não responde. Tente reiniciar o PowerShell."
            exit 1
        }
        Write-Host "[OK] Python instalado com sucesso." -ForegroundColor Green
    }

    # 4. Instalar Dependências (se houver requirements.txt)
    if (Test-Path "requirements.txt") {
        Write-Host "[3/4] Instalando dependências do projeto..." -ForegroundColor Yellow
        python -m pip install -r requirements.txt --quiet
    }

    # 5. Executar Script Principal
    Write-Host "[4/4] Iniciando orquestrador Python (main.py)..." -ForegroundColor Yellow
    Write-Host "------------------------------------------------------"
    
    # Mudar diretório para a pasta do script para evitar erros de caminho relativo
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Push-Location $scriptDir
    
    python src/main.py
    
    Pop-Location

    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "    PROCESSO CONCLUÍDO! VERIFIQUE OS LOGS EM 'logs/'  " -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
} catch {
    Write-Host "`n======================================================" -ForegroundColor Red
    Write-Host "            ERRO FATAL NO BOOTSTRAP                   " -ForegroundColor Red
    Write-Host "======================================================" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host "`nScript parado para depuração."
}
pause

# scripts/01-Preparo/preparar_maquina_completo.ps1
# Script Unificado de Preparo: Configura WinRM + Instala Chocolatey
# Execute este script como ADMINISTRADOR no computador alvo.

$ErrorActionPreference = 'Stop'

# 0. Verificação de Privilégios de Administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Este script PRECISA ser executado como ADMINISTRADOR."
    exit 1
}

Write-Host "`n=== [ETAPA 1/2] Configurando WinRM para Gestão Remota ===" -ForegroundColor Cyan

# 1.1 Garante que a rede seja tratada como Privada (necessário para o WinRM liberar)
Write-Host "Configurando perfil de rede como Privado..."
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

# 1.2 Ativa o serviço WinRM
Write-Host "Ativando WinRM QuickConfig..."
winrm quickconfig -q

# 1.3 Configura permissões de autenticação
Write-Host "Configurando autenticação Básica e Sem Criptografia..."
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# 1.4 Libera acesso administrativo remoto para contas locais (UAC Remote Restriction)
Write-Host "Aplicando LocalAccountTokenFilterPolicy no Registro..."
reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f

# 1.5 Garante que o Firewall permita a conexão na porta 5985 (HTTP)
if (!(Get-NetFirewallRule -DisplayName "WinRM-HTTP" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow
    Write-Host "Regra de Firewall WinRM-HTTP criada." -ForegroundColor Green
} else {
    Write-Host "Regra de Firewall WinRM-HTTP já existe." -ForegroundColor Yellow
}

Write-Host "`n=== [ETAPA 2/2] Instalando Chocolatey ===" -ForegroundColor Cyan

# 2.1 Configurar TLS 1.2 e 1.3
Write-Host "Configurando protocolos de segurança (TLS 1.2/1.3)..."
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

try {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Chocolatey já está instalado." -ForegroundColor Cyan
    } else {
        Write-Host "Instalando Chocolatey..." -ForegroundColor Yellow
        $maxRetries = 3
        $retryCount = 0
        $success = $false

        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                $installScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
                iex $installScript
                $success = $true
                Write-Host "Chocolatey instalado com sucesso." -ForegroundColor Green
            } catch {
                $retryCount++
                Write-Warning "Falha na tentativa $retryCount de $maxRetries. Tentando novamente em 5 segundos..."
                Start-Sleep -Seconds 5
            }
        }

        if (-not $success) {
            throw "Não foi possível instalar o Chocolatey após $maxRetries tentativas."
        }
    }
} catch {
    Write-Error "Erro crítico ao inicializar o Chocolatey: $_"
    exit 1
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "PREPARO CONCLUÍDO COM SUCESSO!" -ForegroundColor Green
Write-Host "A máquina agora pode ser gerenciada remotamente e instalar pacotes." -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green

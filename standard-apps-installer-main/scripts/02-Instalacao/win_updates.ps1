# Script para atualizar o Windows
$ErrorActionPreference = 'Continue'

Write-Host "Verificando Atualizações do Windows..." -ForegroundColor Cyan

# 1. Preparar Provedores de Pacotes (Essencial para máquinas novas)
try {
    Write-Host "Configurando provedor NuGet e PSGallery..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Aviso: Falha ao configurar provedores de pacotes. A instalação do módulo pode falhar."
}

# 2. Tenta usar o módulo PSWindowsUpdate
$module = Get-Module -ListAvailable PSWindowsUpdate

if (-not $module) {
    Write-Host "Instalando módulo de atualização (PSWindowsUpdate)..." -ForegroundColor Yellow
    try {
        Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -Scope AllUsers -Confirm:$false
        Import-Module PSWindowsUpdate -ErrorAction Stop
    } catch {
        Write-Warning "Falha ao instalar módulo PSWindowsUpdate via PowerShell Gallery."
        Write-Host "Tentando via Chocolatey..." -ForegroundColor Yellow
        choco install pswindowsupdate -y
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
    }
}

if (Get-Module -ListAvailable PSWindowsUpdate) {
    try {
        Write-Host "Buscando e instalando atualizações..." -ForegroundColor Yellow
        # Aceita tudo e instala
        Get-WindowsUpdate -Install -AcceptAll -IgnoreReboot -ErrorAction Stop
        Write-Host "Processo de atualização finalizado." -ForegroundColor Green
    } catch {
        Write-Warning "Erro durante a instalação das atualizações: $_"
    }
} else {
    Write-Error "Não foi possível carregar o módulo de atualizações após várias tentativas."
}

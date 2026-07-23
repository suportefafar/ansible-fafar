# setup_lab.ps1 - Orquestrador Nativo de Laboratórios (UFMG)
param(
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

# --- 1. Configurar Caminhos e Logs ---
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
Push-Location $scriptDir

$logDir = Join-Path $scriptDir 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ('install_ps_' + (Get-Date -Format 'yyyyMMdd_HHmm') + '.log')

Start-Transcript -Path $logFile -Append

Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '      SISTEMA DE AUTOMAÇÃO DE LABORATÓRIOS (UFMG)     ' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan

try {
    # --- 2. Verificar Privilégios de Administrador ---
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Solicitando permissoes de administrador...' -ForegroundColor Yellow
        $argList = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
        Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
        Stop-Transcript
        exit
    }

    # --- 3. Configurar Segurança (TLS 1.2) ---
    Write-Host '[1/4] Configurando protocolos de seguranca...' -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    # --- 4. Inicializar Chocolatey ---
    Write-Host '[2/4] Inicializando Gerenciador de Pacotes (Chocolatey)...' -ForegroundColor Yellow
    & "$scriptDir\scripts\init_choco.ps1"

    # --- 5. Instalar Aplicativos ---
    $configPath = Join-Path $scriptDir 'config\apps.json'
    if (Test-Path $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Json
        $packages = $config.packages
        if ($packages) {
            Write-Host '[3/4] Instalando aplicativos...' -ForegroundColor Yellow
            & "$scriptDir\scripts\install_apps.ps1" -Packages ($packages -join ',')
        }
    }

    # --- 6. Aplicar Otimizações ---
    Write-Host '[4/4] Aplicando otimizacoes...' -ForegroundColor Yellow
    & "$scriptDir\scripts\sys_config.ps1"

    # --- 7. Atualizações ---
    & "$scriptDir\scripts\win_updates.ps1"

    Write-Host 'PROCESSO FINALIZADO COM SUCESSO!' -ForegroundColor Green

} catch {
    Write-Host 'ERRO FATAL: ' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    Stop-Transcript
    Pop-Location
}

if (-not $NonInteractive) {
    Write-Host 'Pressione Enter para sair...'
    Read-Host
}

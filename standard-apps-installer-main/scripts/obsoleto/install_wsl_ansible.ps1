# scripts/install_wsl_ansible.ps1
# Script para ativar o WSL e preparar o ambiente para Ansible

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Solicitando permissão de Administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "Ativando recursos do WSL e Máquina Virtual..." -ForegroundColor Cyan
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

Write-Host "Tentando instalar o kernel do WSL e o Ubuntu..." -ForegroundColor Cyan
wsl --install -d Ubuntu

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "PROCESSO CONCLUÍDO!" -ForegroundColor Green
Write-Host "1. REINICIE o seu computador agora." -ForegroundColor Yellow
Write-Host "2. Após reiniciar, o Ubuntu abrirá automaticamente para configurar usuário/senha."
Write-Host "3. Dentro do Ubuntu, rode: sudo apt update && sudo apt install -y ansible"
Write-Host "=======================================================" -ForegroundColor Green

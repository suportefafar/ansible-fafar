# scripts/configurar_wsl_ansible.ps1
# Script para instalar a distribuição Ubuntu no WSL e configurar o Ansible automaticamente

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Iniciando a instalação e configuração do WSL (Ubuntu)..." -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# 1. Instalar a distribuição Ubuntu
Write-Host "`n[Passo 1] Instalando o Ubuntu. Isso pode demorar alguns minutos dependendo da sua internet..." -ForegroundColor Yellow
wsl --install -d Ubuntu

Write-Host "`n[Verificação] Checando se o Ubuntu foi instalado corretamente..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
$wslStatus = wsl -l -v
if ($wslStatus -match "Ubuntu") {
    Write-Host "Ubuntu instalado com sucesso!" -ForegroundColor Green
} else {
    Write-Warning "A instalação do Ubuntu pode exigir que você reinicie o computador primeiro."
    Write-Warning "Se for o caso, por favor reinicie a máquina e rode este script novamente."
    exit
}

# 2. Atualizar os pacotes do Linux e instalar o Ansible
Write-Host "`n[Passo 2] Atualizando os repositórios do Linux e instalando o Ansible..." -ForegroundColor Yellow
Write-Host "(Se pedir senha, digite a senha que você acabou de criar para o Linux)" -ForegroundColor Gray

# O comando abaixo entra no Linux, atualiza a lista de pacotes e instala o ansible
wsl -d Ubuntu -u root -e bash -c "apt-get update && apt-get install -y ansible"

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "Configuração Concluída!" -ForegroundColor Green
Write-Host "Agora você já pode executar o playbook do Ansible." -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green

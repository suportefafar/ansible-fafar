# scripts/disparar_ansible_turbo.ps1
# Scanner de porta 5985 (WinRM) para encontrar alvos instantaneamente e criar inventario dinamico para o Ansible

$onlineHosts = @()
Write-Host ">>> [FASE 1] Escaneando laboratório via Porta 5985 (WinRM)..." -ForegroundColor Cyan

1..253 | ForEach-Object {
    $ip = "192.168.137.$_"
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connect = $tcp.BeginConnect($ip, 5985, $null, $null)
    
    # Espera apenas 100ms por IP (Super rápido!)
    if ($connect.AsyncWaitHandle.WaitOne(100)) {
        if ($tcp.Connected) {
            Write-Host "   [+] WinRM Ativo em: $ip" -ForegroundColor Green
            $onlineHosts += $ip
        }
    }
    $tcp.Close()
}

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum PC com WinRM ativo foi encontrado na rede 192.168.137.x"
    exit
}

Write-Host "`n>>> [FASE 2] Gerando inventário dinâmico do Ansible..." -ForegroundColor Cyan

$ansibleDir = "$PSScriptRoot\..\ansible"
$inventoryPath = "$ansibleDir\inventory_dynamic.ini"

# Cria o conteúdo do inventário
$inventoryContent = @"
[lab_computers]
$($onlineHosts -join "`n")

[lab_computers:vars]
ansible_connection=winrm
ansible_winrm_transport=basic
ansible_winrm_server_cert_validation=ignore
ansible_user=.\User
ansible_password=anjos2014
ansible_port=5985
"@

Set-Content -Path $inventoryPath -Value $inventoryContent -Encoding UTF8
Write-Host "   -> Inventário criado em: $inventoryPath" -ForegroundColor Green

Write-Host "`n>>> [FASE 3] Disparando Ansible Playbook (Execução Paralela)..." -ForegroundColor Cyan

# Executar ansible via WSL
Set-Location $ansibleDir
wsl --cd "$ansibleDir" ansible-playbook -i inventory_dynamic.ini deploy_zip_schedule.yml

Write-Host "`n>>> Deploy concluído." -ForegroundColor Green

# scripts/03-Deploy-Massa/disparar_clean_lab.ps1
# Deploy massivo de limpeza de usuários (FARMANET) e redefinição de wallpaper padrão para o laboratório

$scriptLocal = "$PSScriptRoot\..\04-Diagnostico\clean_lab_users.ps1"
$scriptRemotePath = "C:\Windows\Temp\clean_lab_users.ps1"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser = New-Object System.Management.Automation.PSCredential("User", $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

$onlineHosts = @()
Write-Host ">>> [FASE 1] Detectando sub-redes ativas e escaneando laboratório..." -ForegroundColor Cyan

# Detecta sub-redes IPv4 ativas (desconsiderando loopback, link-local e interfaces virtuais comuns)
$interfaces = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notlike "127.*" -and 
    $_.IPAddress -notlike "169.254.*" -and 
    $_.InterfaceAlias -notlike "*VirtualBox*" -and 
    $_.InterfaceAlias -notlike "*VMware*" -and
    $_.InterfaceAlias -notlike "*vEthernet*"
}

$subnets = @()
foreach ($if in $interfaces) {
    if ($if.IPAddress -match '^(\d+\.\d+\.\d+)\.\d+$') {
        $subnets += $Matches[1]
    }
}

# Remove duplicatas
$subnets = $subnets | Select-Object -Unique

if ($subnets.Count -eq 0) {
    Write-Warning "Nenhuma sub-rede ativa foi identificada."
    exit
}

foreach ($subnet in $subnets) {
    Write-Host " -> Escaneando sub-rede: $subnet.0/24..." -ForegroundColor Yellow
    1..254 | ForEach-Object {
        $ip = "$subnet.$_"
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($ip, 5985, $null, $null)
        
        if ($connect.AsyncWaitHandle.WaitOne(100)) {
            if ($tcp.Connected) {
                Write-Host "   [+] WinRM Ativo em: $ip" -ForegroundColor Green
                $onlineHosts += $ip
            }
        }
        $tcp.Close()
    }
}

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum PC com WinRM ativo foi encontrado."
    exit
}

Write-Host "`n>>> [FASE 2] Iniciando Limpeza nos $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

try {
    # Abre sessões em paralelo - Tenta primeiro com "User"
    Write-Host "   -> Conectando usando usuário 'User'..." -ForegroundColor Yellow
    $sessionsUser = New-PSSession -ComputerName $onlineHosts -Credential $credUser -ErrorAction SilentlyContinue
    $activeSessionsUser = $sessionsUser | Where-Object { $_.State -eq 'Opened' }
    
    # Identifica máquinas que falharam e tenta "admin" nelas
    $connectedHosts = $activeSessionsUser | ForEach-Object { $_.ComputerName }
    $remainingHosts = $onlineHosts | Where-Object { $_ -notin $connectedHosts }
    
    $activeSessionsAdmin = @()
    $sessionsAdmin = @()
    if ($remainingHosts) {
        Write-Host "   -> Tentando conectar em $($remainingHosts.Count) PCs usando usuário 'admin'..." -ForegroundColor Yellow
        $sessionsAdmin = New-PSSession -ComputerName $remainingHosts -Credential $credAdmin -ErrorAction SilentlyContinue
        $activeSessionsAdmin = $sessionsAdmin | Where-Object { $_.State -eq 'Opened' }
    }
    
    $activeSessions = $activeSessionsUser + $activeSessionsAdmin
    
    if (-not $activeSessions) {
        Write-Error "Não foi possível abrir nenhuma sessão válida com 'User' ou 'admin'."
        return
    }

    Write-Host "   -> Copiando script e executando limpeza em cada PC..." -ForegroundColor Yellow
    
    foreach ($session in $activeSessions) {
        $ip = $session.ComputerName
        try {
            Write-Host "      [>] Processando: $ip..." -ForegroundColor Cyan
            
            # Copia o script de limpeza
            Copy-Item -Path $scriptLocal -Destination $scriptRemotePath -ToSession $session -ErrorAction Stop
            
            # Executa a limpeza no alvo
            Invoke-Command -Session $session -ScriptBlock {
                param($path)
                if (Test-Path $path) {
                    Set-ExecutionPolicy Bypass -Scope Process -Force
                    & $path
                    Remove-Item $path -Force -ErrorAction SilentlyContinue
                } else {
                    Write-Error "Script de limpeza não encontrado no caminho remoto: $path"
                }
            } -ArgumentList $scriptRemotePath -ErrorAction Stop
            
            Write-Host "      [+] Sucesso em $ip" -ForegroundColor Green
        } catch {
            Write-Warning "      [-] Falha ao executar limpeza no PC $ip : $($_.Exception.Message)"
        }
    }
    
    if ($sessionsUser) { Remove-PSSession $sessionsUser -ErrorAction SilentlyContinue }
    if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }
    Write-Host "`n>>> LIMPEZA CONCLUÍDA EM TODAS AS MÁQUINAS ATIVAS!" -ForegroundColor Green

} catch {
    Write-Host "`n>>> ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

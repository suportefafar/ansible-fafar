# scripts/03-Deploy-Massa/disparar_deploy_epiinfo_cdc.ps1
# Deploy massivo PARALELO SIMULTÂNEO do Epi Info 7.2.6.0 (CDC) para Downloads e criação do atalho "EPI - Funcionando"

$sourceCdc = "$PSScriptRoot\..\..\apps\CDC"
$localZip = "$env:TEMP\cdc_epiinfo_$([DateTime]::Now.Ticks).zip"
$remoteZip = "C:\Windows\Temp\cdc_epiinfo.zip"

$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser = New-Object System.Management.Automation.PSCredential("User", $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

if (-not (Test-Path $sourceCdc)) {
    Write-Error "Pasta de origem CDC não encontrada em: $sourceCdc"
    exit 1
}

Write-Host ">>> [FASE 1] Empacotando pasta CDC local..." -ForegroundColor Cyan
Compress-Archive -Path "$sourceCdc\*" -DestinationPath $localZip -Force
Write-Host "   [+] Arquivo compactado com sucesso em: $localZip" -ForegroundColor Green

$onlineHosts = @()
Write-Host "`n>>> [FASE 2] Escaneando sub-redes e detectando PCs ativos na porta WinRM 5985..." -ForegroundColor Cyan

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
$subnets = $subnets | Select-Object -Unique

if ($subnets.Count -eq 0) {
    Write-Warning "Nenhuma sub-rede ativa foi identificada."
    if (Test-Path $localZip) { Remove-Item $localZip -Force -ErrorAction SilentlyContinue }
    exit 1
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
    if (Test-Path $localZip) { Remove-Item $localZip -Force -ErrorAction SilentlyContinue }
    exit 1
}

Write-Host "`n>>> [FASE 3] Conectando em PARALELO nos $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

try {
    # Conecta em paralelo com "User"
    Write-Host "   -> Abrindo sessões com usuário 'User'..." -ForegroundColor Yellow
    $sessionsUser = New-PSSession -ComputerName $onlineHosts -Credential $credUser -ErrorAction SilentlyContinue
    $activeSessionsUser = $sessionsUser | Where-Object { $_.State -eq 'Opened' }
    
    # Identifica máquinas restantes e conecta em paralelo com "admin"
    $connectedHosts = $activeSessionsUser | ForEach-Object { $_.ComputerName }
    $remainingHosts = $onlineHosts | Where-Object { $_ -notin $connectedHosts }
    
    $activeSessionsAdmin = @()
    $sessionsAdmin = @()
    if ($remainingHosts) {
        Write-Host "   -> Tentando conectar em $($remainingHosts.Count) PCs com usuário 'admin'..." -ForegroundColor Yellow
        $sessionsAdmin = New-PSSession -ComputerName $remainingHosts -Credential $credAdmin -ErrorAction SilentlyContinue
        $activeSessionsAdmin = $sessionsAdmin | Where-Object { $_.State -eq 'Opened' }
    }
    
    $activeSessions = $activeSessionsUser + $activeSessionsAdmin
    
    if (-not $activeSessions) {
        Write-Error "Não foi possível abrir nenhuma sessão válida com 'User' ou 'admin'."
        if (Test-Path $localZip) { Remove-Item $localZip -Force -ErrorAction SilentlyContinue }
        return
    }

    Write-Host "   -> Copiando pacote ZIP para TODOS os $($activeSessions.Count) PCs..." -ForegroundColor Yellow
    
    # Copia o ZIP para todas as sessões abertas
    $activeSessions | ForEach-Object {
        Copy-Item -Path $localZip -Destination $remoteZip -ToSession $_ -ErrorAction SilentlyContinue
    }

    Write-Host "   -> Executando instalação e criação do atalho 'EPI - Funcionando' em TODOS os PCs SIMULTANEAMENTE (PARALELO)..." -ForegroundColor Cyan

    # Executa Invoke-Command em TODAS as sessões simultaneamente em paralelo!
    Invoke-Command -Session $activeSessions -ScriptBlock {
        param($zipPath)
        
        # 0. Finaliza instâncias em execução do Epi Info para não bloquear arquivos
        $procNames = @("EpiInfo", "Enter", "Analysis", "Menu", "StatCalc", "MakeView", "Mapping", "AnalysisDashboard", "Updater")
        foreach ($proc in $procNames) {
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
        
        $targetDir = "C:\Users\Public\Downloads\CDC"
        $publicDesktop = "C:\Users\Public\Desktop"
        
        # 1. Garante o diretório de destino limpo e descompacta
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        if (Test-Path $zipPath) {
            Expand-Archive -Path $zipPath -DestinationPath $targetDir -Force -ErrorAction SilentlyContinue
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        }
        
        # 2. Permissões de leitura e execução universais
        $icacls = "$env:SystemRoot\System32\icacls.exe"
        if (Test-Path $icacls) {
            & $icacls $targetDir /grant "*S-1-1-0:(OI)(CI)F" /T /C 2>$null
            & $icacls $targetDir /grant "*S-1-5-32-545:(OI)(CI)F" /T /C 2>$null
        }
        
        # 3. Limpeza de atalhos velhos/confusos de Epi Info na Área de Trabalho
        Get-ChildItem -Path $publicDesktop -Filter "*Epi*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -ne "EPI - Funcionando.lnk") {
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
        
        Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $userDesk = Join-Path $_.FullName "Desktop"
            if (Test-Path $userDesk) {
                Get-ChildItem -Path $userDesk -Filter "*Epi*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.Name -ne "EPI - Funcionando.lnk") {
                        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        
        # 4. Criar atalho "EPI - Funcionando"
        $exePath = "$targetDir\Epi Info 7.2.6.0\EpiInfo.exe"
        if (-not (Test-Path $exePath)) {
            $exePath = (Get-ChildItem -Path $targetDir -Filter "EpiInfo.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
        }
        
        if ($exePath -and (Test-Path $exePath)) {
            $shortcutPath = Join-Path $publicDesktop "EPI - Funcionando.lnk"
            $wshShell = New-Object -ComObject WScript.Shell
            $sc = $wshShell.CreateShortcut($shortcutPath)
            $sc.TargetPath = $exePath
            $sc.WorkingDirectory = (Split-Path $exePath -Parent)
            $sc.Description = "Epi Info 7.2.6.0 - Funcionando"
            $sc.Save()
            Write-Host " [+] [$env:COMPUTERNAME] Atalho 'EPI - Funcionando' criado com sucesso para: $exePath"
        } else {
            Write-Warning " [-] [$env:COMPUTERNAME] Executável EpiInfo.exe não encontrado em $targetDir"
        }
    } -ArgumentList $remoteZip
    
    if ($sessionsUser) { Remove-PSSession $sessionsUser -ErrorAction SilentlyContinue }
    if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }
    Write-Host "`n>>> DEPLOY PARALELO DO EPI INFO CDC CONCLUÍDO EM TODAS MÁQUINAS ATIVAS!" -ForegroundColor Green

} catch {
    Write-Host "`n>>> ERRO: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if (Test-Path $localZip) { Remove-Item $localZip -Force -ErrorAction SilentlyContinue }
}

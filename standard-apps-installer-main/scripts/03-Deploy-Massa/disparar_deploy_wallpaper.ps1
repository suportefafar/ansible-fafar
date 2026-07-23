# scripts/03-Deploy-Massa/disparar_deploy_wallpaper.ps1
# Deploy massivo de papel de parede para o laboratório

$wallpaperLocal = "$PSScriptRoot\..\Recursos\wallpaper-fafar.png"
$wallpaperRemotePath = "C:\Users\Public\wallpaper-fafar.png"
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

Write-Host "`n>>> [FASE 2] Iniciando Correção nos $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

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

    Write-Host "   -> Copiando imagem e aplicando configurações em cada PC..." -ForegroundColor Yellow
    
    foreach ($session in $activeSessions) {
        $ip = $session.ComputerName
        try {
            Write-Host "      [>] Processando: $ip..." -ForegroundColor Cyan
            
            # Copia a imagem
            Copy-Item -Path $wallpaperLocal -Destination $wallpaperRemotePath -ToSession $session -ErrorAction Stop
            
            # Aplica no alvo
            Invoke-Command -Session $session -ScriptBlock {
                param($path)
                # Garante permissão de leitura universal usando SIDs (independe de idioma)
                # *S-1-1-0 = Todos (Everyone) | *S-1-5-32-545 = Usuários (Users)
                icacls.exe $path /grant "*S-1-1-0:(R)" /T /C 2>$null
                icacls.exe $path /grant "*S-1-5-32-545:(R)" /T /C 2>$null

                Write-Host "Limpando cache antigo do wallpaper..."
                # Remove cache antigo de TODOS os usuários do computador para garantir a atualização
                Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
                    $userThemePath = "$($_.FullName)\AppData\Roaming\Microsoft\Windows\Themes"
                    if (Test-Path $userThemePath) {
                        Remove-Item "$userThemePath\TranscodedWallpaper" -ErrorAction SilentlyContinue
                        Remove-Item "$userThemePath\CachedFiles\*" -Recurse -ErrorAction SilentlyContinue
                    }
                }

                # 1. Aplicando a Política de Sistema (HKLM) para reforço permanente
                $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
                if (-not (Test-Path $policyPath)) {
                    New-Item -Path $policyPath -Force | Out-Null
                }
                Set-ItemProperty -Path $policyPath -Name "Wallpaper" -Value $path -Force
                Set-ItemProperty -Path $policyPath -Name "WallpaperStyle" -Value "10" -Force
                
                # 2. Criando o payload que vai rodar DENTRO da tela do aluno (Interactive User)
                $scriptTaskPath = "C:\Users\Public\ChangeWallpaperTask.ps1"
                $taskCode = @"
`$ErrorActionPreference = 'SilentlyContinue'

# Limpa o maldito cache da sessão atual
Remove-Item `"`$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper`" -Force
Remove-Item `"`$env:APPDATA\Microsoft\Windows\Themes\CachedFiles\*`" -Recurse -Force

Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value '$path'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'

# A API que o GPT recomendou (roda perfeitamente aqui dentro da tarefa)
Add-Type -TypeDefinition "using System.Runtime.InteropServices; public class Win32 { [DllImport(`"user32.dll`", SetLastError=true)] public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); }"
[Win32]::SystemParametersInfo(20, 0, '$path', 3)
"@
                Set-Content -Path $scriptTaskPath -Value $taskCode -Encoding UTF8

                # 3. Cria a Tarefa Agendada para rodar o payload na tela
                $taskName = "ForceWallpaperUpdateLab"
                $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptTaskPath`""
                
                # O Pulo do Gato corrigido DE VERDADE: Usar o SID universal do grupo "Users" (S-1-5-32-545)
                # Isso ignora o idioma do Windows (Users vs Usuários) e o nome do aluno, forçando a rodar
                # na Sessão Interativa de qualquer pessoa que estiver na frente do computador.
                $principal = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -RunLevel Highest
                
                # Registra a tarefa
                Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
                
                # 4. Dispara a tarefa agora mesmo
                Start-ScheduledTask -TaskName $taskName
                Start-Sleep -Seconds 3
                
                # Reinicia a barra de tarefas apenas para garantir
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

                # 5. Limpeza de rastros (apaga a tarefa e o payload)
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                Remove-Item $scriptTaskPath -Force -ErrorAction SilentlyContinue
            } -ArgumentList $wallpaperRemotePath -ErrorAction Stop
            
            Write-Host "      [+] Sucesso em $ip" -ForegroundColor Green
        } catch {
            Write-Warning "      [-] Falha ao aplicar no PC $ip : $($_.Exception.Message)"
        }
    }
    
    if ($sessionsUser) { Remove-PSSession $sessionsUser -ErrorAction SilentlyContinue }
    if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }
    Write-Host "`n>>> WALLPAPER APLICADO COM SUCESSO!" -ForegroundColor Green

} catch {
    Write-Host "`n>>> ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

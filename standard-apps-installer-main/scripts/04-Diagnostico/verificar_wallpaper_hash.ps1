# scripts/03-Deploy-Massa/verificar_wallpaper_hash.ps1
# Script para verificar se a imagem transcoficada pelo Windows (TranscodedWallpaper) bate com o Hash SHA-256 do nosso Wallpaper oficial

$wallpaperLocal = "$PSScriptRoot\..\Recursos\wallpaper-fafar.png"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser = New-Object System.Management.Automation.PSCredential("User", $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

if (-not (Test-Path $wallpaperLocal)) {
    Write-Error "Arquivo de wallpaper local não encontrado em $wallpaperLocal"
    exit
}

# Calcula o Hash SHA-256 do Wallpaper de Origem
$originHash = (Get-FileHash -Path $wallpaperLocal -Algorithm SHA256).Hash
Write-Host ">>> Hash SHA-256 de Origem: $originHash" -ForegroundColor Green

Write-Host "`n>>> [FASE 1] Detectando sub-redes ativas e escaneando laboratório..." -ForegroundColor Cyan

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

$onlineHosts = @()
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

Write-Host "`n>>> [FASE 2] Conectando nos $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

$sessionsUser = New-PSSession -ComputerName $onlineHosts -Credential $credUser -ErrorAction SilentlyContinue
$activeSessionsUser = $sessionsUser | Where-Object { $_.State -eq 'Opened' }

$connectedHosts = $activeSessionsUser | ForEach-Object { $_.ComputerName }
$remainingHosts = $onlineHosts | Where-Object { $_ -notin $connectedHosts }

$activeSessionsAdmin = @()
$sessionsAdmin = @()
if ($remainingHosts) {
    Write-Host "   -> Tentando conectar em $($remainingHosts.Count) PCs restantes usando usuário 'admin'..." -ForegroundColor Yellow
    $sessionsAdmin = New-PSSession -ComputerName $remainingHosts -Credential $credAdmin -ErrorAction SilentlyContinue
    $activeSessionsAdmin = $sessionsAdmin | Where-Object { $_.State -eq 'Opened' }
}

$activeSessions = $activeSessionsUser + $activeSessionsAdmin

if (-not $activeSessions) {
    Write-Error "Não foi possível abrir nenhuma sessão válida."
    exit
}

Write-Host "`n>>> [FASE 3] Teste Matemático de Integridade (Hash SHA-256 do Wallpaper Transcodificado)..." -ForegroundColor Cyan
Write-Host "------------------------------------------------------------------------------------------------"
Write-Host ("{0,-18} | {1,-12} | {2,-15} | {3}" -f "Endereço IP", "Usuário", "Status de Hash", "Diferença/Detalhe")
Write-Host "------------------------------------------------------------------------------------------------"

foreach ($session in $activeSessions) {
    $ip = $session.ComputerName
    try {
        $results = Invoke-Command -Session $session -ScriptBlock {
            param($targetHash)
            # Busca SIDs de usuários reais ativos sob HKEY_USERS
            $userSids = Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' }
            $outputs = @()
            
            foreach ($sidKey in $userSids) {
                $sid = $sidKey.PSChildName
                $profilePath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profilePath -and $profilePath -notlike "*SystemProfile*" -and $profilePath -notlike "*LocalService*" -and $profilePath -notlike "*NetworkService*") {
                    $username = Split-Path $profilePath -Leaf
                    $transcodedPath = "$profilePath\AppData\Roaming\Microsoft\Windows\Themes\TranscodedWallpaper"
                    
                    if (Test-Path $transcodedPath) {
                        # Calcula hash do wallpaper atualmente renderizado na tela do usuário
                        $currentHash = (Get-FileHash -Path $transcodedPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                        if ($currentHash -eq $targetHash) {
                            $outputs += "$username=INTEGRO"
                        } else {
                            $outputs += "$username=DIFERENTE (Outro Wallpaper)"
                        }
                    } else {
                        $outputs += "$username=SEM_WALLPAPER (Nunca configurado nesta conta)"
                    }
                }
            }
            if ($outputs.Count -eq 0) {
                return "Nenhum usuário logado"
            }
            return $outputs -join "; "
        } -ArgumentList $originHash -ErrorAction Stop
        
        # Formata o output
        $results -split "; " | ForEach-Object {
            if ($_ -match '^([^=]+)=(.+)$') {
                $user = $Matches[1]
                $status = $Matches[2]
                $detail = ""
                if ($status -eq "INTEGRO") {
                    $detail = "O Wallpaper renderizado na tela coincide 100% com o arquivo original."
                } elseif ($status -eq "DIFERENTE (Outro Wallpaper)") {
                    $detail = "A conta possui outro wallpaper ativo."
                } else {
                    $detail = "O Windows ainda não renderizou nenhum wallpaper para esta conta."
                }
                Write-Host ("{0,-18} | {1,-12} | {2,-15} | {3}" -f $ip, $user, $status, $detail)
            } else {
                Write-Host ("{0,-18} | {1}" -f $ip, $_)
            }
        }
    } catch {
        Write-Host ("{0,-18} | ERRO: {1}" -f $ip, $_.Exception.Message) -ForegroundColor Red
    }
}

if ($sessionsUser) { Remove-PSSession $sessionsUser -ErrorAction SilentlyContinue }
if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }
Write-Host "------------------------------------------------------------------------------------------------"

# scripts/03-Deploy-Massa/verificar_wallpaper.ps1
# Script para verificar qual papel de parede está configurado na sessão ativa de cada computador do laboratório

$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser = New-Object System.Management.Automation.PSCredential("User", $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

Write-Host ">>> [FASE 1] Detectando sub-redes ativas e escaneando laboratório..." -ForegroundColor Cyan

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

Write-Host "`n>>> [FASE 3] Verificando Papel de Parede registrado nos PCs..." -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------------"
Write-Host ("{0,-18} | {1}" -f "Endereço IP", "Usuário=Caminho do Wallpaper")
Write-Host "----------------------------------------------------------------------"

foreach ($session in $activeSessions) {
    $ip = $session.ComputerName
    try {
        $result = Invoke-Command -Session $session -ScriptBlock {
            # Busca SIDs de usuários reais ativos sob HKEY_USERS
            $userSids = Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' }
            $userWallpapers = @()
            
            foreach ($sidKey in $userSids) {
                $sid = $sidKey.PSChildName
                $profilePath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).ProfileImagePath
                if ($profilePath -and $profilePath -notlike "*SystemProfile*" -and $profilePath -notlike "*LocalService*" -and $profilePath -notlike "*NetworkService*") {
                    $username = Split-Path $profilePath -Leaf
                    $wallpaper = (Get-ItemProperty -Path "Registry::HKEY_USERS\$sid\Control Panel\Desktop" -Name "Wallpaper" -ErrorAction SilentlyContinue).Wallpaper
                    if (-not $wallpaper) { $wallpaper = "(Não configurado)" }
                    $userWallpapers += "$username=$wallpaper"
                }
            }
            if ($userWallpapers.Count -eq 0) {
                return "Nenhum usuário logado"
            }
            return $userWallpapers -join "; "
        } -ErrorAction Stop
        
        Write-Host ("{0,-18} | {1}" -f $ip, $result)
    } catch {
        Write-Host ("{0,-18} | ERRO: {1}" -f $ip, $_.Exception.Message) -ForegroundColor Red
    }
}

if ($sessionsUser) { Remove-PSSession $sessionsUser -ErrorAction SilentlyContinue }
if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }
Write-Host "----------------------------------------------------------------------"

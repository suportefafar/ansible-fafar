# scripts/03-Deploy-Massa/forcar_sincronizacao_hora.ps1
# Forca a execucao imediata da tarefa de sincronizacao de hora (SyncTimeAtLogon)
# em todas as maquinas do laboratorio.
#
# As sub-redes sao auto-detectadas (padrao do projeto) - nao ha IPs hardcoded.
# Maquinas que ainda nao receberam a tarefa (deploy nao rodado) sao reportadas
# claramente, em vez de gerar erro silencioso.

$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser  = New-Object System.Management.Automation.PSCredential("User", $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

Write-Host ">>> [FASE 1] Detectando sub-redes ativas e escaneando laboratório..." -ForegroundColor Cyan

# Detecta sub-redes IPv4 ativas (desconsiderando loopback, link-local e interfaces virtuais)
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
    exit
}

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

Write-Host "`n>>> [FASE 2] Disparando SyncTimeAtLogon em $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

# Abre sessoes: tenta "User" primeiro, depois "admin" nas que falharem
$sessionsUser = New-PSSession -ComputerName $onlineHosts -Credential $credUser -ErrorAction SilentlyContinue
$activeSessionsUser = $sessionsUser | Where-Object { $_.State -eq 'Opened' }

$connectedHosts = $activeSessionsUser | ForEach-Object { $_.ComputerName }
$remainingHosts = $onlineHosts | Where-Object { $_ -notin $connectedHosts }

$sessionsAdmin = @()
$activeSessionsAdmin = @()
if ($remainingHosts) {
    $sessionsAdmin = New-PSSession -ComputerName $remainingHosts -Credential $credAdmin -ErrorAction SilentlyContinue
    $activeSessionsAdmin = $sessionsAdmin | Where-Object { $_.State -eq 'Opened' }
}

$activeSessions = @($activeSessionsUser) + @($activeSessionsAdmin)

$okCount      = 0
$semTaskCount = 0
$erroCount    = 0

foreach ($session in $activeSessions) {
    $ip = $session.ComputerName
    try {
        # Verifica se a tarefa existe antes de dispara-la; evita erro silencioso
        $res = Invoke-Command -Session $session -ScriptBlock {
            $t = Get-ScheduledTask -TaskName "SyncTimeAtLogon" -ErrorAction SilentlyContinue
            if (-not $t) { return "SEM_TASK" }
            Start-ScheduledTask -TaskName "SyncTimeAtLogon"
            return "OK"
        } -ErrorAction Stop

        if ($res -eq "SEM_TASK") {
            Write-Host "   [!] ${ip}: tarefa 'SyncTimeAtLogon' nao instalada (rode o deploy primeiro)." -ForegroundColor Yellow
            $semTaskCount++
        } else {
            Write-Host "   [OK] Disparado em: $ip" -ForegroundColor Green
            $okCount++
        }
    } catch {
        Write-Host "   [ERRO] ${ip}: $($_.Exception.Message)" -ForegroundColor Red
        $erroCount++
    }
}

# Maquinas ligadas porem sem sessao WinRM valida (nao autenticaram)
$comSessao = $activeSessions | ForEach-Object { $_.ComputerName }
$semAuth = @($onlineHosts | Where-Object { $_ -notin $comSessao })
foreach ($ip in $semAuth) {
    Write-Host "   [ERRO] ${ip}: nao autenticou (User/admin)." -ForegroundColor Red
}

if ($sessionsUser)  { Remove-PSSession $sessionsUser  -ErrorAction SilentlyContinue }
if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }

Write-Host "`n==================== RESUMO ====================" -ForegroundColor Cyan
Write-Host "Maquinas ligadas (WinRM)      : $($onlineHosts.Count)" -ForegroundColor White
Write-Host "Sincronizacao disparada       : $okCount" -ForegroundColor Green
Write-Host "Sem a tarefa instalada        : $semTaskCount" -ForegroundColor Yellow
Write-Host "Falha de execucao             : $erroCount" -ForegroundColor Yellow
Write-Host "Sem autenticacao              : $($semAuth.Count)" -ForegroundColor Yellow
Write-Host "===============================================" -ForegroundColor Cyan

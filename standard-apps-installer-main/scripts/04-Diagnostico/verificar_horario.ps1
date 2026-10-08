# scripts/04-Diagnostico/verificar_horario.ps1
# Lista as maquinas ligadas (WinRM ativo) e verifica quantas estao com o horario correto.
# O "horario correto" e definido pela comparacao com o relogio do proprio Host que roda este script.
# Uso:
#   .\scripts\04-Diagnostico\verificar_horario.ps1                 # tolerancia padrao de 60s
#   .\scripts\04-Diagnostico\verificar_horario.ps1 -ToleranciaSeg 10

param(
    [int]$ToleranciaSeg = 60
)

$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser  = New-Object System.Management.Automation.PSCredential("User", $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

$onlineHosts = @()
Write-Host ">>> [FASE 1] Detectando sub-redes ativas e escaneando laboratorio..." -ForegroundColor Cyan

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

Write-Host "`n>>> [FASE 2] Verificando horario em $($onlineHosts.Count) PCs (tolerancia: ${ToleranciaSeg}s)..." -ForegroundColor Cyan

# Abre sessoes: tenta "User" primeiro, depois "admin" nas que falharem
$sessionsUser = New-PSSession -ComputerName $onlineHosts -Credential $credUser -ErrorAction SilentlyContinue
$activeSessionsUser = $sessionsUser | Where-Object { $_.State -eq 'Opened' }

$connectedHosts = $activeSessionsUser | ForEach-Object { $_.ComputerName }
$remainingHosts = $onlineHosts | Where-Object { $_ -notin $connectedHosts }

$activeSessionsAdmin = @()
$sessionsAdmin = @()
if ($remainingHosts) {
    $sessionsAdmin = New-PSSession -ComputerName $remainingHosts -Credential $credAdmin -ErrorAction SilentlyContinue
    $activeSessionsAdmin = $sessionsAdmin | Where-Object { $_.State -eq 'Opened' }
}

$activeSessions = @($activeSessionsUser) + @($activeSessionsAdmin)
$resultados = @()

foreach ($session in $activeSessions) {
    $ip = $session.ComputerName
    try {
        # Captura a hora do Host imediatamente antes da chamada remota (referencia de "hora correta")
        $horaHost = Get-Date
        $horaRemota = Invoke-Command -Session $session -ScriptBlock { Get-Date } -ErrorAction Stop
        $diff = [math]::Abs(($horaRemota - $horaHost).TotalSeconds)
        $ok = $diff -le $ToleranciaSeg
        $resultados += [pscustomobject]@{
            IP          = $ip
            HoraMaquina = $horaRemota.ToString("yyyy-MM-dd HH:mm:ss")
            DiffSeg     = [math]::Round($diff, 1)
            Status      = if ($ok) { "CORRETO" } else { "DIVERGENTE" }
            Correto     = $ok
        }
    } catch {
        $resultados += [pscustomobject]@{
            IP          = $ip
            HoraMaquina = "ERRO"
            DiffSeg     = $null
            Status      = "SEM RESPOSTA"
            Correto     = $false
        }
    }
}

# Inclui as maquinas ligadas porem sem sessao WinRM valida (nao autenticaram)
$comSessao = $activeSessions | ForEach-Object { $_.ComputerName }
foreach ($ip in $onlineHosts) {
    if ($ip -notin $comSessao) {
        $resultados += [pscustomobject]@{
            IP          = $ip
            HoraMaquina = "ERRO"
            DiffSeg     = $null
            Status      = "SEM AUTENTICACAO"
            Correto     = $false
        }
    }
}

if ($sessionsUser)  { Remove-PSSession $sessionsUser  -ErrorAction SilentlyContinue }
if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }

# Relatorio
Write-Host "`n==================== RELATORIO DE HORARIO ====================" -ForegroundColor Cyan
$resultados | Sort-Object IP | Format-Table IP, HoraMaquina, DiffSeg, Status -AutoSize

$ligadas    = $onlineHosts.Count
$verificadas = ($resultados | Where-Object { $_.HoraMaquina -ne "ERRO" }).Count
$corretas   = ($resultados | Where-Object { $_.Correto }).Count

Write-Host "--------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Maquinas ligadas (WinRM ativo) : $ligadas" -ForegroundColor White
Write-Host "Verificadas com sucesso        : $verificadas" -ForegroundColor White
Write-Host "Com horario CORRETO            : $corretas  (tolerancia ${ToleranciaSeg}s)" -ForegroundColor Green
Write-Host "Com horario DIVERGENTE/ERRO    : $($ligadas - $corretas)" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Cyan

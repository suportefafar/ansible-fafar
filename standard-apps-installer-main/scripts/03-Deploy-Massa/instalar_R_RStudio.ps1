# scripts/03-Deploy-Massa/instalar_R_RStudio.ps1
# Deploy massivo de R e RStudio para o laboratorio via Chocolatey

$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$credUser  = New-Object System.Management.Automation.PSCredential("User",  $senha)
$credAdmin = New-Object System.Management.Automation.PSCredential("admin", $senha)

# FASE 1: Detectar sub-redes ativas e escanear laboratorio
$onlineHosts = @()
Write-Host ">>> [FASE 1] Detectando sub-redes e escaneando laboratorio..." -ForegroundColor Cyan

$interfaces = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notlike "127.*" -and
    $_.IPAddress -notlike "169.254.*" -and
    $_.InterfaceAlias -notlike "*VirtualBox*" -and
    $_.InterfaceAlias -notlike "*VMware*" -and
    $_.InterfaceAlias -notlike "*vEthernet*"
}

$subnets = @()
foreach ($iface in $interfaces) {
    if ($iface.IPAddress -match '^(\d+\.\d+\.\d+)\.\d+$') {
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

Write-Host "`n>>> [FASE 2] Conectando nos $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

# FASE 2: Abrir sessoes com dupla credencial
$sessionsUser = New-PSSession -ComputerName $onlineHosts -Credential $credUser -ErrorAction SilentlyContinue
$activeSessionsUser = @($sessionsUser | Where-Object { $_.State -eq 'Opened' })

$connectedHosts = $activeSessionsUser | ForEach-Object { $_.ComputerName }
$remainingHosts = $onlineHosts | Where-Object { $_ -notin $connectedHosts }

$activeSessionsAdmin = @()
$sessionsAdmin = @()
if ($remainingHosts.Count -gt 0) {
    Write-Host "   -> Tentando 'admin' em $($remainingHosts.Count) PCs restantes..." -ForegroundColor Yellow
    $sessionsAdmin = New-PSSession -ComputerName $remainingHosts -Credential $credAdmin -ErrorAction SilentlyContinue
    $activeSessionsAdmin = @($sessionsAdmin | Where-Object { $_.State -eq 'Opened' })
}

$activeSessions = $activeSessionsUser + $activeSessionsAdmin

if ($activeSessions.Count -eq 0) {
    Write-Error "Nao foi possivel abrir nenhuma sessao valida."
    exit
}

Write-Host "   -> $($activeSessions.Count) sessoes abertas com sucesso." -ForegroundColor Green

# FASE 3: Instalar R e RStudio em cada PC
Write-Host "`n>>> [FASE 3] Instalando R e RStudio em cada PC..." -ForegroundColor Cyan
Write-Host "-------------------------------------------------------------------"

$resultados = @()

foreach ($session in $activeSessions) {
    $ip = $session.ComputerName
    Write-Host "`n   [>] Processando: $ip ..." -ForegroundColor Cyan

    try {
        $result = Invoke-Command -Session $session -ErrorAction Stop -ScriptBlock {
            $log = [System.Collections.ArrayList]@()

            # 1. Garantir que Chocolatey esta instalado
            $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
            if (-not $chocoCmd) {
                $null = $log.Add("Chocolatey nao encontrado. Instalando...")
                try {
                    Set-ExecutionPolicy Bypass -Scope Process -Force
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                    $null = $log.Add("Chocolatey instalado com sucesso.")
                } catch {
                    $null = $log.Add("ERRO ao instalar Chocolatey: " + $_.Exception.Message)
                    return ($log -join "`n")
                }
            } else {
                $chocoVer = & choco --version 2>&1
                $null = $log.Add("Chocolatey ja instalado: $chocoVer")
            }

            # Recarrega PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

            # 2. Instalar R (verificando se ja existe)
            $rCmd = Get-Command Rscript -ErrorAction SilentlyContinue
            if ($rCmd) {
                $null = $log.Add("R ja instalado - pulando.")
            } else {
                $null = $log.Add("Instalando R (linguagem de programacao)...")
                $chocoOut = & choco install r.project -y --no-progress --limit-output --ignore-checksums 2>&1
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010) {
                    $null = $log.Add("R instalado com sucesso. (exit: $LASTEXITCODE)")
                } else {
                    $null = $log.Add("ERRO ao instalar R (exit: $LASTEXITCODE) - $chocoOut")
                }
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            }

            # 3. Instalar RStudio (verificando se ja existe)
            $rstudioExe1 = "C:\Program Files\RStudio\bin\rstudio.exe"
            $rstudioExe2 = "C:\Program Files\RStudio\rstudio.exe"
            if ((Test-Path $rstudioExe1) -or (Test-Path $rstudioExe2)) {
                $null = $log.Add("RStudio ja instalado - pulando.")
            } else {
                $null = $log.Add("Instalando RStudio (IDE)...")
                $chocoOut = & choco install r.studio -y --no-progress --limit-output --ignore-checksums 2>&1
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010) {
                    $null = $log.Add("RStudio instalado com sucesso. (exit: $LASTEXITCODE)")
                } else {
                    $null = $log.Add("ERRO ao instalar RStudio (exit: $LASTEXITCODE) - $chocoOut")
                }
            }

            return ($log -join "`n")
        }

        Write-Host $result -ForegroundColor White
        $resultados += [PSCustomObject]@{ IP = $ip; Status = "OK"; Detalhes = $result }
        Write-Host "   [+] $ip - Concluido!" -ForegroundColor Green

    } catch {
        $msg = $_.Exception.Message
        Write-Warning "   [-] Falha no PC $ip : $msg"
        $resultados += [PSCustomObject]@{ IP = $ip; Status = "ERRO"; Detalhes = $msg }
    }
}

# FASE 4: Relatorio Final
Write-Host "`n>>> [FASE 4] Relatorio Final" -ForegroundColor Cyan
Write-Host "==================================================================="
$ok    = @($resultados | Where-Object { $_.Status -eq "OK" })
$erros = @($resultados | Where-Object { $_.Status -eq "ERRO" })
Write-Host "   Sucesso : $($ok.Count) PCs" -ForegroundColor Green

if ($erros.Count -gt 0) {
    Write-Host "   Falhas  : $($erros.Count) PCs" -ForegroundColor Red
    Write-Host "`n   PCs com falha:" -ForegroundColor Red
    foreach ($e in $erros) {
        Write-Host "   - $($e.IP): $($e.Detalhes)" -ForegroundColor Red
    }
} else {
    Write-Host "   Falhas  : 0 PCs" -ForegroundColor Green
}

Write-Host "==================================================================="
Write-Host ">>> DEPLOY DE R e RSTUDIO FINALIZADO!" -ForegroundColor Cyan

if ($sessionsUser)  { Remove-PSSession $sessionsUser  -ErrorAction SilentlyContinue }
if ($sessionsAdmin) { Remove-PSSession $sessionsAdmin -ErrorAction SilentlyContinue }

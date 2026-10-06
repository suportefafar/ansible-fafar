# scripts/03-Deploy-Massa/remover_atalho_epi_funcionando.ps1
# Remove PARALELO o atalho antigo "EPI - Funcionando.lnk" da Area de Trabalho publica
# e de todos os perfis, em todas as maquinas ativas da rede (via WinRM).
# PCs que nao respondem sao abandonados por timeout.

param(
    [string]$NomeAtalho = "EPI - Funcionando.lnk"
)

# --- FASE 1: Descobrir PCs com WinRM ativo ---
Write-Host ">>> [FASE 1] Escaneando rede na porta WinRM 5985 (paralelo)..." -ForegroundColor Cyan

$subnets = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -notlike "127.*" -and
    $_.IPAddress -notlike "169.254.*" -and
    $_.InterfaceAlias -notlike "*VirtualBox*" -and
    $_.InterfaceAlias -notlike "*VMware*" -and
    $_.InterfaceAlias -notlike "*vEthernet*"
} | ForEach-Object {
    if ($_.IPAddress -match '^(\d+\.\d+\.\d+)\.\d+$') { $Matches[1] }
} | Select-Object -Unique

$tentativas = foreach ($subnet in $subnets) {
    foreach ($i in 1..254) {
        $ip = "$subnet.$i"
        $tcp = New-Object System.Net.Sockets.TcpClient
        [pscustomobject]@{ Ip = $ip; Tcp = $tcp; Async = $tcp.BeginConnect($ip, 5985, $null, $null) }
    }
}
Start-Sleep -Milliseconds 1500

$onlineHosts = @()
foreach ($t in $tentativas) {
    if ($t.Async.IsCompleted -and $t.Tcp.Connected) { $onlineHosts += $t.Ip }
    $t.Tcp.Close()
}

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum PC com WinRM ativo foi encontrado."
    exit 1
}
Write-Host "   [+] $($onlineHosts.Count) PCs encontrados" -ForegroundColor Green

# --- FASE 2: Remover atalho em todos ao mesmo tempo (User, depois admin) ---
Write-Host "`n>>> [FASE 2] Removendo '$NomeAtalho' em paralelo..." -ForegroundColor Cyan

$remover = {
    param($nome)
    $alvos = @("C:\Users\Public\Desktop\$nome")
    Get-ChildItem "C:\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $alvos += Join-Path $_.FullName "Desktop\$nome"
        Get-ChildItem $_.FullName -Directory -Filter "OneDrive*" -ErrorAction SilentlyContinue | ForEach-Object {
            $alvos += Join-Path $_.FullName "Desktop\$nome"
        }
    }
    $removidos = 0
    foreach ($a in $alvos) {
        if (Test-Path -LiteralPath $a) {
            Remove-Item -LiteralPath $a -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $a)) { $removidos++ }
        }
    }
    [pscustomobject]@{ Removidos = $removidos }
}

$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 60000 -CancelTimeout 5000

$resultados = @()
$restantes = $onlineHosts
foreach ($usuario in "User", "admin") {
    if (-not $restantes) { break }
    $cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)
    $r = Invoke-Command -ComputerName $restantes -Credential $cred -SessionOption $opt -ThrottleLimit 64 `
        -ScriptBlock $remover -ArgumentList $NomeAtalho -ErrorAction SilentlyContinue
    foreach ($x in $r) {
        $msg = if ($x.Removidos -gt 0) { "removido ($($x.Removidos))" } else { "nao existia" }
        Write-Host "   [+] $($x.PSComputerName): $msg" -ForegroundColor Green
    }
    $resultados += $r
    $restantes = $restantes | Where-Object { $_ -notin $r.PSComputerName }
}

foreach ($ip in $restantes) {
    Write-Host "   [-] $($ip): sem sessao / nao respondeu" -ForegroundColor Red
}

Write-Host "`n>>> RESUMO" -ForegroundColor Cyan
Write-Host "   OK:    $(@($resultados).Count) (atalho removido em $(@($resultados | Where-Object { $_.Removidos -gt 0 }).Count))" -ForegroundColor Green
Write-Host "   Falha: $(@($restantes).Count) $($restantes -join ', ')" -ForegroundColor Red

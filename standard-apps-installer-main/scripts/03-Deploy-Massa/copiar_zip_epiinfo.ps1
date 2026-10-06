# scripts/03-Deploy-Massa/copiar_zip_epiinfo.ps1
# Deploy PARALELO: copia apps\Epi_Info_7.zip para todas as maquinas ativas da rede (via WinRM),
# extrai em <Destino>\Epi_Info_7 e cria o atalho "EPI - Definitivo" na Area de Trabalho publica
# apontando para "Launch Epi Info 7.exe".
# Destino padrao: C:\Users\Public\Downloads

param(
    [string]$Destino = "C:\Users\Public\Downloads",
    [int]$MaxParalelo = 64,
    [int]$TimeoutSeg = 300   # tempo maximo total do deploy; PCs que passarem disso sao abandonados
)

$localZip = (Resolve-Path "$PSScriptRoot\..\..\apps\Epi_Info_7.zip" -ErrorAction SilentlyContinue).Path
if (-not $localZip) {
    Write-Error "Arquivo nao encontrado: $PSScriptRoot\..\..\apps\Epi_Info_7.zip"
    exit 1
}

# --- FASE 1: Descobrir PCs com WinRM ativo (todos os IPs testados ao mesmo tempo) ---
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
    Write-Host " -> Sub-rede: $subnet.0/24" -ForegroundColor Yellow
    foreach ($i in 1..254) {
        $ip = "$subnet.$i"
        $tcp = New-Object System.Net.Sockets.TcpClient
        [pscustomobject]@{ Ip = $ip; Tcp = $tcp; Async = $tcp.BeginConnect($ip, 5985, $null, $null) }
    }
}

Start-Sleep -Milliseconds 1500

$onlineHosts = @()
foreach ($t in $tentativas) {
    if ($t.Async.IsCompleted -and $t.Tcp.Connected) {
        Write-Host "   [+] WinRM ativo em: $($t.Ip)" -ForegroundColor Green
        $onlineHosts += $t.Ip
    }
    $t.Tcp.Close()
}

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum PC com WinRM ativo foi encontrado."
    exit 1
}

# --- FASE 2: Copiar, extrair e criar atalho em TODOS os PCs ao mesmo tempo ---
Write-Host "`n>>> [FASE 2] Deploy simultaneo em $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

# Executado em cada PC (remoto): verifica o que ja existe
$verificar = {
    param($dir, $zipName)
    $extractDir = Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($zipName))
    $launcher = Join-Path $extractDir "Launch Epi Info 7.exe"
    $atalho = "C:\Users\Public\Desktop\EPI - Definitivo.lnk"

    $temPasta = (Test-Path $launcher) -and (Test-Path (Join-Path $extractDir "Epi Info 7\EpiInfo.exe"))
    $temAtalho = $false
    if (Test-Path $atalho) {
        $temAtalho = (New-Object -ComObject WScript.Shell).CreateShortcut($atalho).TargetPath -eq $launcher
    }
    [pscustomobject]@{ TemPasta = $temPasta; TemAtalho = $temAtalho }
}

# Executado em cada PC (remoto): extrai (se preciso) e cria o atalho
$remoto = {
    param($dir, $zipName, $extrair)

    $zipPath = Join-Path $dir $zipName
    $extractDir = Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($zipName))

    if ($extrair) {
        # Fecha o Epi Info se estiver aberto, para nao travar arquivos
        "EpiInfo", "Enter", "Analysis", "AnalysisDashboard", "MakeView", "Menu", "StatCalc", "Mapping", "Launch Epi Info 7" |
            ForEach-Object { Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue }

        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # Permissao total para Usuarios, para rodar sem senha de admin
        & "$env:SystemRoot\System32\icacls.exe" $extractDir /grant "*S-1-5-32-545:(OI)(CI)F" /T /C /Q | Out-Null
    }

    $launcher = Join-Path $extractDir "Launch Epi Info 7.exe"
    if (-not (Test-Path $launcher)) { throw "launcher nao encontrado em $extractDir" }

    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut("C:\Users\Public\Desktop\EPI - Definitivo.lnk")
    $sc.TargetPath = $launcher
    $sc.WorkingDirectory = $extractDir
    $sc.IconLocation = "$extractDir\Epi Info 7\EpiInfo.exe,0"
    $sc.Description = "Epi Info 7"
    $sc.Save()
}

# Executado localmente, um por PC, em paralelo
$porHost = {
    param($ip, $localZip, $dir, $remoto, $verificar)

    $senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
    # Nao fica preso em PC que nao responde
    $opt = New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 180000 -CancelTimeout 5000
    $sessao = $null
    foreach ($usuario in "User", "admin") {
        $cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)
        $sessao = New-PSSession -ComputerName $ip -Credential $cred -SessionOption $opt -ErrorAction SilentlyContinue
        if ($sessao) { break }
    }
    if (-not $sessao) { return [pscustomobject]@{ Ip = $ip; Ok = $false; Msg = "sem sessao (User/admin)" } }

    try {
        $zipName = Split-Path $localZip -Leaf
        $estado = Invoke-Command -Session $sessao -ScriptBlock ([scriptblock]::Create($verificar)) -ArgumentList $dir, $zipName -ErrorAction Stop

        if ($estado.TemPasta -and $estado.TemAtalho) {
            return [pscustomobject]@{ Ip = $ip; Ok = $true; Msg = "ja tinha pasta e atalho - pulado" }
        }

        if (-not $estado.TemPasta) {
            Invoke-Command -Session $sessao -ScriptBlock {
                param($d) if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
            } -ArgumentList $dir -ErrorAction Stop
            Copy-Item -Path $localZip -Destination (Join-Path $dir $zipName) -ToSession $sessao -Force -ErrorAction Stop
        }
        Invoke-Command -Session $sessao -ScriptBlock ([scriptblock]::Create($remoto)) -ArgumentList $dir, $zipName, (-not $estado.TemPasta) -ErrorAction Stop

        $msg = if ($estado.TemPasta) { "pasta ja existia - so criou o atalho" } else { "copiado + atalho 'EPI - Definitivo' criado" }
        [pscustomobject]@{ Ip = $ip; Ok = $true; Msg = $msg }
    } catch {
        [pscustomobject]@{ Ip = $ip; Ok = $false; Msg = $_.Exception.Message }
    } finally {
        Remove-PSSession $sessao -ErrorAction SilentlyContinue
    }
}

$pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxParalelo)
$pool.Open()

$pendentes = [System.Collections.ArrayList]@(foreach ($ip in $onlineHosts) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($porHost).AddArgument($ip).AddArgument($localZip).AddArgument($Destino).AddArgument($remoto.ToString()).AddArgument($verificar.ToString())
    [pscustomobject]@{ Ip = $ip; Ps = $ps; Handle = $ps.BeginInvoke() }
})

# Mostra cada PC assim que termina; abandona os que passarem do timeout
$total = $pendentes.Count
$prazo = (Get-Date).AddSeconds($TimeoutSeg)
$resultados = @()
while ($pendentes.Count -gt 0 -and (Get-Date) -lt $prazo) {
    foreach ($j in @($pendentes | Where-Object { $_.Handle.IsCompleted })) {
        $x = $j.Ps.EndInvoke($j.Handle) | Select-Object -First 1
        if (-not $x) { $x = [pscustomobject]@{ Ip = $j.Ip; Ok = $false; Msg = "sem retorno" } }
        $j.Ps.Dispose()
        $pendentes.Remove($j)
        $resultados += $x
        $cor = if ($x.Ok) { "Green" } else { "Red" }
        $sinal = if ($x.Ok) { "+" } else { "-" }
        Write-Host "   [$sinal] ($($resultados.Count)/$total) $($x.Ip): $($x.Msg)" -ForegroundColor $cor
    }
    Start-Sleep -Milliseconds 500
}

foreach ($j in $pendentes) {
    Write-Host "   [-] $($j.Ip): TIMEOUT (nao respondeu em $TimeoutSeg s) - abandonado" -ForegroundColor Red
    $resultados += [pscustomobject]@{ Ip = $j.Ip; Ok = $false; Msg = "timeout" }
    [void]$j.Ps.BeginStop($null, $null)
}

# Nao espera os abandonados fecharem
if ($pendentes.Count -eq 0) { $pool.Close(); $pool.Dispose() }

$ok = @($resultados | Where-Object Ok)
$falha = @($resultados | Where-Object { -not $_.Ok })

Write-Host "`n>>> RESUMO" -ForegroundColor Cyan
Write-Host "   Sucesso: $($ok.Count)" -ForegroundColor Green
Write-Host "   Falha:   $($falha.Count) $($falha.Ip -join ', ')" -ForegroundColor Red

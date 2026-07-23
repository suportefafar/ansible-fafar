# scripts/disparar_deploy_laboratorio_turbo.ps1
# Scanner de porta 5985 (WinRM) para encontrar alvos instantaneamente

$zipLocal = "$PSScriptRoot\sync-datetime.zip"
$usuario = "user"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)

$onlineHosts = @()
Write-Host ">>> [FASE 1] Escaneando laboratório via Porta 5985 (WinRM)..." -ForegroundColor Cyan

1..253 | ForEach-Object {
    $ip = "192.168.137.$_"
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connect = $tcp.BeginConnect($ip, 5985, $null, $null)
    
    # Espera apenas 100ms por IP (Super rápido!)
    if ($connect.AsyncWaitHandle.WaitOne(100)) {
        if ($tcp.Connected) {
            Write-Host "   [+] WinRM Ativo em: $ip" -ForegroundColor Green
            $onlineHosts += $ip
        }
    }
    $tcp.Close()
}

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum PC com WinRM ativo foi encontrado na rede 192.168.137.x"
    exit
}

Write-Host "`n>>> [FASE 2] Iniciando Deploy nos $($onlineHosts.Count) PCs encontrados..." -ForegroundColor Cyan

foreach ($ip in $onlineHosts) {
    Write-Host "`n>>> Processando ${ip}..." -ForegroundColor Yellow
    try {
        $s = New-PSSession -ComputerName $ip -Credential $cred -ErrorAction Stop
        Copy-Item -Path $zipLocal -Destination "C:\Windows\Temp\sync-datetime.zip" -ToSession $s
        Invoke-Command -Session $s -ScriptBlock {
            if (Test-Path "C:\sync-datetime") { Remove-Item "C:\sync-datetime" -Recurse -Force }
            Expand-Archive -Path "C:\Windows\Temp\sync-datetime.zip" -DestinationPath "C:\sync-datetime" -Force
            $batFile = Get-ChildItem -Path "C:\sync-datetime" -Filter "scheduale-sync.bat" -Recurse | Select-Object -First 1
            if ($batFile) {
                Set-Location $batFile.DirectoryName
                .\scheduale-sync.bat
            }
        }
        Write-Host "   -> SUCESSO!" -ForegroundColor Green
        Remove-PSSession $s
    } catch {
        Write-Host "   -> ERRO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# scripts/disparar_deploy_laboratorio_veloz.ps1
# Versão ultra-rápida com Scan Paralelo

$zipLocal = "$PSScriptRoot\sync-datetime.zip"
$usuario = "User"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)

$ipsParaEscanear = 1..253 | ForEach-Object { "192.168.137.$_" }

Write-Host ">>> [FASE 1] Escaneando rede em PARALELO (Pinga tudo de uma vez)..." -ForegroundColor Cyan
$jobs = foreach ($ip in $ipsParaEscanear) {
    Test-Connection -ComputerName $ip -Count 1 -AsJob
}

# Espera os pings terminarem (timeout de 15 segundos)
$onlineHosts = $jobs | Wait-Job -Timeout 15 | Receive-Job | Where-Object { $_.Status -eq "Success" } | Select-Object -ExpandProperty Address -Unique

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum computador respondeu ao ping rápido."
    exit
}

Write-Host "`n>>> [FASE 2] PCs detectados: $($onlineHosts.Count)" -ForegroundColor Green
foreach ($h in $onlineHosts) { Write-Host "   -> $h" -ForegroundColor Green }

Write-Host "`n>>> Iniciando Deploy nos PCs detectados..." -ForegroundColor Cyan

foreach ($ip in $onlineHosts) {
    Write-Host "`n>>> Processando $ip..." -ForegroundColor Yellow
    try {
        $s = New-PSSession -ComputerName $ip -Credential $cred -Authentication Basic -ErrorAction Stop
        Copy-Item -Path $zipLocal -Destination "C:\Windows\Temp\sync-datetime.zip" -ToSession $s
        Invoke-Command -Session $s -ScriptBlock {
            if (Test-Path "C:\sync-datetime") { Remove-Item "C:\sync-datetime" -Recurse -Force }
            Expand-Archive -Path "C:\Windows\Temp\sync-datetime.zip" -DestinationPath "C:\" -Force
            $batFile = Get-ChildItem -Path "C:\sync-datetime" -Filter "scheduale-sync.bat" -Recurse | Select-Object -First 1
            if ($batFile) {
                Set-Location $batFile.DirectoryName
                .\scheduale-sync.bat
            }
        }
        Write-Host "   -> SUCESSO!" -ForegroundColor Green
        Remove-PSSession $s
    } catch {
        Write-Host "   -> FALHA em ${ip}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nDeploy finalizado!" -ForegroundColor Cyan

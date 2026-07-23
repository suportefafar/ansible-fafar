# scripts/disparar_deploy_laboratorio.ps1
# 1. Faz um ping rápido em toda a rede para identificar PCs ativos
# 2. Executa o deploy do sync-datetime.zip apenas nos PCs online

$zipLocal = "$PSScriptRoot\sync-datetime.zip"
$usuario = "User"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)

$ipsParaEscanear = 1..253 | ForEach-Object { "192.168.137.$_" }
$onlineHosts = @()

Write-Host ">>> [FASE 1] Escaneando a rede 192.168.137.x (Ping)..." -ForegroundColor Cyan
foreach ($ip in $ipsParaEscanear) {
    if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "   [V] PC detectado: $ip" -ForegroundColor Green
        $onlineHosts += $ip
    }
}

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum computador respondeu ao ping na rede 192.168.137.x"
    exit
}

Write-Host "`n>>> [FASE 2] Iniciando Deploy nos $($onlineHosts.Count) PCs detectados..." -ForegroundColor Cyan

foreach ($ip in $onlineHosts) {
    Write-Host "`n>>> Enviando para $ip..." -ForegroundColor Yellow
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
                Write-Host "   -> SUCESSO: Arquivos copiados e Schedule criado." -ForegroundColor Green
            } else {
                Write-Error "   -> ERRO: Arquivo .bat não encontrado dentro do ZIP."
            }
        }
        Remove-PSSession $s
    } catch {
        Write-Host "   -> FALHA ao conectar em ${ip}: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nProcesso de deploy em massa finalizado!" -ForegroundColor Cyan

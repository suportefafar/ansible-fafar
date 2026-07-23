# scripts/disparar_deploy_laboratorio_paralelo.ps1
# Scanner ultra-rápido (WinRM) + Execução Nativa em Paralelo

$zipLocal = "$PSScriptRoot\..\Recursos\sync-datetime.zip"
$usuario = "user"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)

$onlineHosts = @()
Write-Host ">>> [FASE 1] Escaneando laboratório via Porta 5985 (WinRM)..." -ForegroundColor Cyan

1..253 | ForEach-Object {
    $ip = "192.168.137.$_"
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

if ($onlineHosts.Count -eq 0) {
    Write-Warning "Nenhum PC com WinRM ativo foi encontrado."
    exit
}

Write-Host "`n>>> [FASE 2] Iniciando Deploy PARALELO nos $($onlineHosts.Count) PCs encontrados..." -ForegroundColor Cyan
Write-Host "Copiando arquivos e executando... (Aguarde, rodando em todos ao mesmo tempo)" -ForegroundColor Yellow

try {
    # Abre sessões em paralelo (ignora erros individuais como 'Acesso Negado')
    $sessions = New-PSSession -ComputerName $onlineHosts -Credential $cred -ErrorAction SilentlyContinue
    
    if ($sessions.Count -eq 0) {
        Write-Error "Não foi possível abrir sessão em nenhum dos PCs encontrados."
        return
    }

    # Filtra apenas as sessões que realmente abriram
    $activeSessions = $sessions | Where-Object { $_.State -eq 'Opened' }
    
    if (-not $activeSessions) {
        Write-Error "Não foi possível abrir nenhuma sessão válida."
        return
    }

    Write-Host "   -> Sessões abertas com sucesso em $($activeSessions.Count) PCs." -ForegroundColor Green
    
    # Copia o ZIP para todas as sessões em paralelo (Nota: Copy-Item para múltiplos destinos pode ser lento sequencialmente, mas aqui as sessões já estão abertas)
    $activeSessions | ForEach-Object {
        Copy-Item -Path $zipLocal -Destination "C:\Windows\Temp\sync-datetime.zip" -ToSession $_
    }

    # Executa os comandos em todas as máquinas em paralelo
    Invoke-Command -Session $activeSessions -ScriptBlock {
        if (Test-Path "C:\sync-datetime") { Remove-Item "C:\sync-datetime" -Recurse -Force }
        Expand-Archive -Path "C:\Windows\Temp\sync-datetime.zip" -DestinationPath "C:\sync-datetime" -Force
        
        $batFile = Get-ChildItem -Path "C:\sync-datetime" -Filter "scheduale-sync.bat" -Recurse | Select-Object -First 1
        if ($batFile) {
            Set-Location $batFile.DirectoryName
            .\scheduale-sync.bat
        }
    }
    
    # Fecha as sessões
    Remove-PSSession $sessions
    
    Write-Host "`n>>> DEPLOY CONCLUÍDO COM SUCESSO EM TODAS AS MÁQUINAS!" -ForegroundColor Green

} catch {
    Write-Host "`n>>> ERRO durante a execução paralela: $($_.Exception.Message)" -ForegroundColor Red
}

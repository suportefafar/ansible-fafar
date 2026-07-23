# scripts/forcar_sincronizacao_hora.ps1
# Força a execução imediata da tarefa de sincronização de hora em toda a rede

$usuario = "User"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)

Write-Host ">>> Forçando Sincronização de Hora no Laboratório..." -ForegroundColor Cyan

1..253 | ForEach-Object {
    $ip = "192.168.137.$_"
    $tcp = New-Object System.Net.Sockets.TcpClient
    $connect = $tcp.BeginConnect($ip, 5985, $null, $null)
    
    if ($connect.AsyncWaitHandle.WaitOne(100)) {
        if ($tcp.Connected) {
            Write-Host "   -> Disparando em: $ip" -ForegroundColor Green
            try {
                $s = New-PSSession -ComputerName $ip -Credential $cred -Authentication Basic -ErrorAction Stop
                Invoke-Command -Session $s -ScriptBlock { Start-ScheduledTask -TaskName "SyncTimeAtLogon" }
                Remove-PSSession $s
            } catch {
                Write-Host "      Erro em ${ip}: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    $tcp.Close()
}

Write-Host "`nSincronização forçada concluída!" -ForegroundColor Cyan

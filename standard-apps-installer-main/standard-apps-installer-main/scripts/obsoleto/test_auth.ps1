$ErrorActionPreference = "Stop"

$senhaText = "anjos2014"
$senha = $senhaText | ConvertTo-SecureString -AsPlainText -Force
$cred1 = New-Object System.Management.Automation.PSCredential("User", $senha)
$cred2 = New-Object System.Management.Automation.PSCredential("user", $senha)
$cred3 = New-Object System.Management.Automation.PSCredential(".\User", $senha)
$cred4 = New-Object System.Management.Automation.PSCredential(".\user", $senha)

$creds = @(
    @{ Name = "User"; Cred = $cred1 },
    @{ Name = "user"; Cred = $cred2 },
    @{ Name = ".\User"; Cred = $cred3 },
    @{ Name = ".\user"; Cred = $cred4 }
)

$targetIp = $null

Write-Host "Procurando um PC com WinRM ativo na rede 192.168.137.x..."
1..253 | ForEach-Object {
    if ($targetIp) { return }
    $ip = "192.168.137.$_"
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $tcp.BeginConnect($ip, 5985, $null, $null)
        if ($connect.AsyncWaitHandle.WaitOne(100)) {
            if ($tcp.Connected) {
                $targetIp = $ip
            }
        }
    } catch {} finally {
        $tcp.Close()
    }
}

if (-not $targetIp) {
    Write-Host "Nenhum PC encontrado na rede 192.168.137.x com porta 5985 aberta."
    exit
}

Write-Host "PC encontrado: $targetIp"
Write-Host "Iniciando testes de credenciais..."

foreach ($c in $creds) {
    Write-Host "`nTestando com usuario: $($c.Name)"
    try {
        $s = New-PSSession -ComputerName $targetIp -Credential $c.Cred -ErrorAction Stop
        Write-Host "[SUCESSO] Conectado com $($c.Name)!" -ForegroundColor Green
        Remove-PSSession $s
    } catch {
        Write-Host "[FALHA] $($_.Exception.Message)" -ForegroundColor Red
    }
}

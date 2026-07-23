# Script de configurações do sistema para Laboratórios
$ErrorActionPreference = 'Continue'

Write-Host "Iniciando otimizações de Laboratório..." -ForegroundColor Cyan

# 1. Ponto de Restauração
try {
    Write-Host "[1/8] Configurando ponto de restauração..." -ForegroundColor Yellow
    Enable-ComputerRestore -Drive "C:" -ErrorAction SilentlyContinue
    vssadmin resize shadowstorage /on=C: /for=C: /maxsize=5% 
} catch {
    Write-Warning "Não foi possível configurar o ponto de restauração."
}

# 2. Descoberta de Rede e Firewall
Write-Host "[2/8] Ativando descoberta de rede e regras de Firewall..." -ForegroundColor Yellow
netsh advfirewall firewall set rule group="Descoberta de Rede" new enable=yes
netsh advfirewall firewall set rule group="Compartilhamento de Arquivo e Impressora" new enable=yes
netsh advfirewall firewall add rule name="ICMP Allow incoming V4 echo request" protocol=icmpv4:8,any dir=in action=allow 2>$null

# 3. Habilitar Remote Desktop (RDP) para Gestão
Write-Host "[3/8] Habilitando Acesso Remoto (RDP)..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
# Usar o Nome interno (agnóstico a idioma) em vez do DisplayGroup
Get-NetFirewallRule -Name "RemoteDesktop*" | Enable-NetFirewallRule -ErrorAction SilentlyContinue

# 4. Plano de Energia: Alto Desempenho e Sem Sono/Hibernação
Write-Host "[4/8] Otimizando plano de energia (Alto Desempenho)..." -ForegroundColor Yellow
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c # High Performance
powercfg /hibernate off
powercfg /x -monitor-timeout-ac 0
powercfg /x -disk-timeout-ac 0
powercfg /x -standby-timeout-ac 0

# 5. Debloating: Remover Apps de Consumo Inúteis (Candy Crush, etc)
Write-Host "[5/8] Removendo bloatware do Windows..." -ForegroundColor Yellow
$appsToRemove = @(
    "*CandyCrush*", "*Disney*", "*Spotify*", "*Netflix*", "*Xbox*", 
    "*Twitter*", "*OneNote*", "*Skype*", "*OfficeHub*", "*FeedbackHub*"
)
foreach ($app in $appsToRemove) {
    Get-AppxPackage -Name $app -AllUsers | Remove-AppxPackage -ErrorAction SilentlyContinue
}
# Desativar "Consumer Features" (instalação automática de lixo)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -ErrorAction SilentlyContinue

# 6. Configurações de Região e Hora (Brasília)
Write-Host "[6/8] Configurando fuso horário (Brasília)..." -ForegroundColor Yellow
Set-TimeZone -Id "E. South America Standard Time"

# 7. Informações e Renomeação Automática (com timeout)
$computer = Get-CimInstance Win32_ComputerSystem
Write-Host "`nInformações atuais do sistema:" -ForegroundColor Cyan
Write-Host "Nome: $($computer.Name)"
$mac = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 -ExpandProperty MacAddress
Write-Host "MAC Principal: $mac"

$suggestedName = "LAB-PHAR-$($mac.Replace(':','').Substring(6,6))" # Sugestão baseada no MAC
Write-Host "`nSugestão de Nome: $suggestedName" -ForegroundColor Cyan
Write-Host "Aguardando 10 segundos para entrada... (Ou pressione ENTER para manter o nome atual)"

$newName = ""
$timeout = 10
$timer = [diagnostics.stopwatch]::StartNew()

while ($timer.Elapsed.TotalSeconds -lt $timeout -and -not [console]::KeyAvailable) {
    Write-Host -NoNewline "`rTempo restante: $($timeout - [int]$timer.Elapsed.TotalSeconds)s. Nome desejado: "
    Start-Sleep -Milliseconds 500
}

if ([console]::KeyAvailable) {
    $newName = Read-Host
} else {
    Write-Host "`nTempo esgotado. Mantendo nome atual."
}

if ($newName -and $newName -ne $computer.Name) {
    try {
        Rename-Computer -NewName $newName -Force
        Write-Host "Sucesso: Nome alterado para $newName." -ForegroundColor Green
    } catch {
        Write-Warning "Falha ao renomear: $_"
    }
}

# 8. Finalização
Write-Host "`n[8/8] Otimizações de sistema concluídas." -ForegroundColor Cyan

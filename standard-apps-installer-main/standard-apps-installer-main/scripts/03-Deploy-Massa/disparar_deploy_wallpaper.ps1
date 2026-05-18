# scripts/03-Deploy-Massa/disparar_deploy_wallpaper.ps1
# Deploy massivo de papel de parede para o laboratório

$wallpaperLocal = "$PSScriptRoot\..\Recursos\wallpaper-fafar.png"
$wallpaperRemotePath = "C:\Users\Public\wallpaper-fafar.png"
$usuario = "User"
$senha = "anjos2014" | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($usuario, $senha)

$onlineHosts = @()
Write-Host ">>> [FASE 1] Escaneando laboratório para Correção de Wallpaper..." -ForegroundColor Cyan

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

Write-Host "`n>>> [FASE 2] Iniciando Correção nos $($onlineHosts.Count) PCs..." -ForegroundColor Cyan

try {
    # Abre sessões em paralelo
    $sessions = New-PSSession -ComputerName $onlineHosts -Credential $cred -ErrorAction SilentlyContinue
    $activeSessions = $sessions | Where-Object { $_.State -eq 'Opened' }
    
    if (-not $activeSessions) {
        Write-Error "Não foi possível abrir nenhuma sessão válida."
        return
    }

    Write-Host "   -> Enviando imagem para C:\Users\Public\..." -ForegroundColor Yellow
    
    # Copia a imagem para todos
    $activeSessions | ForEach-Object {
        Copy-Item -Path $wallpaperLocal -Destination $wallpaperRemotePath -ToSession $_
    }

    Write-Host "   -> Ajustando Permissões e Aplicando Política..." -ForegroundColor Yellow

    # Aplica via Registro (Política de Sistema - HKLM)
    Invoke-Command -Session $activeSessions -ScriptBlock {
        param($path)
        
        # Garante permissão de leitura para todos no arquivo
        icacls $path /grant "Todos:(R)" /T /C
        icacls $path /grant "Users:(R)" /T /C

        $policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        
        # Garante que a chave existe
        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }

        # Define o Wallpaper e o Estilo (10 = Fill/Preencher)
        Set-ItemProperty -Path $policyPath -Name "Wallpaper" -Value $path -Force
        Set-ItemProperty -Path $policyPath -Name "WallpaperStyle" -Value "10" -Force

        # Força o Windows a atualizar o desktop reiniciando o processo explorer
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Opcional: Tenta forçar a atualização via comando de sistema se houver usuário logado
        rundll32.exe user32.dll,UpdatePerUserSystemParameters
    } -ArgumentList $wallpaperRemotePath
    
    Remove-PSSession $sessions
    Write-Host "`n>>> WALLPAPER APLICADO COM SUCESSO!" -ForegroundColor Green

} catch {
    Write-Host "`n>>> ERRO: $($_.Exception.Message)" -ForegroundColor Red
}

$ErrorActionPreference = "Stop"

$senhaText = "anjos2014"
$senha = $senhaText | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $senha)
$ip = "192.168.137.16"

Write-Host "Conectando ao $ip"
$s = New-PSSession -ComputerName $ip -Credential $cred -ErrorAction Stop

$zipLocal = "c:\Users\CARLOS\Downloads\standard-apps-installer-main\standard-apps-installer-main\scripts\sync-datetime.zip"
Write-Host "Copiando zip..."
Copy-Item -Path $zipLocal -Destination "C:\Windows\Temp\sync-datetime.zip" -ToSession $s

Write-Host "Executando carga no $ip"
Invoke-Command -Session $s -ScriptBlock {
    Write-Host "Trace 1: Removendo pasta se existir..."
    if (Test-Path "C:\sync-datetime") { Remove-Item "C:\sync-datetime" -Recurse -Force }
    Write-Host "Trace 2: Extraindo..."
    Expand-Archive -Path "C:\Windows\Temp\sync-datetime.zip" -DestinationPath "C:\sync-datetime" -Force
    Write-Host "Trace 3: Buscando bat..."
    
    try {
        $batFile = Get-ChildItem -Path "C:\sync-datetime" -Filter "scheduale-sync.bat" -Recurse -ErrorAction Stop | Select-Object -First 1
        Write-Host "Trace 4: Bat encontrado? $($batFile -ne $null)"
        if ($batFile) {
            Write-Host "Trace 5: Executando bat..."
            Set-Location $batFile.DirectoryName
            .\scheduale-sync.bat
            Write-Host "Trace 6: Fim do bat."
        }
    } catch {
        Write-Host "Trace ERR: Erro no get-childitem: $($_.Exception.Message)"
    }
    Write-Host "Trace 7: Fim do scriptblock"
}

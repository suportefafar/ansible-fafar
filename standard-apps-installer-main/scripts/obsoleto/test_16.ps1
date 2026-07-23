$ErrorActionPreference = "Stop"

$senhaText = "anjos2014"
$senha = $senhaText | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $senha)
$ip = "192.168.137.16"

Write-Host "Conectando ao $ip"
$s = New-PSSession -ComputerName $ip -Credential $cred -ErrorAction Stop

Write-Host "Executando carga no $ip"
Invoke-Command -Session $s -ScriptBlock {
    Write-Host "Running bat file"
    C:\sync-datetime\scheduale-sync.bat
    Write-Host "Finished bat file"
}

Remove-PSSession $s
Write-Host "Fim."

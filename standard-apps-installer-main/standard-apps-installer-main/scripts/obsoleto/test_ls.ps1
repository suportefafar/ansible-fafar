$ErrorActionPreference = "Stop"

$senhaText = "anjos2014"
$senha = $senhaText | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $senha)
$ip = "192.168.137.16"

$s = New-PSSession -ComputerName $ip -Credential $cred -ErrorAction Stop

Invoke-Command -Session $s -ScriptBlock {
    Write-Host "Conteudo de C:\sync-datetime"
    Get-ChildItem -Path "C:\sync-datetime"
}

Remove-PSSession $s

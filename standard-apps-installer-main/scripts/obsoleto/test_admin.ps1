$ErrorActionPreference = "Stop"

$senhaText = "anjos2014"
$senha = $senhaText | ConvertTo-SecureString -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("User", $senha)

$targetIp = "192.168.137.16"

Write-Host "Testando permissões de administrador no $targetIp via WinRM..."

try {
    $s = New-PSSession -ComputerName $targetIp -Credential $cred -ErrorAction Stop
    Write-Host "[SUCESSO] Conectado!" -ForegroundColor Green
    
    $result = Invoke-Command -Session $s -ScriptBlock {
        $testPath = "C:\Windows\Temp\winrm_admin_test.txt"
        try {
            "test" | Out-File -FilePath $testPath -ErrorAction Stop
            Remove-Item -Path $testPath -Force
            return "SUCCESS"
        } catch {
            return "ERROR: $($_.Exception.Message)"
        }
    }
    
    Write-Host "Resultado da criação de arquivo em C:\Windows\Temp : $result"
    
    $result2 = Invoke-Command -Session $s -ScriptBlock {
        # Check if the user is in the local Administrators group
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        return $isAdmin
    }
    
    Write-Host "Usuário é Admin? (IsInRole Administrator): $result2"
    
    Remove-PSSession $s
} catch {
    Write-Host "[FALHA] $($_.Exception.Message)" -ForegroundColor Red
}

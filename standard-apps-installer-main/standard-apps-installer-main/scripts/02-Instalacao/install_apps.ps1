# Script para instalar programas via Chocolatey
param (
    [string[]]$Packages
)

if ($null -eq $Packages -or $Packages.Count -eq 0) {
    Write-Host "Nenhum pacote especificado para instalação." -ForegroundColor Gray
    return
}

# Atualizar PATH e garantir que a lista de pacotes seja separada corretamente (separar por vírgula se necessário)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$packageList = if ($Packages.Count -eq 1) { $Packages -split ',' } else { $Packages }

Write-Host "Iniciando a instalação dos programas..." -ForegroundColor Cyan

foreach ($pkg in $packageList) {
    $pkg = $pkg.Trim()
    if ($pkg) {
        Write-Host "Instalando: $pkg..." -ForegroundColor Yellow
        # --ignore-checksums adicionado para evitar falhas em pacotes que atualizam muito rápido (ex: Chrome)
        choco install $pkg -y --limit-output --no-progress --ignore-checksums
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010) {
            Write-Host "Sucesso: $pkg" -ForegroundColor Green
        } else {
            Write-Warning "Erro ao instalar: $pkg (Código: $LASTEXITCODE)"
        }
    }
}

Write-Host "Processo de instalação concluído." -ForegroundColor Cyan

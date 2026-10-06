# scripts/04-Diagnostico/remover_instalador_epinfo.ps1
# Script para remover instaladores e atalhos quebrados do Epi Info da Área de Trabalho de todos os usuários

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Iniciando verificação e limpeza de instaladores do Epi Info na Área de Trabalho..." -ForegroundColor Cyan

# 1. Localizar todas as pastas de Área de Trabalho dos usuários e Public
$desktopFolders = @(
    "C:\Users\Public\Desktop",
    "C:\Users\Public\Public Desktop"
)

# Adiciona Desktop de todos os perfis em C:\Users
Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
    $userDesktop = Join-Path $_.FullName "Desktop"
    if (Test-Path $userDesktop) {
        $desktopFolders += $userDesktop
    }
}

$desktopFolders = $desktopFolders | Select-Object -Unique

# 2. Padrões de arquivos de instalação para remover do Desktop
$installerPatterns = @(
    "*EpiInfo*Setup*.exe",
    "*Epi*Info*Setup*.exe",
    "*EpiInfo*Installer*.exe",
    "*EpiInfo*.msi",
    "*setup_epi*.exe",
    "*EpiInfo7*.exe",
    "*EpiInfo7*.zip",
    "*Epi_Info*.exe"
)

$removedCount = 0

foreach ($folder in $desktopFolders) {
    if (Test-Path $folder) {
        # Busca executáveis/instaladores diretamente na Área de Trabalho
        foreach ($pattern in $installerPatterns) {
            $files = Get-ChildItem -Path $folder -Filter $pattern -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                Write-Host " [x] Removendo instalador do Desktop: $($file.FullName)" -ForegroundColor Yellow
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                $removedCount++
            }
        }

        # Busca atalhos (.lnk) que aponta para instaladores ou que estão quebrados/com 'setup' no nome
        $shortcuts = Get-ChildItem -Path $folder -Filter "*Epi*.lnk" -File -ErrorAction SilentlyContinue
        $wshShell = New-Object -ComObject WScript.Shell
        
        foreach ($lnk in $shortcuts) {
            try {
                $sc = $wshShell.CreateShortcut($lnk.FullName)
                $target = $sc.TargetPath
                
                # Se o atalho aponta para um executável de instalação ou o arquivo alvo não existe
                if ($target -match "setup|install|download" -or ($target -ne "" -and -not (Test-Path $target))) {
                    Write-Host " [x] Removendo atalho inválido/instalador: $($lnk.FullName) -> Target: $target" -ForegroundColor Yellow
                    Remove-Item -Path $lnk.FullName -Force -ErrorAction SilentlyContinue
                    $removedCount++
                }
            } catch {}
        }
    }
}

# 3. Garantir atalho correto apontando para a instalação válida do Epi Info (se encontrada)
$possibleInstallPaths = @(
    "C:\EpiInfo7\EpiInfo.exe",
    "C:\Epi Info 7\EpiInfo.exe",
    "C:\Program Files (x86)\Epi Info 7\EpiInfo.exe",
    "C:\Program Files\Epi Info 7\EpiInfo.exe",
    "C:\Program Files (x86)\CDC\Epi Info 7\EpiInfo.exe",
    "C:\Program Files\CDC\Epi Info 7\EpiInfo.exe",
    "C:\Program Files (x86)\CDC\EpiInfo7\EpiInfo.exe",
    "C:\EpiInfo\EpiInfo.exe"
)

$validExe = $null
foreach ($path in $possibleInstallPaths) {
    if (Test-Path $path) {
        $validExe = $path
        break
    }
}

if ($validExe) {
    Write-Host "Instalação válida do Epi Info encontrada em: $validExe" -ForegroundColor Green
    $publicDesktop = "C:\Users\Public\Desktop"
    if (Test-Path $publicDesktop) {
        $shortcutPath = Join-Path $publicDesktop "Epi Info 7.lnk"
        try {
            $wshShell = New-Object -ComObject WScript.Shell
            $sc = $wshShell.CreateShortcut($shortcutPath)
            $sc.TargetPath = $validExe
            $sc.WorkingDirectory = (Split-Path $validExe -Parent)
            $sc.Description = "Epi Info 7"
            $sc.Save()
            Write-Host "Atalho público válido verificado/criado em: $shortcutPath" -ForegroundColor Green
        } catch {
            Write-Warning "Não foi possível recriar o atalho público: $_"
        }
    }
} else {
    Write-Host "Nota: Nenhuma instalação padrão do Epi Info foi detectada nos caminhos comuns." -ForegroundColor Gray
}

Write-Host "Concluído! Total de arquivos/atalhos de instaladores removidos: $removedCount" -ForegroundColor Green

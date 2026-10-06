# scripts/02-Instalacao/instalar_epiinfo_cdc.ps1
# Script para instalar localmente a pasta CDC do Epi Info e gerar o atalho "EPI - Funcionando"

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Iniciando configuração cirúrgica do Epi Info 7.2.6.0 (CDC)..." -ForegroundColor Cyan

$sourceDir = "$PSScriptRoot\..\..\apps\CDC"
$targetDir = "C:\Users\Public\Downloads\CDC"
$publicDesktop = "C:\Users\Public\Desktop"

if (-not (Test-Path $sourceDir)) {
    Write-Error "Pasta de origem CDC não encontrada em: $sourceDir"
    exit 1
}

# 1. Copiar conteúdo para C:\Users\Public\Downloads\CDC
Write-Host "Copiando pasta CDC para $targetDir..." -ForegroundColor Yellow
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Copy-Item -Path "$sourceDir\*" -Destination $targetDir -Recurse -Force

# 2. Conceder permissões totais de leitura e execução a todos os usuários (Everyone / Users)
Write-Host "Aplicando permissões universais de acesso..." -ForegroundColor Yellow
$icacls = "$env:SystemRoot\System32\icacls.exe"
if (Test-Path $icacls) {
    & $icacls $targetDir /grant "*S-1-1-0:(OI)(CI)F" /T /C 2>$null
    & $icacls $targetDir /grant "*S-1-5-32-545:(OI)(CI)F" /T /C 2>$null
}

# 3. Remover atalhos antigos ou confusos de Epi Info da Área de Trabalho Pública
Get-ChildItem -Path $publicDesktop -Filter "*Epi*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -ne "EPI - Funcionando.lnk") {
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

# 4. Criar o atalho "EPI - Funcionando" na Área de Trabalho Pública
$exePath = "$targetDir\Epi Info 7.2.6.0\EpiInfo.exe"
if (-not (Test-Path $exePath)) {
    $exePath = (Get-ChildItem -Path $targetDir -Filter "EpiInfo.exe" -Recurse | Select-Object -First 1).FullName
}

if ($exePath -and (Test-Path $exePath)) {
    $shortcutPath = Join-Path $publicDesktop "EPI - Funcionando.lnk"
    try {
        $wshShell = New-Object -ComObject WScript.Shell
        $sc = $wshShell.CreateShortcut($shortcutPath)
        $sc.TargetPath = $exePath
        $sc.WorkingDirectory = (Split-Path $exePath -Parent)
        $sc.Description = "Epi Info 7.2.6.0 - Funcionando"
        $sc.Save()
        Write-Host "Atalho 'EPI - Funcionando' criado com sucesso em: $shortcutPath" -ForegroundColor Green
    } catch {
        Write-Error "Falha ao criar o atalho na Área de Trabalho: $_"
    }
} else {
    Write-Error "Executável EpiInfo.exe não foi encontrado na pasta $targetDir"
}

Write-Host "Instalação do Epi Info CDC concluída!" -ForegroundColor Green

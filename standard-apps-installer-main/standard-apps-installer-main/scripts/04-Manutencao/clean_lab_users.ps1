# scripts/clean_lab_users.ps1
$ErrorActionPreference = 'SilentlyContinue'

Write-Host "Iniciando limpeza das pastas do usuario FARMANET..." -ForegroundColor Cyan

# 1. Apagar arquivos das pastas do FARMANET
$targetFolders = @(
    "C:\Users\FARMANET\Desktop\*",
    "C:\Users\FARMANET\Documents\*",
    "C:\Users\FARMANET\Downloads\*",
    "C:\Users\FARMANET\Pictures\*",
    "C:\Users\FARMANET\Videos\*"
)

foreach ($folder in $targetFolders) {
    if (Test-Path -Path $folder) {
        Write-Host "Limpando: $folder"
        Remove-Item -Path $folder -Recurse -Force
    }
}

# 2. Redefinir Tela de Fundo (Wallpaper) Padrão do Windows 10
Write-Host "Aplicando Tela de Fundo Padrao do Windows 10 para todos os usuarios..." -ForegroundColor Cyan

$wallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
$policyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# Garantir que a chave existe
if (-not (Test-Path $policyPath)) {
    New-Item -Path $policyPath -Force | Out-Null
}

# Forçar o papel de parede via Registro (Aplica para todos os usuários que logarem)
Set-ItemProperty -Path $policyPath -Name "Wallpaper" -Value $wallpaperPath
Set-ItemProperty -Path $policyPath -Name "WallpaperStyle" -Value "2" # 2 = Estender/Preencher

# Reiniciar o Windows Explorer para aplicar as mudanças visuais se houver algum usuário logado
Stop-Process -Name explorer -Force

Write-Host "Limpeza e redefinicao concluidas!" -ForegroundColor Green

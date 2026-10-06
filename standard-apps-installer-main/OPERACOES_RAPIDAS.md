# OPERACOES RAPIDAS — Laboratorio FAFAR/UFMG
# Cheatsheet de comandos para gerenciamento remoto do laboratorio

## PRE-REQUISITO
# Execute sempre como Administrador no PowerShell
# Navegue ate a pasta raiz do projeto antes de rodar qualquer script:
#   cd C:\caminho\para\standard-apps-installer-main

---

## 1. PREPARAR UMA MAQUINA NOVA (rodar localmente no PC novo)
# Configura WinRM + instala Chocolatey. Rodar UMA VEZ por PC novo.

.\scripts\01-Preparo\preparar_maquina_completo.ps1

---

## 2. DEPLOY MASSIVO — PAPEL DE PAREDE (todas as maquinas)
# Envia e aplica o wallpaper em todos os PCs do lab de uma vez.
# Coloque a imagem em: scripts\Recursos\wallpaper-fafar.png

.\scripts\03-Deploy-Massa\disparar_deploy_wallpaper.ps1

---

## 3. DEPLOY MASSIVO — INSTALAR R e RSTUDIO (todas as maquinas)
# Instala Chocolatey (se necessario), R e RStudio em todos os PCs.

.\scripts\03-Deploy-Massa\instalar_R_RStudio.ps1

---

## 4. DEPLOY MASSIVO — SINCRONIZAR DATA/HORA (todas as maquinas)

.\scripts\03-Deploy-Massa\forcar_sincronizacao_hora.ps1

---

## 5. VERIFICAR SE O WALLPAPER TROCOU (diagnostico)
# Mostra o caminho do wallpaper registrado no perfil de cada usuario logado.

.\scripts\04-Diagnostico\verificar_wallpaper.ps1

# Versao avancada: verifica integridade matematica (hash SHA-256) da imagem
.\scripts\04-Diagnostico\verificar_wallpaper_hash.ps1

---

## 6. LIMPAR ARQUIVOS DOS ALUNOS (pasta FARMANET)
# Remove arquivos de Desktop, Documents, Downloads, Pictures e Videos do FARMANET.
# ATENCAO: irreversivel!

# Opção A: Executar localmente nesta máquina
.\scripts\04-Diagnostico\clean_lab_users.ps1

# Opção B: Disparar em massa para todo o laboratório (via rede/WinRM)
.\scripts\03-Deploy-Massa\disparar_clean_lab.ps1

---

## 7. REMOVER INSTALADOR E ATALHOS QUEBRADOS DO EPI INFO
# Remove executáveis de instalação (*EpiInfo*.exe, setup, etc.) e atalhos inválidos da Área de Trabalho.
# Garante atalho funcional para a instalação válida do Epi Info.

# Opção A: Executar localmente nesta máquina
.\scripts\04-Diagnostico\remover_instalador_epinfo.ps1

# Opção B: Disparar em massa para todo o laboratório (via rede/WinRM)
.\scripts\03-Deploy-Massa\disparar_remover_instalador_epinfo.ps1

---

## 8. INSTALAR EPI INFO 7.2.6.0 (PASTA CDC -> DOWNLOADS)
# Copia a pasta apps/CDC para Downloads das máquinas e gera o atalho "EPI - Funcionando" na Área de Trabalho.
# Concede permissões totais para execução sem senha de administrador.

# Opção A: Executar localmente nesta máquina
.\scripts\02-Instalacao\instalar_epiinfo_cdc.ps1

# Opção B: Disparar em massa para todo o laboratório (via rede/WinRM)
.\scripts\03-Deploy-Massa\disparar_deploy_epiinfo_cdc.ps1

---

## 9. COPIAR Epi_Info_7.zip PARA TODAS AS MAQUINAS + ATALHO "EPI - Definitivo"
# Copia apps\Epi_Info_7.zip para C:\Users\Public\Downloads, extrai em ...\Downloads\Epi_Info_7
# e cria o atalho "EPI - Definitivo" (-> Launch Epi Info 7.exe) na Area de Trabalho publica.
# Para outro destino: -Destino "C:\Temp"

.\scripts\03-Deploy-Massa\copiar_zip_epiinfo.ps1

---

## CREDENCIAIS PADRAO
# Usuario principal: User    | Senha: anjos2014
# Usuario alternativo: admin | Senha: anjos2014
# (Os scripts tentam automaticamente os dois usuarios)

## REDE DO LABORATORIO
# Sub-rede: 192.168.137.0/24
# Porta WinRM: 5985
# Os scripts detectam a sub-rede ativa automaticamente.

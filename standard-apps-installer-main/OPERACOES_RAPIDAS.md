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

.\scripts\04-Diagnostico\clean_lab_users.ps1

---

## CREDENCIAIS PADRAO
# Usuario principal: User    | Senha: anjos2014
# Usuario alternativo: admin | Senha: anjos2014
# (Os scripts tentam automaticamente os dois usuarios)

## REDE DO LABORATORIO
# Sub-rede: 192.168.137.0/24
# Porta WinRM: 5985
# Os scripts detectam a sub-rede ativa automaticamente.

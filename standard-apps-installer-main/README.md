# Sistema de Automacao de Laboratorios — FAFAR/UFMG

Sistema de automacao para deploy, instalacao e configuracao em massa de computadores dos laboratorios da Faculdade de Farmacia (UFMG).

Utiliza scripts nativos em **PowerShell** com conexao remota via **WinRM** e instalacao de pacotes via **Chocolatey**. Suporte opcional a **Ansible**.

---

## Estrutura do Projeto

```
standard-apps-installer/
|
+-- README.md                     <- Este guia
+-- OPERACOES_RAPIDAS.md          <- Cheatsheet de comandos do dia a dia
|
+-- config/
|   +-- apps.json                 <- Lista de pacotes padrao do laboratorio
|
+-- scripts/
|   |
|   +-- 01-Preparo/
|   |   +-- preparar_maquina_completo.ps1  <- Configura WinRM + Chocolatey (1x por PC novo)
|   |
|   +-- 02-Instalacao/
|   |   +-- install_apps.ps1               <- Instala pacotes via Chocolatey (uso local)
|   |   +-- sys_config.ps1                 <- Configuracoes de sistema
|   |
|   +-- 03-Deploy-Massa/
|   |   +-- disparar_deploy_wallpaper.ps1             <- Deploy de papel de parede
|   |   +-- instalar_R_RStudio.ps1                    <- Deploy R + RStudio
|   |   +-- disparar_deploy_laboratorio_paralelo.ps1  <- Deploy generico paralelo
|   |   +-- forcar_sincronizacao_hora.ps1             <- Sincronizacao de data/hora (NTP)
|   |
|   +-- 04-Diagnostico/
|   |   +-- verificar_wallpaper.ps1         <- Verifica wallpaper no registro dos usuarios
|   |   +-- verificar_wallpaper_hash.ps1    <- Verifica integridade matematica (SHA-256)
|   |   +-- clean_lab_users.ps1             <- Limpa arquivos do usuario FARMANET
|   |
|   +-- Recursos/
|       +-- wallpaper-fafar.png             <- Imagem oficial de papel de parede
|
+-- logs/                         <- Logs de execucoes (gerado automaticamente)
+-- ansible/                      <- Playbooks Ansible (alternativa opcional)
+-- scripts/obsoleto/             <- Scripts antigos mantidos como referencia
```

---

## Inicio Rapido

Para o dia a dia, consulte o arquivo **[OPERACOES_RAPIDAS.md](OPERACOES_RAPIDAS.md)** — ele tem todos os comandos prontos para copiar e colar.

---

## Configuracao Inicial (Uma Vez por PC Novo)

### Passo 1 — Preparar a Maquina Alvo

Execute este script **localmente** em cada PC novo do laboratorio (como Administrador):

```powershell
.\scripts\01-Preparo\preparar_maquina_completo.ps1
```

O que ele faz automaticamente:
- Altera o perfil de rede para **Privado** (necessario para o WinRM)
- Ativa e configura o servico **WinRM** na porta `5985`
- Aplica `LocalAccountTokenFilterPolicy` no registro (permite admin remoto para contas locais)
- Cria regra no **Firewall** liberando a porta `5985`
- Instala o gerenciador de pacotes **Chocolatey** (com 3 tentativas automaticas)

> **Nota:** Repita em cada maquina nova que entrar no laboratorio.

### Passo 2 — Preparar a Maquina Gerenciadora (Host)

O Host e o computador de onde voce dispara os comandos para o lab inteiro.

Requisitos:
- Estar **na mesma rede** do laboratorio (`192.168.137.x`)
- Ter este repositorio baixado/clonado
- Executar os scripts como **Administrador**

---

## Deploy Massivo

Todos os scripts de deploy em massa:
- **Detectam automaticamente** as sub-redes IPv4 ativas no Host (sem precisar configurar IPs manualmente)
- **Tentam dois usuarios** em sequencia: `User` e `admin` (com a senha padrao)
- **Isolam falhas** — se uma maquina cair no meio, as outras continuam sendo atualizadas
- **Reportam** sucesso e falha ao final com o IP de cada maquina

### Papel de Parede

```powershell
.\scripts\03-Deploy-Massa\disparar_deploy_wallpaper.ps1
```

Envia `scripts\Recursos\wallpaper-fafar.png` para `C:\Users\Public\` em todos os PCs e aplica via Tarefa Agendada na sessao interativa do usuario logado (funciona mesmo com WinRM na Sessao 0).

### R e RStudio

```powershell
.\scripts\03-Deploy-Massa\instalar_R_RStudio.ps1
```

Instala Chocolatey (se necessario), depois R (`r.project`) e RStudio (`r.studio`) em todos os PCs. Pula automaticamente PCs onde ja estao instalados.

### Sincronizar Data/Hora

```powershell
.\scripts\03-Deploy-Massa\forcar_sincronizacao_hora.ps1
```

---

## Diagnostico e Verificacao

### Verificar se o wallpaper trocou

```powershell
# Verifica o caminho no registro de cada usuario logado
.\scripts\04-Diagnostico\verificar_wallpaper.ps1

# Verifica integridade matematica (hash SHA-256) da imagem renderizada
.\scripts\04-Diagnostico\verificar_wallpaper_hash.ps1
```

### Limpar arquivos dos alunos (usuario FARMANET)

```powershell
.\scripts\04-Diagnostico\clean_lab_users.ps1
```

> **ATENCAO:** Remove permanentemente arquivos de Desktop, Documents, Downloads, Pictures e Videos do usuario FARMANET em todas as maquinas.

---

## Credenciais e Rede

| Item | Valor |
|------|-------|
| Usuario principal | `User` |
| Usuario alternativo | `admin` |
| Senha (ambos) | `anjos2014` |
| Sub-rede do lab | `192.168.137.0/24` |
| Porta WinRM | `5985` |

> Os scripts detectam a sub-rede automaticamente a partir das interfaces de rede do Host. Nao e necessario configurar manualmente.

---

## Resolucao de Problemas

**"Acesso Negado" no WinRM**
Geralmente o usuario remoto nao e administrador ou a chave `LocalAccountTokenFilterPolicy` nao foi aplicada. Rode novamente o script de preparo na maquina com problema:
```powershell
.\scripts\01-Preparo\preparar_maquina_completo.ps1
```

**Maquina nao aparece no scanner**
- Verifique se o Firewall do Windows da maquina esta bloqueando a porta `5985`
- Verifique se a rede foi classificada como "Publica" ao inves de "Privada" — o script de preparo corrige isso

**Maquina cai no meio do deploy**
Os scripts de deploy possuem tratamento individual de erros por maquina. A maquina com problema recebe um aviso no log e o script continua normalmente nas demais.

---

## Ansible (Opcional)

Se preferir usar Ansible via WSL:
1. Configure os IPs em `ansible/inventory.ini`
2. Execute o playbook desejado:
```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy_lab.yml
```

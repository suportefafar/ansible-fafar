# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Lab automation for the Faculty of Pharmacy (FAFAR/UFMG). It mass-deploys, installs, and configures Windows lab PCs using native **PowerShell** over **WinRM** (port 5985) with package installs via **Chocolatey**. Ansible playbooks exist as an optional alternative.

Code, comments, and console output are written in **Portuguese** — match that when editing or adding scripts.

## Two execution models

1. **Mass deploy from a Host (current, primary workflow)** — `scripts/03-Deploy-Massa/*.ps1` run from one management machine on the lab subnet and push changes to every PC over WinRM. This is what day-to-day operations use.
2. **Single-PC EXE installer (original flow)** — `src/main.py` orchestrates Chocolatey + system config on the *local* machine. It is packaged into `dist/Instalador Apps Padrao.exe` with PyInstaller and bootstrapped by `run_installer.ps1`/`run_installer.bat`.

## Common commands

All scripts require an **elevated (Administrator)** PowerShell, run from the repo root.

```powershell
# Prepare a NEW lab PC (run locally on that PC, once): WinRM + firewall + Chocolatey
.\scripts\01-Preparo\preparar_maquina_completo.ps1

# Mass deploys (run from the Host, hit all PCs on the subnet)
.\scripts\03-Deploy-Massa\disparar_deploy_wallpaper.ps1
.\scripts\03-Deploy-Massa\instalar_R_RStudio.ps1
.\scripts\03-Deploy-Massa\forcar_sincronizacao_hora.ps1

# Diagnostics / cleanup
.\scripts\04-Diagnostico\verificar_wallpaper.ps1          # check wallpaper registry path per user
.\scripts\04-Diagnostico\verificar_wallpaper_hash.ps1     # verify rendered image via SHA-256
.\scripts\04-Diagnostico\clean_lab_users.ps1              # IRREVERSIBLE: wipes FARMANET user files

# Single-PC installer (local)
.\run_installer.ps1        # bootstraps Python if missing, then runs src/main.py

# Rebuild the EXE (needs Python + pip; installs PyInstaller if absent)
.\gera-exe.bat             # outputs dist/Instalador Apps Padrao.exe
```

`OPERACOES_RAPIDAS.md` is the operator cheatsheet — the authoritative, copy-paste list of every routine operation. Keep it in sync when you add or rename an operational script.

There is **no test suite and no linter**. `requirements.txt` contains only `pyinstaller` (build-time).

## Mass-deploy script pattern

Every `03-Deploy-Massa` script follows the same two-phase structure — copy an existing one (e.g. `disparar_deploy_wallpaper.ps1`) rather than inventing a new shape:

- **Phase 1 — discover hosts:** enumerate active IPv4 subnets via `Get-NetIPAddress` (excluding loopback/link-local/virtual adapters), then TCP-scan `.1-254` on port 5985 with a short (~100ms) async timeout to find live WinRM hosts. Subnets are auto-detected — do not hardcode IPs.
- **Phase 2 — act over WinRM:** open `New-PSSession` to all hosts trying the `User` credential first, then retry only the failures with `admin`. Push files with `Copy-Item -ToSession` and run remote logic inside `Invoke-Command -ScriptBlock`. Wrap each host in its own `try/catch` so one failed machine never aborts the batch, and always `Remove-PSSession` at the end.

Remote logic that must affect the *interactive* desktop session (e.g. wallpaper) cannot run directly — WinRM lands in Session 0. The established workaround is to register a **Scheduled Task** running as the `Users` group SID (`S-1-5-32-545`, language-independent), trigger it, then unregister it and delete its payload.

## Key facts & gotchas

- **Hardcoded credentials** live in nearly every deploy script and in `ansible/inventory.ini`: users `User` / `admin`, password `anjos2014`. Changing the lab password means editing all of them. Treat these as the real lab secrets — do not exfiltrate or publish them.
- **Lab network:** `192.168.137.0/24`, WinRM port `5985`.
- `src/main.py` loads its package list from `config/apps.json` (`{"packages": [...]}`) and self-elevates via UAC (`ShellExecuteW "runas"`). It resolves bundled resources through `sys._MEIPASS` so paths work both in dev and inside the PyInstaller EXE.
- **`main.py` script references are stale:** it calls `run_powershell("init_choco.ps1")`, `install_apps.ps1`, `sys_config.ps1`, `win_updates.ps1` by bare filename, but those files now live under numbered subfolders (`scripts/02-Instalacao/...`) and `init_choco.ps1` does not exist at all. The EXE install flow is effectively superseded by the manual phase scripts — verify paths before relying on it.
- `scripts/obsoleto/` holds superseded scripts kept only for reference — don't extend them.
- Logs are written to `logs/` (gitignored); the EXE flow names them `install_<timestamp>.log`.

import subprocess
import os
import sys
import json
import ctypes
import logging
from datetime import datetime

# Configuração de Pasta de Logs
LOG_DIR = "logs"
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR)

LOG_FILE = os.path.join(LOG_DIR, f"install_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

# Configurar Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except:
        return False

def get_resource_path(relative_path):
    """ Obtém caminho absoluto, funciona para dev e PyInstaller """
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")
    
    path = os.path.join(base_path, relative_path)
    if os.path.exists(path):
        return path
    return path

def run_powershell(script_name, args=None, retries=1):
    script_path = get_resource_path(os.path.join("scripts", script_name))
    if not os.path.exists(script_path):
        script_path = get_resource_path(script_name)

    logging.info(f"--- Executando: {script_name} ---")
    
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path]
    if args:
        cmd.extend(args)
    
    attemp = 0
    while attemp < retries:
        try:
            result = subprocess.call(cmd)
            if result == 0:
                logging.info(f"Sucesso: {script_name}")
                return True
            else:
                logging.warning(f"Aviso: {script_name} retornou código {result}")
                attemp += 1
                if attemp < retries:
                    logging.info(f"Tentando novamente {script_name} (Tentativa {attemp+1})...")
        except Exception as e:
            logging.error(f"Erro ao executar {script_name}: {e}")
            attemp += 1
    
    return False

def main():
    try:
        # 1. Verificar Elevação
        if not is_admin():
            logging.info("Solicitando permissões de administrador...")
            # Re-executa o script com privilégios de administrador
            script_abs_path = os.path.abspath(sys.argv[0])
            params = " ".join(sys.argv[1:])
            ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, f'"{script_abs_path}" {params}', None, 1)
            sys.exit()

        logging.info("======================================================")
        logging.info("      SISTEMA DE AUTOMAÇÃO DE LABORATÓRIOS (UFMG)     ")
        logging.info("======================================================")
        logging.info(f"Diretório de trabalho: {os.getcwd()}")
        logging.info(f"Arquivo de Log: {LOG_FILE}")

        # 2. Carregar Configuração
        config_path = get_resource_path(os.path.join("config", "apps.json"))
        if not os.path.exists(config_path):
            config_path = get_resource_path("apps.json")

        packages = []
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    packages = config.get("packages", [])
            except Exception as e:
                logging.error(f"Erro ao carregar apps.json: {e}")
        else:
            logging.error(f"Configuração não encontrada em: {config_path}")

        # 3. Fluxo de Execução
        
        # Passo 1: Chocolatey (com 2 retentativas)
        if not run_powershell("init_choco.ps1", retries=2):
            logging.error("Falha crítica ao inicializar o Chocolatey.")

        # Passo 2: Instalar Programas
        if packages:
            logging.info(f"Pacotes para instalar: {', '.join(packages)}")
            run_powershell("install_apps.ps1", ["-Packages", ",".join(packages)])
        else:
            logging.warning("Nenhum pacote encontrado para instalar.")

        # Passo 3: Configurações do Sistema e Otimizações de Lab
        run_powershell("sys_config.ps1")

        # Passo 4: Atualizações do Windows
        logging.info("Iniciando Atualizações do Sistema (pode demorar)...")
        run_powershell("win_updates.ps1")

        logging.info("\n======================================================")
        logging.info("             Processo Finalizado com Sucesso!        ")
        logging.info("======================================================")
        
    except Exception as e:
        print(f"\n[ERRO CRÍTICO NO PYTHON]: {e}")
        import traceback
        traceback.print_exc()
    
    input("Pressione Enter para sair...")

if __name__ == "__main__":
    main()

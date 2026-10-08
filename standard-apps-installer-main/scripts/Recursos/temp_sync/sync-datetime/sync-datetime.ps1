# sync-datetime.ps1
# Servico de sincronizacao de hora do laboratorio.
#
# Em cada ciclo executa os metodos EM ORDEM, testando o relogio apos cada um:
#   1) Cronos NTP   (cronos.farmacia.ufmg.br, UDP/123) -> define a hora com Set-Date -> TESTA
#   2) Cronos HTTP  (https://cronos.farmacia.ufmg.br/time)  -> define com Set-Date    -> TESTA
#   3) Windows      (w32tm /resync)                                                   -> TESTA
#   4) NTP publico  (NTP.br/Google/...; ultimo recurso)      -> define com Set-Date   -> TESTA
# Se algum TESTE confirmar a hora correta (drift <= tolerancia), o loop ENCERRA.
# Senao, aguarda e repete o ciclo (loop) ate MaxCiclos.
#
# Cada metodo e testado contra a SUA PROPRIA referencia (Cronos NTP/HTTP, time.windows.com,
# NTP publico). A verificacao inicial do ciclo usa referencia NAO-Windows (Cronos).
#
# Registra TODAS as tentativas (motivo de sucesso/falha) e o STATUS (sincronizado ou nao) em log.

param(
    [int]$ToleranciaSeg = 30,    # drift maximo aceito p/ considerar "sincronizado"
    [int]$IntervaloSeg  = 15,    # espera entre ciclos quando ainda nao sincronizou
    [int]$MaxCiclos     = 40     # trava de seguranca (40 x 15s ~= 10 min)
)

$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path

# Garante o System32 no PATH (w32tm/sc/net); algumas sessoes chegam sem ele
$env:Path = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;$env:Path"

# Importa as funcoes (Cronos NTP/HTTP, NTP publico, Set-Date)
. (Join-Path $base 'sync-custom-ntp.ps1')

# ---------------- Log ----------------
$logDir = Join-Path $base 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("sync-hora_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-Log {
    param([ValidateSet('INFO','OK','WARN','ERRO')][string]$Nivel, [string]$Msg)
    $Msg = $Msg -replace '\s*[\r\n]+\s*', ' '   # uma entrada = uma linha no log
    $linha = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Msg
    try { Add-Content -Path $logFile -Value $linha -Encoding UTF8 } catch {}
    Write-Host $linha
}

# ---------------- Metodo Windows (w32tm) ----------------
function Invoke-SyncWindows {
    $ErrorActionPreference = 'Continue'   # stderr de comando nativo nao pode abortar
    try {
        sc.exe config w32time start= auto 2>&1 | Out-Null
        net.exe start w32time 2>&1 | Out-Null

        $out = w32tm /resync /force 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Sucesso = $true; Motivo = ("w32tm /resync OK: {0}" -f (($out -join ' ').Trim())) }
        }
        $erro1 = (($out -join ' ').Trim())

        # Falhou: re-registra o servico de tempo e tenta de novo
        w32tm /unregister 2>&1 | Out-Null
        w32tm /register   2>&1 | Out-Null
        net.exe start w32time 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        $out2 = w32tm /resync /force 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Sucesso = $true; Motivo = ("w32tm /resync OK apos re-registro (1a tentativa: {0}): {1}" -f $erro1, (($out2 -join ' ').Trim())) }
        }
        return @{ Sucesso = $false; Motivo = ("w32tm falhou: {0} | apos re-registro: {1}" -f $erro1, (($out2 -join ' ').Trim())) }
    } catch {
        return @{ Sucesso = $false; Motivo = ("excecao no w32tm: {0}" -f $_.Exception.Message) }
    }
}

# ---------------- Referencias de TESTE (apenas leitura), uma por metodo ----------------
function Get-DriftSeg {
    # Diferenca (s) entre o relogio local e a referencia; $null se a referencia nao respondeu.
    param([Parameter(Mandatory)][scriptblock]$Fonte)
    $ref = & $Fonte
    if ($null -eq $ref) { return $null }
    $drift = [math]::Abs(((Get-Date).ToUniversalTime() - $ref.Utc).TotalSeconds)
    return [pscustomobject]@{ Drift = $drift; Server = $ref.Server }
}

$fonteCronosNtp  = { Get-NtpReferenceUtc -Servers $script:CronosNtpServers }
$fonteCronosHttp = { Get-CronosHttpReferenceUtc }
$fonteWindows    = { Get-NtpReferenceUtc -Servers @('time.windows.com') }
$fontePublica    = { Get-NtpReferenceUtc -Servers $script:NtpServers }

# ---------------- Ordem de execucao ----------------
$metodos = @(
    @{ Nome = 'CRONOS-NTP';  Aplicar = { Set-HoraViaNtp -Servers $script:CronosNtpServers }; Fonte = $fonteCronosNtp  },
    @{ Nome = 'CRONOS-HTTP'; Aplicar = { Set-HoraViaCronosHttp };                            Fonte = $fonteCronosHttp },
    @{ Nome = 'WINDOWS';     Aplicar = { Invoke-SyncWindows };                               Fonte = $fonteWindows    },
    @{ Nome = 'NTP-PUBLICO'; Aplicar = { Set-HoraViaNtp -Servers $script:NtpServers };       Fonte = $fontePublica    }
)

# ================= Loop principal =================
Write-Log 'INFO' ("===== Servico de sincronizacao INICIADO (tolerancia=${ToleranciaSeg}s, intervalo=${IntervaloSeg}s, maxCiclos=${MaxCiclos}) =====")
Write-Log 'INFO' ("Ordem por ciclo: " + (($metodos | ForEach-Object { $_.Nome }) -join ' -> ') + " (testa apos cada metodo)")

$sincronizado   = $false
$metodoVencedor = $null

for ($ciclo = 1; $ciclo -le $MaxCiclos -and -not $sincronizado; $ciclo++) {

    # --- Verificacao inicial do ciclo: referencia NAO-Windows (Cronos NTP; se mudo, Cronos HTTP) ---
    $r = Get-DriftSeg -Fonte $fonteCronosNtp
    if ($null -eq $r) { $r = Get-DriftSeg -Fonte $fonteCronosHttp }

    if ($null -eq $r) {
        Write-Log 'WARN' ("Ciclo {0}: Cronos (NTP e HTTP) sem resposta na verificacao inicial. STATUS=NAO SINCRONIZADO (indeterminado)." -f $ciclo)
    }
    elseif ($r.Drift -le $ToleranciaSeg) {
        Write-Log 'OK' ("Ciclo {0}: relogio JA correto (drift={1:N1}s via {2}). STATUS=SINCRONIZADO." -f $ciclo, $r.Drift, $r.Server)
        $sincronizado   = $true
        $metodoVencedor = 'ja-estava-correto'
        break
    }
    else {
        Write-Log 'INFO' ("Ciclo {0}: drift={1:N1}s (ref {2}). STATUS=NAO SINCRONIZADO. Iniciando metodos em ordem..." -f $ciclo, $r.Drift, $r.Server)
    }

    # --- Metodos em ordem: aplica -> testa; o primeiro teste OK encerra ---
    foreach ($m in $metodos) {
        $nome = $m.Nome
        Write-Log 'INFO' ("Ciclo {0}: [{1}] aplicando..." -f $ciclo, $nome)

        try   { $res = & $m.Aplicar }
        catch { $res = @{ Sucesso = $false; Motivo = ("excecao: {0}" -f $_.Exception.Message) } }

        if ($res -and $res.Sucesso) {
            Write-Log 'INFO' ("Ciclo {0}: [{1}] aplicacao => SUCESSO. {2}" -f $ciclo, $nome, $res.Motivo)
        } else {
            $motivo = if ($res) { $res.Motivo } else { "sem retorno" }
            Write-Log 'WARN' ("Ciclo {0}: [{1}] aplicacao => FALHA. {2}" -f $ciclo, $nome, $motivo)
        }

        # Testa SEMPRE apos o metodo (mesmo se a aplicacao falhou: o relogio pode ja estar certo)
        Start-Sleep -Milliseconds 500
        $t = Get-DriftSeg -Fonte $m.Fonte
        if ($null -eq $t) {
            Write-Log 'WARN' ("Ciclo {0}: [{1}] TESTE indeterminado: referencia do metodo nao respondeu." -f $ciclo, $nome)
        }
        elseif ($t.Drift -le $ToleranciaSeg) {
            Write-Log 'OK' ("Ciclo {0}: [{1}] TESTE OK (drift={2:N1}s verificado em {3}). STATUS=SINCRONIZADO." -f $ciclo, $nome, $t.Drift, $t.Server)
            $sincronizado   = $true
            $metodoVencedor = $nome
            break
        }
        else {
            Write-Log 'WARN' ("Ciclo {0}: [{1}] TESTE REPROVADO (drift={2:N1}s em {3}). Proximo metodo." -f $ciclo, $nome, $t.Drift, $t.Server)
        }
    }

    if (-not $sincronizado -and $ciclo -lt $MaxCiclos) {
        Write-Log 'INFO' ("Ciclo {0}: nenhum teste confirmou a hora. STATUS=NAO SINCRONIZADO. Novo ciclo em {1}s..." -f $ciclo, $IntervaloSeg)
        Start-Sleep -Seconds $IntervaloSeg
    }
}

if ($sincronizado) {
    Write-Log 'OK' ("===== FIM: hora SINCRONIZADA (metodo: {0}). =====" -f $metodoVencedor)
    exit 0
} else {
    Write-Log 'ERRO' ("===== FIM: NAO foi possivel sincronizar apos {0} ciclos. STATUS=NAO SINCRONIZADO. =====" -f $MaxCiclos)
    exit 1
}

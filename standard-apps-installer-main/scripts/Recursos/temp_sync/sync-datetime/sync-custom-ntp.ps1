# sync-custom-ntp.ps1
# Biblioteca de sincronizacao PROPRIA de hora (sem usar o w32tm para sincronizar).
#
# Fontes:
#   - Cronos NTP  : cronos.farmacia.ufmg.br (UDP/123)  -> sistema interno da Farmacia UFMG
#   - Cronos HTTP : https://cronos.farmacia.ufmg.br/time (JSON; GET/443)
#   - NTP publico : NTP.br / Google / Cloudflare / pool.ntp.org (ultimo recurso)
#
# Em todos os casos o relogio e DEFINIDO manualmente com Set-Date, com a hora
# obtida da fonte (como se fosse um acerto manual).
#
# Uso:
#   1) Dot-sourced ( . .\sync-custom-ntp.ps1 ) -> apenas define as funcoes (usado pelo sync-datetime.ps1)
#   2) Executado direto ( .\sync-custom-ntp.ps1 ) -> forca um acerto de hora (Cronos NTP > Cronos HTTP > NTP publico)

# ---------------- Cronos (sistema interno) ----------------
$script:CronosHost = 'cronos.farmacia.ufmg.br'
# IP interno resolvido pelo DNS em 2026-10-08. Usado como 2a opcao do NTP para nao depender de DNS.
# (HTTPS continua usando o hostname: o certificado TLS e do nome e NAO se desativa a verificacao.)
$script:CronosIp          = '150.164.110.1'
$script:CronosNtpServers  = @($script:CronosHost, $script:CronosIp)
$script:CronosHttpUrls    = @("https://$($script:CronosHost)/time", "https://$($script:CronosHost)/api/time")

# ---------------- NTP publico (fallback final) ----------------
$script:NtpServers = @(
    'a.st1.ntp.br',
    'b.st1.ntp.br',
    'a.ntp.br',
    'time.google.com',
    'time.cloudflare.com',
    'pool.ntp.org'
)

$script:NtpMinValida = New-Object System.DateTime(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
$script:NtpMaxValida = New-Object System.DateTime(2100, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)

function Get-NtpUtc {
    # Consulta UM servidor NTP e devolve o horario UTC (DateTime). Lanca excecao em erro.
    param([Parameter(Mandatory)][string]$Server)

    # Pacote NTP de 48 bytes. Primeiro byte 0x1B = LI(0) | VN(3) | Mode(3=client).
    $ntpData = New-Object byte[] 48
    $ntpData[0] = 0x1B

    $socket = New-Object System.Net.Sockets.Socket(
        [System.Net.Sockets.AddressFamily]::InterNetwork,
        [System.Net.Sockets.SocketType]::Dgram,
        [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $socket.ReceiveTimeout = 3000
        $socket.SendTimeout    = 3000
        $socket.Connect($Server, 123)
        [void]$socket.Send($ntpData)
        [void]$socket.Receive($ntpData)
    } finally {
        $socket.Close()
    }

    # Transmit Timestamp: offset 40, big-endian (4 bytes segundos desde 1900 + 4 bytes fracao).
    $intPart = ([uint64]$ntpData[40] -shl 24) -bor ([uint64]$ntpData[41] -shl 16) -bor `
               ([uint64]$ntpData[42] -shl 8)  -bor  [uint64]$ntpData[43]
    $fracPart = ([uint64]$ntpData[44] -shl 24) -bor ([uint64]$ntpData[45] -shl 16) -bor `
                ([uint64]$ntpData[46] -shl 8)  -bor  [uint64]$ntpData[47]

    if ($intPart -eq 0 -and $fracPart -eq 0) {
        throw "Resposta NTP invalida (timestamp zerado) de $Server"
    }

    $milliseconds = ([double]$intPart * 1000) + (([double]$fracPart * 1000) / 4294967296)
    $epoch = New-Object System.DateTime(1900, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    return $epoch.AddMilliseconds($milliseconds)
}

function Get-CronosHttpUtc {
    # Consulta o Cronos via HTTPS e devolve [pscustomobject]{ Utc; Server; Detalhe }.
    # Prefere o JSON documentado (timestamp / unix_time). Se o corpo vier vazio ou invalido,
    # usa o header 'Date' do mesmo servidor (resolucao de 1s). Lanca excecao se nada servir.
    # Compensa metade do RTT. Nao desativa a verificacao TLS.
    param(
        [string[]]$Urls = $script:CronosHttpUrls,
        [int]$TimeoutSec = 5
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ultimoErro = "sem tentativa"

    foreach ($url in $Urls) {
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $r  = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            $sw.Stop()
            $meioRtt = $sw.Elapsed.TotalMilliseconds / 2

            $utc = $null; $detalhe = $null

            # 1) JSON do Cronos
            $corpo = ($r.Content | Out-String).Trim()
            if ($corpo) {
                try {
                    $j = $corpo | ConvertFrom-Json -ErrorAction Stop
                    if ($j.timestamp) {
                        $estilo = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
                        $utc = [DateTimeOffset]::Parse([string]$j.timestamp, [System.Globalization.CultureInfo]::InvariantCulture, $estilo).UtcDateTime
                        $detalhe = "JSON.timestamp"
                    } elseif ($j.unix_time) {
                        $epoch = New-Object System.DateTime(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
                        $utc = $epoch.AddSeconds([double]$j.unix_time)
                        $detalhe = "JSON.unix_time"
                    }
                } catch { $detalhe = $null }
            }

            # 2) Header Date (corpo vazio/invalido)
            if ($null -eq $utc) {
                $d = $r.Headers['Date']
                if ($d -is [array]) { $d = $d[0] }
                if ($d) {
                    $estilo = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
                    $utc = [DateTimeOffset]::Parse([string]$d, [System.Globalization.CultureInfo]::InvariantCulture, $estilo).UtcDateTime
                    $detalhe = "header Date (corpo vazio/invalido; resolucao 1s)"
                }
            }

            if ($null -eq $utc) { throw "resposta HTTP $($r.StatusCode) sem JSON e sem header Date" }

            $utc = $utc.AddMilliseconds($meioRtt)
            if ($utc -lt $script:NtpMinValida -or $utc -gt $script:NtpMaxValida) {
                throw "hora implausivel ($utc UTC)"
            }
            return [pscustomobject]@{ Utc = $utc; Server = $url; Detalhe = $detalhe }
        } catch {
            $ultimoErro = ("{0}: {1}" -f $url, $_.Exception.Message)
        }
    }
    throw $ultimoErro
}

function Get-NtpReferenceUtc {
    # Devolve a primeira hora NTP valida da lista (apenas LEITURA, para verificacao).
    # Retorna [pscustomobject]{ Utc; Server } ou $null se nenhum respondeu.
    param([string[]]$Servers = $script:NtpServers)

    foreach ($s in $Servers) {
        try {
            $utc = Get-NtpUtc -Server $s
            if ($utc -ge $script:NtpMinValida -and $utc -le $script:NtpMaxValida) {
                return [pscustomobject]@{ Utc = $utc; Server = $s }
            }
        } catch {
            # tenta o proximo servidor
        }
    }
    return $null
}

function Get-CronosHttpReferenceUtc {
    # Versao "silenciosa" (apenas LEITURA) para verificacao: $null se o Cronos HTTP nao respondeu.
    try { return (Get-CronosHttpUtc) } catch { return $null }
}

function Set-HoraViaNtp {
    # Busca a hora em NTP e DEFINE o relogio manualmente (sem w32tm).
    # Retorna hashtable { Sucesso; Servidor; Hora; Motivo }. O Motivo lista cada servidor que falhou.
    param([string[]]$Servers = $script:NtpServers)

    $falhas = @()
    foreach ($s in $Servers) {
        try {
            $utc = Get-NtpUtc -Server $s
            if ($utc -lt $script:NtpMinValida -or $utc -gt $script:NtpMaxValida) {
                throw "hora implausivel ($utc UTC)"
            }
            $local = $utc.ToLocalTime()
            Set-Date -Date $local | Out-Null
            $obs = if ($falhas.Count) { " (antes falharam: " + ($falhas -join ' | ') + ")" } else { "" }
            return @{
                Sucesso  = $true
                Servidor = $s
                Hora     = $local
                Motivo   = ("Hora definida via NTP {0} -> {1} (local){2}" -f $s, $local.ToString('yyyy-MM-dd HH:mm:ss'), $obs)
            }
        } catch {
            $falhas += ("{0}: {1}" -f $s, $_.Exception.Message)
        }
    }
    return @{
        Sucesso  = $false
        Servidor = $null
        Hora     = $null
        Motivo   = ("Nenhum servidor NTP respondeu -> " + ($falhas -join ' | '))
    }
}

function Set-HoraViaCronosHttp {
    # Busca a hora no Cronos via HTTPS e DEFINE o relogio manualmente (sem w32tm).
    # Retorna hashtable { Sucesso; Servidor; Hora; Motivo }.
    try {
        $ref   = Get-CronosHttpUtc
        $local = $ref.Utc.ToLocalTime()
        Set-Date -Date $local | Out-Null
        return @{
            Sucesso  = $true
            Servidor = $ref.Server
            Hora     = $local
            Motivo   = ("Hora definida via Cronos HTTP {0} [{1}] -> {2} (local)" -f $ref.Server, $ref.Detalhe, $local.ToString('yyyy-MM-dd HH:mm:ss'))
        }
    } catch {
        return @{ Sucesso = $false; Servidor = $null; Hora = $null; Motivo = ("Cronos HTTP falhou -> {0}" -f $_.Exception.Message) }
    }
}

# ---- Execucao direta (NAO dot-sourced): Cronos NTP > Cronos HTTP > NTP publico ----
if ($MyInvocation.InvocationName -ne '.') {
    $r = Set-HoraViaNtp -Servers $script:CronosNtpServers
    if (-not $r.Sucesso) { Write-Host "[WARN] $($r.Motivo)"; $r = Set-HoraViaCronosHttp }
    if (-not $r.Sucesso) { Write-Host "[WARN] $($r.Motivo)"; $r = Set-HoraViaNtp }
    if ($r.Sucesso) { Write-Host "[OK] $($r.Motivo)"; exit 0 }
    else            { Write-Host "[ERRO] $($r.Motivo)"; exit 1 }
}

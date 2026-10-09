[CmdletBinding()]
param(
    [switch] $Sync
)

# Manual installer and logon action for the FAFAR lab time synchronization task.
# Install from an elevated PowerShell prompt. The scheduled task runs this same
# signed script as LocalSystem when any user logs on.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'FAFAR-SincronizarHoraNoLogon'
$InstallDirectory = Join-Path $env:ProgramFiles 'FAFAR\SyncTime'
$InstalledScript = Join-Path $InstallDirectory 'Sync-TimeAtLogon.ps1'
$LogDirectory = Join-Path $env:ProgramData 'FAFAR\SyncTime'
$LogFile = Join-Path $LogDirectory 'Sync-TimeAtLogon.log'
# This is the only configured time peer; there is no public NTP fallback.
$NtpServer = 'cronos.farmacia.ufmg.br'
$TimeZoneId = 'E. South America Standard Time'
$MaximumLogSizeBytes = 10MB
$RotatedLogCount = 3

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [ValidateSet('INFO', 'DEBUG', 'WARN', 'ERROR')][string] $Level = 'INFO'
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -ge $MaximumLogSizeBytes) {
        for ($index = $RotatedLogCount; $index -ge 1; $index--) {
            $source = if ($index -eq 1) { $LogFile } else { "$LogFile.$($index - 1)" }
            $destination = "$LogFile.$index"
            if (Test-Path -LiteralPath $destination) {
                Remove-Item -LiteralPath $destination -Force
            }
            if (Test-Path -LiteralPath $source) {
                Move-Item -LiteralPath $source -Destination $destination -Force
            }
        }
    }

    $singleLineMessage = ($Message -replace '[\r\n]+', ' | ').Trim()
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fffK'), $Level, $singleLineMessage
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][string] $Description
    )

    $commandText = $FilePath + ' ' + ($Arguments -join ' ')
    Write-Log "DEBUG command start: $Description; command=$commandText" 'DEBUG'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $rawOutput = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $output = (@($rawOutput | ForEach-Object { $_.ToString() }) -join ' | ').Trim()
    }
    catch {
        $exitCode = -1
        $output = $_.Exception.Message
    }
    $timer.Stop()
    Write-Log "DEBUG command end: $Description; exitCode=$exitCode; durationMs=$($timer.ElapsedMilliseconds); output='$output'" 'DEBUG'
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Invoke-TimeSync {
    $runId = [Guid]::NewGuid().ToString('N')
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Log "Início da execução de sincronização; runId=$runId; identity=$identity; computer=$env:COMPUTERNAME; NTP=$NtpServer; timezoneTarget=$TimeZoneId." 'INFO'

    $w32tm = Join-Path $env:SystemRoot 'System32\w32tm.exe'
    $tzutil = Join-Path $env:SystemRoot 'System32\tzutil.exe'

    $config = Invoke-LoggedCommand -FilePath $w32tm -Arguments @('/config', "/manualpeerlist:$NtpServer,0x8", '/syncfromflags:manual', '/update') -Description 'Configurar Cronos como fonte NTP exclusiva'
    if ($config.ExitCode -ne 0) {
        throw "w32tm falhou ao configurar '$NtpServer' (codigo $($config.ExitCode)): $($config.Output)"
    }
    Write-Log "Fonte NTP configurada exclusivamente para $NtpServer (modo cliente)."

    $timeService = Get-Service -Name W32Time
    Write-Log "DEBUG serviço W32Time antes da inicialização: status=$($timeService.Status); startupType=$($timeService.StartType)." 'DEBUG'
    if ($timeService.StartType -eq 'Disabled') {
        Write-Log 'W32Time está desativado; configurando inicialização automática.' 'WARN'
        Set-Service -Name W32Time -StartupType Automatic
    }
    elseif ($timeService.StartType -ne 'Automatic') {
        Write-Log "Configurando W32Time para inicialização automática; startupTypeAnterior=$($timeService.StartType)." 'DEBUG'
        Set-Service -Name W32Time -StartupType Automatic
    }
    if ((Get-Service -Name W32Time).Status -ne 'Running') {
        Write-Log 'Iniciando serviço W32Time.' 'DEBUG'
        Start-Service -Name W32Time
    }
    $timeService = Get-Service -Name W32Time
    Write-Log "DEBUG serviço W32Time após inicialização: status=$($timeService.Status); startupType=$($timeService.StartType)." 'DEBUG'

    # Keep polling on a five-second cadence until timezone and clock source
    # both report the intended state. The task is deliberately allowed to wait
    # through a slow logon or temporary network outage.
    $poll = 0
    while ($true) {
        $cycle = [Diagnostics.Stopwatch]::StartNew()
        $poll++
        Write-Log "DEBUG polling iniciado; runId=$runId; poll=$poll." 'DEBUG'
        $timezoneResult = Invoke-LoggedCommand -FilePath $tzutil -Arguments @('/g') -Description "poll=$poll ler timezone atual"
        $timezone = $timezoneResult.Output.Trim()
        if ($timezone -ne $TimeZoneId) {
            Write-Log "Timezone divergente; poll=$poll; atual='$timezone'; alvo='$TimeZoneId'. Aplicando fuso alvo." 'WARN'
            $setTimezone = Invoke-LoggedCommand -FilePath $tzutil -Arguments @('/s', $TimeZoneId) -Description "poll=$poll definir timezone"
        }
        else {
            Write-Log "DEBUG timezone já corresponde ao alvo; poll=$poll; timezone='$timezone'." 'DEBUG'
        }

        # Use the Windows Time NTP client itself for the attempt. The separate
        # w32tm /stripchart diagnostic sends an older NTP packet version that
        # Cronos intentionally rejects, so it cannot be used as a gate here.
        $resyncResult = Invoke-LoggedCommand -FilePath $w32tm -Arguments @('/resync', '/rediscover') -Description "poll=$poll solicitar sincronização do Windows Time com o Cronos"
        $resyncSucceeded = ($resyncResult.ExitCode -eq 0)

        $timezoneCheck = Invoke-LoggedCommand -FilePath $tzutil -Arguments @('/g') -Description "poll=$poll confirmar timezone"
        $timezone = $timezoneCheck.Output.Trim()
        $sourceCheck = Invoke-LoggedCommand -FilePath $w32tm -Arguments @('/query', '/source') -Description "poll=$poll consultar fonte de horário ativa"
        $source = $sourceCheck.Output.Trim()
        $validTimeSource = ($source -match [regex]::Escape($NtpServer))
        Write-Log "DEBUG verificação do estado; runId=$runId; poll=$poll; timezone='$timezone'; timezoneCorreto=$($timezone -eq $TimeZoneId); fonte='$source'; fonteCorreta=$validTimeSource; resyncBemSucedido=$resyncSucceeded." 'DEBUG'

        if ($timezone -eq $TimeZoneId -and $resyncSucceeded -and $validTimeSource) {
            Write-Log "Sincronização concluída; runId=$runId; poll=$poll; timezone='$timezone'; fonte='$source'." 'INFO'
            return
        }

        Write-Log "Aguardando próxima tentativa; runId=$runId; poll=$poll; timezoneCorreto=$($timezone -eq $TimeZoneId); resyncBemSucedido=$resyncSucceeded; fonteCorreta=$validTimeSource." 'INFO'

        $remainingMilliseconds = [Math]::Max(0, 5000 - [int]$cycle.ElapsedMilliseconds)
        Write-Log "DEBUG pausa antes do próximo polling; runId=$runId; poll=$poll; elapsedMs=$($cycle.ElapsedMilliseconds); sleepMs=$remainingMilliseconds." 'DEBUG'
        if ($remainingMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $remainingMilliseconds
        }
    }
}

function Install-LogonTask {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute a instalacao em uma janela do PowerShell aberta como Administrador.'
    }
    Write-Log "Iniciando instalação; identity=$($identity.Name); computer=$env:COMPUTERNAME; sourceScript=$PSCommandPath; installPath=$InstalledScript; taskName=$TaskName." 'INFO'

    if (-not (Test-Path -LiteralPath $InstallDirectory)) {
        New-Item -Path $InstallDirectory -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $sourceScript = $PSCommandPath
    if (-not $sourceScript) {
        throw 'Salve este arquivo como Sync-TimeAtLogon.ps1 antes de instala-lo.'
    }
    if ([IO.Path]::GetFullPath($sourceScript) -ne [IO.Path]::GetFullPath($InstalledScript)) {
        Copy-Item -LiteralPath $sourceScript -Destination $InstalledScript -Force
        $sourceHash = (Get-FileHash -LiteralPath $sourceScript -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -LiteralPath $InstalledScript -Algorithm SHA256).Hash
        Write-Log "Script copiado para o diretório de instalação; sourceSHA256=$sourceHash; installedSHA256=$installedHash; hashesMatch=$($sourceHash -eq $installedHash)." 'INFO'
    }
    else {
        Write-Log 'Script já está no diretório de instalação; cópia ignorada.' 'DEBUG'
    }

    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoLogo -NoProfile -NonInteractive -File `"$InstalledScript`" -Sync"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
    Write-Log "DEBUG registrando tarefa; executable=$($action.Execute); arguments=$($action.Argument); trigger=AtLogOn(any user); principal=SYSTEM; runLevel=Highest; executionTimeLimit=0." 'DEBUG'

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settings -Description 'Define o fuso horario FAFAR e sincroniza o relogio no logon de qualquer usuario.' -Force | Out-Null
    $task = Get-ScheduledTask -TaskName $TaskName
    Write-Log "Tarefa '$TaskName' registrada; state=$($task.State); taskPath=$($task.TaskPath); principal=$($task.Principal.UserId)." 'INFO'

    # Start the registered SYSTEM task now; it will also run on future logons.
    Start-ScheduledTask -TaskName $TaskName
    Write-Log "Tarefa '$TaskName' iniciada para sincronização imediata; próxima execução automática em cada logon." 'INFO'
    Write-Host "Instalacao concluida. A tarefa iniciou a sincronizacao e sera executada no logon de qualquer usuario."
    Write-Host "Log: $LogFile"
}

try {
    if ($Sync) {
        Invoke-TimeSync
    }
    else {
        Install-LogonTask
    }
}
catch {
    try { Write-Log "Falha não tratada; exceptionType=$($_.Exception.GetType().FullName); message=$($_.Exception.Message); scriptStackTrace=$($_.ScriptStackTrace); position=$($_.InvocationInfo.PositionMessage)." 'ERROR' } catch { }
    Write-Error $_
    exit 1
}

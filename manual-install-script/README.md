# Sincronização de horário no logon (Windows)

Este pacote instala manualmente uma tarefa agendada em cada computador. A tarefa é acionada quando qualquer usuário faz logon e roda como `SYSTEM`, com privilégios suficientes para configurar o serviço de horário do Windows. Não usa WinRM nem instala um serviço de terceiros.

O arquivo [Sync-TimeAtLogon.ps1](Sync-TimeAtLogon.ps1) executa duas ações:

1. Define o fuso horário do laboratório como `E. South America Standard Time` (UTC−03:00, São Paulo).
2. Solicita a sincronização do relógio pelo serviço nativo Windows Time (`W32Time`) com `cronos.farmacia.ufmg.br`, usando NTP em UDP/123.

O NTP corrige o instante do relógio; ele não define fuso horário. Por isso o script configura e verifica o fuso separadamente. Após o logon, a tarefa solicita ao cliente NTP nativo do Windows uma sincronização com o Cronos e verifica o fuso e a fonte de horário ativa. Continua tentando a cada cinco segundos até confirmar ambos; se a rede estiver indisponível, a tarefa permanece aguardando. Não usa `w32tm /stripchart` como teste, pois essa sonda diagnóstica envia pacotes de versão antiga que o Cronos rejeita. Não consulta servidores NTP públicos, serviços de horário na internet nem usa um fallback externo.

O serviço NTP do Cronos fornece a hora do relógio do sistema no host onde ele roda. O código cliente deste repositório não consulta uma fonte externa. A configuração do relógio do sistema operacional do host Cronos, porém, é feita fora deste script e precisa ser conferida no próprio servidor. NTP transmite o instante UTC, não o timezone; neste cliente, o fuso é definido pela política fixa do laboratório (`E. South America Standard Time`).

## Instalação manual

1. Copie a pasta para o computador, mantendo `Instalar-SyncTime.cmd` e `Sync-TimeAtLogon.ps1` juntos. Se a instituição fornecer uma cópia assinada, use essa cópia sem editar o arquivo.
2. Clique duas vezes em `Instalar-SyncTime.cmd` e confirme a solicitação do **Controle de Conta de Usuário (UAC)**. O instalador abre o PowerShell elevado e executa o script de sincronização. Ele não altera a política de execução do PowerShell; se essa política bloquear o arquivo, siga as orientações da seção sobre distribuição confiável abaixo.
3. A instalação copia o script para `C:\Program Files\FAFAR\SyncTime`, cria a tarefa `FAFAR-SincronizarHoraNoLogon` para logon de qualquer usuário e inicia a tarefa em segundo plano. Ela solicita a sincronização pelo Windows Time e verifica a cada cinco segundos até confirmar o fuso e a fonte de horário; se Cronos ou a rede não responderem, continuará tentando. A tarefa também será acionada nos próximos logons.
4. Para conferir a tarefa, abra **Agendador de Tarefas → Biblioteca do Agendador de Tarefas** e localize `FAFAR-SincronizarHoraNoLogon`. O log detalhado fica em `C:\ProgramData\FAFAR\SyncTime\Sync-TimeAtLogon.log`.

O arquivo registra em nível detalhado cada polling, timezone observado e definido, saída e código de retorno dos comandos `w32tm`/`tzutil`, fonte NTP ativa, estado do serviço Windows Time, instalação/início da tarefa e erros. Quando o log chega a 10 MB, ele é rotacionado; ficam o arquivo atual e até três versões anteriores com sufixos `.1`, `.2` e `.3` no mesmo diretório.

O instalador deve ser executado uma vez por computador com uma conta administradora. A rede precisa resolver `cronos.farmacia.ufmg.br` para o endereço interno alcançável e permitir tráfego NTP de saída em UDP/123. Para eliminar também a dependência de DNS, confirme o IP interno fixo do host Cronos e substitua `$NtpServer` no script por esse IP antes de distribuir a cópia assinada. Não use um IP público ou de proxy.

O script configura Cronos como fonte manual exclusiva do Windows Time, inclusive em computadores associados a domínio. Se GPO, MDM ou outra gestão central impuser uma fonte diferente, essa política precisa ser ajustada pela equipe responsável; a tarefa continuará tentando até o Windows confirmar Cronos como fonte ativa.

## Como distribuir com confiança e reduzir falsos positivos

Não existe configuração de script que garanta que todos os antivírus o considerarão seguro. A decisão depende do conteúdo, da reputação do arquivo e das políticas da organização. O script é texto PowerShell legível e usa ferramentas nativas do Windows; não baixa código, não desativa proteções e não altera exclusões do antivírus.

Para distribuição institucional:

1. Revise o conteúdo e mantenha o script em controle de versão. Distribua sempre a versão aprovada por um canal institucional autenticado.
2. Assine o arquivo final com um certificado **Authenticode de assinatura de código** emitido por uma autoridade confiável para os computadores do laboratório. Distribua a cadeia/certificado conforme a política de TI e assine a versão final depois de qualquer alteração. Uma edição posterior invalida a assinatura.
3. Verifique a assinatura antes da instalação com `Get-AuthenticodeSignature .\Sync-TimeAtLogon.ps1`; o estado esperado é `Valid` e o editor deve ser o certificado institucional reconhecido.
4. Se Microsoft Defender, Avast ou outro produto ainda sinalizar a versão assinada, não desative o antivírus nem restaure o arquivo às cegas. Confirme a assinatura e o hash SHA-256 (`Get-FileHash .\Sync-TimeAtLogon.ps1 -Algorithm SHA256`), envie o arquivo ao fornecedor como possível falso positivo e peça à equipe de TI uma regra de permissão central, restrita ao editor assinado ou ao hash aprovado e conforme as capacidades do produto.
5. Não crie exclusões amplas para pastas, PowerShell ou processos, não use `ExecutionPolicy Bypass` e não instrua usuários a ignorar alertas. Se a política de execução exigir scripts assinados, mantenha-a: o script precisa estar assinado por um editor confiável.

Assinatura válida ajuda a identificar o editor e detectar alterações, mas não é uma garantia universal de ausência de alertas. SmartScreen e produtos antimalware podem considerar reputação e política local além da assinatura.

## Remover

Como Administrador, remova a tarefa no Agendador de Tarefas e, depois de confirmar que nenhuma política institucional depende dela, remova os arquivos em `C:\Program Files\FAFAR\SyncTime` e o log em `C:\ProgramData\FAFAR\SyncTime`. A configuração do serviço Windows Time/fuso fica no sistema; ajuste-a conforme a política de horário da instituição.

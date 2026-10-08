# Handoff — Sincronização de Hora (Cronos/FAFAR)

Status em 08/10/2026. Documento pra continuar de onde parei — contexto rápido antes de tocar em qualquer coisa aqui.

## O que é

Substituição do sync de hora antigo (so `w32tm`/NTP público) por um serviço mais robusto que prioriza o servidor interno da Farmácia (**Cronos**), com fallback em cascata. Roda como tarefa agendada `SyncTimeAtLogon` (SYSTEM) em cada PC do laboratório.

Ordem de tentativa, testando o relógio depois de cada etapa (para na primeira que confirmar o horário certo):
1. **Cronos NTP** — `cronos.farmacia.ufmg.br` (UDP/123) → `Set-Date` manual
2. **Cronos HTTP** — `https://cronos.farmacia.ufmg.br/time` → `Set-Date` manual
3. **Windows** — `w32tm /resync`
4. **NTP público** — NTP.br / Google / Cloudflare (último recurso)

## Arquivos envolvidos

- `scripts/Recursos/sync-datetime.zip` — **é este arquivo que o deploy real usa** (`disparar_deploy_laboratorio_paralelo.ps1` copia e extrai ele em `C:\sync-datetime` em cada PC, depois roda `scheduale-sync.bat`).
- `scripts/Recursos/extracted_zip/*` e `scripts/Recursos/temp_sync/sync-datetime/*` — duas cópias soltas do conteúdo do zip, aparentemente usadas como staging/teste local. **Estão duplicadas e com diffs idênticos no momento** — se forem editar o conteúdo, teem que atualizar as duas pastas (ou melhor, decidir qual é a fonte de verdade e remover a outra, pra não perder sincronismo entre elas e o zip).
- `scripts/03-Deploy-Massa/forcar_sincronizacao_hora.ps1` — dispara `Start-ScheduledTask SyncTimeAtLogon` em massa (já migrado pro padrão de auto-detecção de sub-rede).
- `scripts/04-Diagnostico/verificar_horario.ps1` — **novo**, verifica drift de horário em todos os PCs ligados, comparando com o relógio do Host.
- `OPERACOES_RAPIDAS.md` — já atualizado com a seção 4 (sync de hora) e o novo diagnóstico.

## O que já foi validado (testado ao vivo no host 192.168.137.16)

- ✅ **Cronos HTTP funciona**, mas com uma pegadinha: os endpoints (`/time`, `/api/time`, `/`) respondem HTTP 200 com **corpo vazio** (sem JSON). O código já lida com isso corretamente — cai pro header `Date` da resposta (resolução de 1s). Validado: drift de 0,5s após sync.
- ❌ **Cronos NTP via UDP/123 não responde** a partir do `.16` (timeout). Confirmado em duas rodadas de teste. DNS resolve certo (`150.164.110.1`). Suspeita: firewall bloqueando UDP/123 de saída nessa rede — **precisa confirmar com quem administra o Cronos/firewall do lab** se isso é esperado. Enquanto não resolver, o serviço sempre vai cair pro fallback HTTP (funciona, só não é o caminho "ideal").
- ✅ Rodei o `sync-datetime.ps1` + `sync-custom-ntp.ps1` reais do projeto (sem alteração) direto no `.16` via WinRM — concluiu com sucesso, log OK.
- ✅ **Nenhuma quarentena do Avast** observada — nem numa versão mínima (só `Set-Date` + Cronos, sem tarefa agendada), nem rodando os scripts completos do projeto no host de teste.

## Pendente / próximos passos

1. **Confirmar com o admin do Cronos se UDP/123 deveria estar acessível** da rede do laboratório. Se não for pra abrir, vale ajustar a ordem/prioridade dos métodos no `sync-custom-ntp.ps1` (ou documentar que HTTP é o caminho normal, não NTP).
2. **Testar o caminho de correção de verdade**: só testei com o relógio já certo (`drift=0.5s`, saiu no "ja-estava-correto"). Falta forçar um relógio errado num PC de teste e confirmar que o loop corrige e sai corretamente pelo método certo.
3. **Testar o fluxo completo da tarefa agendada** (`scheduale-sync.bat` → SYSTEM + `icacls` travando a pasta) no host de teste — só validei o script `.ps1` isolado, não a tarefa agendada+lock de permissão juntos. Minha suspeita é que SE o Avast flagar algo, é essa combinação (persistência SYSTEM + alteração de hora + lock de pasta), não o `Set-Date` isolado.
4. **Se aparecer flag de antivírus na combinação completa**, os caminhos já mapeados (em ordem de preferência) são:
   - Reportar como falso positivo pro Avast Threat Labs (resolve pra todos os PCs via definição de vírus, sem tocar em nada local);
   - Exceção via console central do Avast Business (se houver) ou manual pela UI em cada PC;
   - Assinatura Authenticode (mesmo autoassinada) do `.ps1`, com o certificado importado como Trusted Publisher nos PCs.
   - **Importante: não contornar/desativar a auto-defesa do Avast via script** — isso é evasão de proteção e foi descartado como opção, independente do cenário.
5. Depois de validar os passos 2 e 3, rodar `forcar_sincronizacao_hora.ps1` pra todo o laboratório e conferir com `verificar_horario.ps1`.

## Rede/credenciais (igual ao resto do projeto)

- Sub-rede: `192.168.137.0/24`, WinRM porta `5985`.
- Credenciais: ver `OPERACOES_RAPIDAS.md` (seção "CREDENCIAIS PADRAO") / `CLAUDE.md`.
- Host de teste usado nesta rodada: `192.168.137.16` (tinha Avast instalado, confirmado).

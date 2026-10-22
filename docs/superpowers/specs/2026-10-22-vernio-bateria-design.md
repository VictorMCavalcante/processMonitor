# Vernio — Bateria e energia

Data: 22/10/2026. Continua os designs anteriores (v1, v2, Disco, Disco v2 + GPU) e a marca Vernio. Continuam valendo:
- nunca fazer nada sozinho;
- leve;
- Swift nativo sem dependências;
- pt-BR;
- tema violeta;
- zero comentários no código;
- commits em inglês sem coautoria.

O nome visível é Vernio; o código continua `Monitor`/`MonitorCore`.

## Por que

O Victor não sabe por que a bateria às vezes dura muito e às vezes pouco ("é um controle que não tenho direito"). O controle de bateria do macOS mostra só um "impacto energético" sem explicar o motivo. Ele pediu "o melhor", deu carta branca ("pode fazer tudo, confio em você") e quer algo que diga o que gasta, por quê, e que ajude a otimizar.

O levantamento de 22/10 no Mac dele (MacBook Pro M4 Pro) achou:

- **Um processo travado:** `supabase db query --linked …` estava travado havia 4h40 a ~150% de CPU, com nota de energia 127 contra 11 do segundo colocado. Foi encerrado com o consentimento dele.
- **Sessões do Claude Code** rodam `caffeinate -i -t 300` em loop, o que impede o sono ocioso.
- **Despertares durante o sono:** em 7 dias de log foram ~270 por Wi‑Fi/Bluetooth (TCP keepalive, push) e ~99 pelo relógio interno (rtc), além de vários "Dark Wake Thermal Emergency".
- **Sessões na bateria (calculadas do `pmset -g log`):**
  - 15→16/10: de 99% a 15% em 30 h (2,8%/h).
  - 16→19/10: 0,1%/h, quase só dormindo.
- **Saúde:** 93% da capacidade original, 113 ciclos, condição Normal.

## Fontes de dados verificadas (sem administrador)

| Dado | Fonte | Observação |
|---|---|---|
| Energia por processo | `proc_pid_rusage(RUSAGE_INFO_V6).ri_energy_nj` (nanojoules acumulados) | Só os processos do próprio usuário; os do sistema/root dão erro. Ex.: ghostty 155 mW, Vernio 31 mW. |
| Despertares da CPU por processo | `ri_interrupt_wkups` + `ri_pkg_idle_wkups` | Mesma chamada. Ex.: ghostty 333/s. |
| Potência total do Mac | `AppleSmartBattery` → `PowerTelemetryData.SystemLoad` (mW) | Funciona também na tomada. Ex.: 23,2 W. |
| Estado da bateria | `IOPSCopyPowerSourcesInfo` e `AppleSmartBattery` | %, carregando, na tomada, `AppleRawCurrentCapacity`/`AppleRawMaxCapacity`/`DesignCapacity`, `CycleCount`, `Temperature`, `Voltage`, `Amperage`. |
| Quem impede o sono | `IOPMCopyAssertionsByProcess` | PID → tipos de bloqueio, como `PreventUserIdleSystemSleep`, `PreventUserIdleDisplaySleep` e `UserIsActive`. |
| Histórico de despertares e sessões na bateria | `pmset -g log` | Os últimos ~7 dias. Só sob demanda, nunca no ciclo. |
| GPU e CPU por processo | já coletados pelo Vernio | |

Temperatura e potência por componente via `powermetrics` exigem administrador e ficam fora.

## Objetivos (o Victor delegou as decisões, todas são do Claude)

1. **Aba "Bateria" na janela**, em SISTEMA, depois de Disco. Em Macs sem bateria, a aba mostra só energia e consumo total.
2. **Agora:**
   - Card com a carga (%), o estado (na bateria / carregando / carregada), a potência total em W e uma previsão honesta: "no ritmo dos últimos 10 min, dura 4h20". A previsão é calculada pelo Vernio a partir da queda real; quando não há dados suficientes, mostra "calculando…".
   - Card de saúde: capacidade atual em relação à original (%), ciclos, temperatura.
3. **Quem está gastando**, a lista principal, agrupada por app e por projeto, como o resto do app:
   - **Ordem:** pela energia nos últimos 10 min, mostrada em mW e em % da energia dos processos do usuário.
   - **Motivo em linguagem simples**, o principal fator de cada item:
     - "CPU alta (85%)";
     - "GPU (40%)";
     - "acorda a CPU 333×/s";
     - "impede o Mac de dormir";
     - "rodando há 4 h sem uso".
   - Ação "Fechar" com as mesmas regras e confirmações de hoje.
   - A energia que não dá para atribuir (sistema, tela, Wi‑Fi) aparece numa linha "Sistema e tela", calculada como potência total menos a soma medida, para o total fechar.
4. **Impedindo o sono:** a lista de bloqueios ativos com nome legível:
   - `caffeinate` filho do Claude Code vira "Claude Code está impedindo o Mac de dormir";
   - powerd vira "tela ligada";
   - videochamadas aparecem pelo nome.

   Cada bloqueio mostra há quanto tempo está ativo e uma ação ("Fechar" o dono quando for permitido).
5. **Sessões na bateria (histórico):**
   - **Gravação:** cada vez que o Mac sai da tomada, o Vernio grava uma sessão. Ele guarda início, fim, % inicial e final, horas acordado e dormindo, consumo médio acordado (%/h) e os 5 maiores consumidores de energia (por app) somados na sessão.
   - **Lista:** últimas 14 sessões, com uma comparação simples: "esta sessão gastou 2× mais que a sua média; principais diferenças: supabase, Docker".
   - **Retroativo:** as sessões dos últimos 7 dias são reconstruídas do `pmset -g log`, só com % e duração, sem consumidores, para a aba não começar vazia.
6. **Sono e despertares (últimos 7 dias, do `pmset -g log`):** contagem de despertares por motivo legível ("Wi‑Fi/Bluetooth (rede e notificações)", "relógio (tarefas agendadas)", "teclado/mouse", "tampa/USB-C"), alertas térmicos durante o sono e quanto a bateria caiu dormindo (%/h).
7. **Sugestões (o Victor aprova; nada é automático).** Um bloco "Como economizar", com até 4 sugestões, cada uma com o ganho estimado e a ação:
   - **Processo descontrolado consumindo muito:** usa a regra de descontrolado do Vernio aplicada à energia. Ação: fechar, com confirmação.
   - **Bloqueio de sono parado há mais de 30 min sem o usuário ativo.** Ação: fechar o dono.
   - **Servidor de dev ou banco ligado há mais de 8 h na bateria.** Ação: fechar.
   - **Muitos despertares por rede no sono:** mostra o comando que reduz isso. Ex.: "Ajustes › Bateria › Opções › Acordar para acesso à rede: Nunca na bateria", ou `sudo pmset -b tcpkeepalive 0`. O Vernio **não** executa nada que exija administrador; só copia o comando.
   - **Brilho/tela:** fica fora (não é medido por processo).
8. **Barra de menus e popover:**
   - No popover, uma linha "Bateria 64% · 14 W · ~4h20" quando estiver na bateria, e o maior consumidor quando ele passar de 30% da energia dos processos.
   - A barra de menus não muda.
9. **Alerta:** notificação quando um processo passar de 2 W de média por 10 min estando na bateria. Usa a mesma política anti-repetição e "sempre ignorar" dos outros alertas.

## Não-objetivos

- Mudar configurações do sistema, rodar `pmset`/`sudo`, controlar brilho ou modo de pouca energia.
- Dados de `powermetrics` ou de processos de outros usuários (root) por processo.
- Prever a vida útil da bateria, ou "calibrar".

## Anti-objetivos

- **O próprio Vernio pesar.** A coleta de energia entra no ciclo atual, que já lê `proc_pid_rusage`; basta trocar para V6. A leitura da bateria é barata (IOKit). O `pmset -g log` só roda ao abrir a aba Bateria e no máximo a cada 10 min. A meta de consumo com a janela fechada continua (~0,6% de CPU, ~20 MB).
- **Números falsos com cara de precisos.** Toda estimativa (previsão, "Sistema e tela", ganho de uma sugestão) é marcada como estimativa ("~", "estimado") e tem regra clara de quando aparece.
- **Atribuir a energia de outro processo** por reuso de PID: zera o histórico quando a hora de início muda, como CPU e GPU já fazem.
- **Sugestão que causa dano:** nunca sugerir fechar processo do sistema ou de outro usuário, nem apps protegidos pelas regras atuais.

## Decisões de detalhe (Claude)

- **Janela "agora":** média móvel de 10 min para energia, potência e previsão. A previsão só aparece depois de pelo menos 3 min na bateria e com queda de pelo menos 1%.
- **Persistência:**
  - O histórico de sessões vai para `~/Library/Application Support/Monitor/battery-sessions.json`, como os picos, guardando no máximo 60 sessões.
  - Uma sessão aberta é gravada a cada 5 min, para não se perder se o app fechar.
- **Atribuição por app:** usa os grupos "Por app" e "Por projeto" que já existem. Ex.: os helpers do Chrome somam no Chrome; o node do systemwra soma no projeto systemwra.
- **Motivo principal:** CPU acima de 50% de um núcleo, senão GPU acima de 20%, senão mais de 100 despertares/s, senão bloqueio de sono, senão "uso leve". Vence o que contribuir mais. Os limites ficam ajustáveis no código como constantes.
- **Fora do Mac com bateria:** a aba mostra só energia, potência total e bloqueios de sono, e o card de bateria e as sessões somem.

## Deixado para quem construir

- **Leitura dos dados:** como ler `PowerTelemetryData` via IOKit (sem `ioreg` subprocesso) e o parser do `pmset -g log`, com os formatos de exemplo nas saídas acima.
- **Layout:** o layout exato da aba, seguindo o visual atual (cards, listas, cores de status).
- **Estrutura do código:** a divisão em arquivos.

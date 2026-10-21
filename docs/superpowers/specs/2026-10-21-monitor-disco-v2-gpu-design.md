# Monitor — aba Disco v2 e GPU

Data: 21/10/2026. Continuação de `2026-10-20-monitor-disco-design.md` (aba Disco), da v2 e da v1. Continuam valendo as restrições e anti-objetivos desses documentos:
- nunca fazer nada sozinho;
- leve;
- Swift nativo sem dependências;
- pt-BR;
- tema da v1;
- zero comentários;
- commits em inglês sem coautoria.

São duas partes independentes, feitas nesta ordem: **A. Disco v2**, depois **B. GPU**.

---

## A. Disco v2

### Por que

O Victor usou a aba Disco recém-lançada e teve dois incômodos:
- **"A análise demora muito e não mostra progresso."** Ela leva cerca de 76 s no Mac dele e fica parada num spinner.
- **"O wallpaper do Mac eu não consigo excluir por lá."** São 9,7 GB de vídeos aéreos que aparecem só como informativo.

### Objetivos (aprovados pelo Victor)

1. **Progresso visível.** Durante a análise, o topo mostra a etapa atual e o avanço. Por exemplo:
   - "Medindo node_modules… 12 de 33"
   - "Medindo dados de apps… Steam"

   Cada seção aparece preenchida assim que a sua parte termina, sem esperar o resto.
2. **Última análise na hora.** Ao abrir a aba, o último resultado aparece imediatamente, mesmo depois de reiniciar o app, com "analisado há X". A nova análise roda por cima e substitui as seções conforme terminam.
3. **Mais rápida.** As partes independentes são medidas em paralelo: `node_modules`, caches do catálogo, sobras e dados de apps.
4. **Wallpapers apagáveis.** Os vídeos em `~/Library/Application Support/com.apple.wallpaper/aerials/videos` saem de "Seus dados" e viram um item de **Seguro** com estas características:
   - título "Wallpapers e protetores aéreos";
   - aviso "o macOS baixa de novo se você usar um fundo animado";
   - **marcado por padrão**;
   - vai para a Lixeira como os demais.

   O Victor confirmou que não usa fundos nem protetores animados.

### Não-objetivos

- Analisar em segundo plano com a janela fechada, ou de tempos em tempos. Continua sob demanda: ao abrir a aba ou no ↻.
- Detectar qual vídeo aéreo está em uso para preservá-lo.
- Mexer em `/Library/Application Support/com.apple.idleassetsd`, que é do sistema e exige permissão de administrador.

### Anti-objetivos

- A paralelização deixar a janela travada ou fazer o app pesar mais. A análise continua fora da thread principal e com no máximo poucas tarefas simultâneas.
- O resultado salvo em disco mostrar como existente algo que já foi limpo. Depois de limpar, o salvo é atualizado com a nova análise.
- Contagem duplicada voltar por causa do paralelismo. Cada byte continua numa categoria só, com a prioridade Seguro > Sobras > Dados.

### Como deve se comportar

- **Etapas mostradas:**
  - "Listando apps instalados"
  - "Medindo caches"
  - "Medindo node_modules… N de M"
  - "Procurando sobras"
  - "Medindo dados de apps… <nome>"
  - "Medindo Docker"

  O texto fica no lugar de "analisado há X", com uma barra fina de progresso quando o total é conhecido.
- **Seções conforme terminam:**
  - **Seguro:** aparece quando os caches e `node_modules` terminam.
  - **Sobras:** aparece depois que Seguro termina, porque depende dos caminhos já contados.
  - **Dados:** aparece por último.

  Os cards e a barra do disco se atualizam a cada seção.
- **Resultado salvo:**
  - O último relatório fica salvo em `~/Library/Application Support/Monitor/`, no mesmo esquema do histórico de picos (`PeakStore`).
  - Ao abrir a aba, o salvo aparece na hora. Se tiver mais de 1 h, a nova análise começa sozinha. Se tiver menos, só começa com ↻ (escolha do Claude).
  - Arquivo corrompido ou ausente: começa vazio, sem travar.
- **Durante a análise:** os botões de limpar ficam desabilitados, como já são hoje.
- **Meta de tempo** (escolha do Claude): analisar o Mac do Victor em ≤ 30 s, com Docker fechado. Quem construir mede antes e depois e informa os números.

---

## B. GPU

### Por que

O btop mostra a GPU, e o Victor quer "saber tudo que é interessante" sobre ela no Monitor. O Mac dele é um **M4 Pro com GPU de 16 núcleos**.

O levantamento de 21/10 mostrou que, sem senha de administrador, o macOS expõe dois tipos de dado. No registro de hardware (IOKit, classe `IOAccelerator`), em `PerformanceStatistics`, estão:
- `Device Utilization %` (uso total);
- `Renderer Utilization %`;
- `Tiler Utilization %`;
- `In use system memory` (memória de GPU em uso);
- `Alloc system memory`.

Por processo, há o tempo acumulado de GPU por cliente: `AGXDeviceUserClient`, com `IOUserClientCreator = "pid N, nome"` e `accumulatedGPUTime` em nanossegundos.

### Objetivos (aprovados pelo Victor)

1. **Card "GPU"** ao lado de CPU e Memória, com:
   - o % de uso total e o sparkline;
   - embaixo, "X GB de memória de GPU", vindo de `In use system memory`.
2. **GPU % por processo.** A lista mostra a coluna GPU %, somada por app e por projeto nos grupos, como a CPU, e permite ordenar por ela. O % é o tempo de GPU consumido no intervalo dividido pelo tempo decorrido, com teto de 100%.
3. **Painel de detalhes** mostra "GPU: X%" junto de CPU e Memória.
4. **Descontrolado por GPU:** processo acima de 80% de GPU de forma contínua por 5 min ou mais. Etiqueta, dica e notificação seguem as mesmas regras da CPU: só processos do próprio usuário que o Monitor deixa fechar, e respeitando "sempre ignorar".
5. **Picos:** cada episódio de pico de pressão também guarda os 3 maiores consumidores de GPU no momento do pico. A tela de Picos mostra esses consumidores quando existirem.
6. **Popover:** uma linha "GPU X%" junto da linha de CPU. A barra de menus não muda.

### Não-objetivos

- Temperatura, consumo em watts e frequência da GPU. Exigem `powermetrics` com administrador ou SMC privado, que muda entre versões. O Victor aceitou deixar de fora.
- Gráficos separados de Renderer e Tiler. Esses valores podem aparecer como detalhe no card, mas não ganham card próprio (escolha do Claude).
- GPU de Macs Intel ou eGPU. Se a leitura falhar, o card mostra "–" e nada quebra.

### Anti-objetivos

- **Pesar o app.** A leitura da GPU entra no ciclo atual de 3 s/10 s e deve ser feita direto pelo IOKit dentro do processo, sem rodar `ioreg` a cada ciclo.
- **Atribuir GPU errada a um processo:**
  - Quando um PID é reutilizado, o histórico zera, como já faz o rastreador de CPU.
  - O primeiro ciclo de um processo mostra 0%, não o acumulado desde que ele abriu.
- **Alerta falso** de descontrolado em jogos ou apps de vídeo usados de propósito por pouco tempo. Valem os mesmos 5 minutos contínuos da CPU.

### Decisões do Claude (o Victor pode mudar)

- O % de GPU por processo é relativo à GPU inteira, com teto de 100%, não por núcleo.
- Processos do sistema, como o `WindowServer`, aparecem com GPU % na lista, mas não geram alerta.
- Picos antigos, gravados sem dados de GPU, continuam abrindo normalmente: o campo novo é opcional.

### Decisões do Claude após a revisão

- **Relatório salvo é só para olhar.** Os botões de limpar só ficam habilitados depois que uma análise desta sessão termina. Assim, "em uso", apps abertos e caminhos sumidos estão sempre atualizados na hora de limpar.
- **Paralelismo com prioridade.** Os tamanhos são medidos em paralelo. A atribuição a cada categoria e o desconto do que já foi contado seguem a ordem Seguro > Sobras > Dados.
- **Wallpapers.** Só a pasta `aerials/videos` vai para Seguro. O resto de `com.apple.wallpaper` continua em Dados, se passar de 1 GB.
- **GPU por processo.** Vários clientes do mesmo PID são somados. Uma diferença negativa, quando um cliente fecha, conta como 0.
- **GPU nos descontrolados e picos.** O alerta usa o mesmo rastreador da CPU. Os 3 maiores de GPU num pico são gravados no mesmo momento em que o pico grava os maiores de memória.

## Deixado para quem construir

- **Leitura via IOKit:** como ler `PerformanceStatistics` e os `AGXDeviceUserClient`, ou seja, o caminho no registro, as chaves e o tratamento de chaves ausentes.
- **Arquitetura:** o formato do arquivo do relatório salvo e como dividir o analisador em etapas com callback de progresso.
- **Paralelismo:** a quantidade de tarefas paralelas.
- **Visual:** o layout da linha de progresso e da coluna de GPU, seguindo o visual atual.

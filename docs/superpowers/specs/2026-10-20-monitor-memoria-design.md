# Monitor de processos e memória para macOS — design

Data: 20/10/2026. Usuário: Victor (desenvolvedor, MacBook Apple Silicon, macOS 26.6, 24 GB de RAM).

## Por que existe

Em 20/10/2026 o Mac do Victor estava sob pressão de memória sem que ele percebesse. A causa não era um app pesado, e sim processos esquecidos acumulados por dias: servidores de desenvolvimento (Next.js, Vite, Spring Boot) parados há 4–5 dias, sessões antigas do Claude Code (uma suspensa com Ctrl+Z há 19 dias), servidores Playwright MCP órfãos de sessões que morreram. Juntos, cerca de 6 GB. No Monitor de Atividade eles aparecem como `node`, `java`, `2.1.296`, `Browser Helper (Renderer)` — impossível saber o que é cada um, de qual projeto, e se pode fechar.

O app resolve três coisas, nas palavras dele: **saber o que é cada processo**, **fechar com facilidade** e **ver memória e processamento** — "tudo que envolver isso".

Sucesso: o Victor percebe a pressão subindo antes de o Mac ficar lento, entende em segundos o que está consumindo, e fecha o que quiser com um clique.

## Objetivos

1. Mostrar a pressão de memória o tempo todo, discretamente, na barra de menus.
2. Traduzir cada processo para algo legível: o que é, de qual projeto/pasta, porta em uso, quem abriu, há quanto tempo está aberto.
3. Destacar os prováveis esquecidos (servidor de dev parado há muito tempo, sessão suspensa, processo órfão) e avisar.
4. Fechar processos facilmente (individual ou em lote), sempre por decisão do Victor.
5. Ser leve: o monitor não pode virar um dos consumidores.

## Não-objetivos

- **Nunca fechar nada sozinho.** Decisão explícita do Victor: o app só avisa; quem decide é ele.
- Não é substituto completo do Monitor de Atividade (disco, rede, energia por processo ficam de fora nesta versão).
- Não é para distribuir a outras pessoas nem publicar na App Store; é para o Mac do Victor.
- Não monitora outros computadores nem envia dados para fora.

## Anti-objetivos (falharia mesmo funcionando)

- Consumir memória/CPU relevantes (meta: menos de ~50 MB de RAM e CPU desprezível em repouso).
- Notificações demais, a ponto de serem ignoradas.
- Fechar por engano algo importante (ex.: a sessão do Claude Code em uso, o próprio terminal, processos do sistema).

## Decisões tomadas

- **Forma:** ícone na barra de menus que abre um resumo (popover) e, a partir dele, uma janela detalhada. (decisão do Victor)
- **Ação automática:** só avisar; fechar é sempre manual. (decisão do Victor)
- **Visual:** tema escuro caprichado, conforme o mockup aprovado em 20/10 (`docs/design/mockup-aprovado.html`). (decisão do Victor, "gostei, pode seguir")
- **Tecnologia:** app nativo em Swift/SwiftUI, por ser o mais leve, rápido e eficaz. (critério do Victor; escolha de tecnologia foi do Claude)

## Como funciona (o aprovado no mockup)

### Ícone na barra de menus
Bolinha colorida (verde / âmbar / vermelho conforme a pressão de memória do sistema) seguida da porcentagem. Clicar abre um popover translúcido, no estilo dos menus nativos do macOS, com:
- anel de pressão com %, memória usada/total, swap, CPU total;
- bloco "N esquecidos · X GB" listando cada um (nome legível, idade, memória);
- "Maiores consumidores": top 3 grupos por memória;
- link "Abrir janela detalhada" (atalho ⌘D).

### Janela detalhada
- **Barra superior:** busca (por processo, projeto, porta) e seletor de agrupamento: Por app / Por projeto / Lista plana.
- **Cartões de métricas:** pressão de memória, memória usada, CPU, swap, cada um com mini gráfico do histórico recente.
- **Faixa de esquecidos:** "N esquecidos · liberaria X GB", com checkbox por item e botão "Fechar selecionados".
- **Lista:** linhas agrupadas (ex.: Teams = 1 linha com 9 processos, expansível), com ícone do app, nome, contexto (ex.: "Next.js dev", "4 sessões"), etiquetas (esquecido, suspensa, ignorado), memória com barra proporcional, CPU, tempo aberto e botão ✕.
- **Painel lateral de detalhes** do item selecionado: nome e descrição ("Servidor de dev do Next.js 16"), dica do motivo de suspeita ("Sem uso de CPU há 3 dias. Provavelmente esquecido."), projeto, pasta, porta, data/hora de início e idade, memória, CPU, processo pai / terminal, PID; botões Fechar, Forçar, Abrir pasta; opção "Sempre ignorar este processo".

### Identificação (o coração do app)
Para cada processo, reunir: nome, linha de comando completa, pasta de trabalho, processo pai, terminal, portas TCP em escuta, hora de início, memória (a mesma métrica do Monitor de Atividade), CPU, estado (rodando / suspenso). A partir disso, classificar com regras conhecidas, por exemplo:
- `next-server`, `vite`, `webpack`, `nest start`, `tsx watch`, Maven/Spring (`java … spring` / `mvn`), `rails`, `django`, `uvicorn` → servidor de desenvolvimento; projeto = nome da pasta de trabalho (raiz com `package.json`/`pom.xml`/`.git`).
- `claude` / processos com nome de versão `2.x.y` → sessão do Claude Code; projeto = pasta de trabalho; estado suspenso destacado.
- `playwright-mcp`, `… mcp` → servidor MCP; órfão quando a sessão que o criou não existe mais.
- Helpers de apps (`Microsoft Teams WebView Helper`, `Browser Helper (Renderer)`, `Google Chrome Helper`) → agrupados no app dono.
- Desconhecidos → mostram o nome e a linha de comando, sem inventar descrição.

### Esquecidos (heurística, só para avisar)
Candidato a esquecido quando, por exemplo: servidor de dev aberto há mais de 24 h e sem CPU relevante há horas; sessão do Claude Code suspensa; MCP órfão. Itens marcados "sempre ignorar" nunca entram.

### Avisos
Notificação do macOS quando a pressão sair do verde e quando surgir um novo esquecido, sem repetir o mesmo aviso em sequência.

### Fechar
Fechar = encerramento normal (SIGTERM); Forçar = SIGKILL. Processo suspenso precisa ser retomado antes de encerrar (descoberto em 20/10: a sessão suspensa ignorou o SIGTERM). Confirmar antes de fechar quando o item for sensível (sessão do Claude Code ativa, terminal, processos de outro usuário/sistema).

### Decisões de detalhe (do Claude, após revisão; o Victor pode mudar)

- **Fechar um app com janela** (Teams, Arc, Slack…) = sair normalmente, como ⌘Q, para o app poder pedir para salvar. "Forçar" = encerrar à força todos os processos do app. Sinais (SIGTERM/SIGKILL) ficam para processos sem janela.
- **Fechar um servidor de dev** = encerrar a cadeia que o iniciou (ex.: `npm run dev` → `next-server`), não só o filho, para não deixar o pai recriando ou um zumbi segurando a porta.
- **O ✕ aparece em todas as linhas.** Pede confirmação quando o item é sensível: a sessão do Claude Code em uso (a que é ancestral do próprio terminal ativo), terminais, processos de outro usuário/sistema. Processos que o sistema não deixa fechar sem senha mostram o ✕ desabilitado com o motivo.
- **O número da barra e do anel é a pressão de memória do sistema** (100% menos a "memória livre" que o próprio macOS calcula, a mesma base do `memory_pressure`), não memória usada/total, que fica sempre alta por causa do cache. A cor segue o nível oficial do sistema (normal / aviso / crítico). "Usada/total" aparece só como informação secundária. O mockup mostrava 16 GB; o Mac tem 24 GB.
- **"Sempre ignorar"** guarda uma identidade estável: para apps, o app (identificador do pacote); para servidores de dev e sessões, o tipo + a pasta do projeto; para o resto, o caminho do executável. Ignorar tira o item dos esquecidos e dos avisos, mas não esconde a linha nem o ✕. Uma lista de ignorados nas preferências permite desfazer.
- **⌘D** funciona só com o popover aberto; não é atalho global.
- **Abrir ao iniciar o Mac**: ligado por padrão, com opção para desligar.

## Restrições

- Mac Apple Silicon, macOS 26.6. Há Swift 6.2 (Command Line Tools), **sem Xcode instalado**: o build deve funcionar com Swift Package Manager e empacotar o `.app` por script (Info.plist com `LSUIElement`, assinatura ad-hoc local).
- Sem dependências externas pesadas; sem serviço em segundo plano além do próprio app.
- Processos de outros usuários (root, `_mysql`) só podem ser lidos/fechados até onde o sistema permitir sem senha de administrador; o app não pede privilégios elevados.

## Deixado para quem construir

- Estrutura de código, APIs de sistema usadas para coletar os dados, intervalo de atualização (respeitando o anti-objetivo de leveza), formato de armazenamento das preferências ("sempre ignorar", limites).
- Limites exatos da heurística de esquecidos e da cor da pressão (usar o nível de pressão do próprio sistema como base).
- Duração do histórico dos mini gráficos.
- Ícones dos apps (usar o ícone real do app quando houver; letra colorida como no mockup quando não houver).

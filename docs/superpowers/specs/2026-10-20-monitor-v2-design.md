# Monitor v2 — portas, máquinas virtuais, containers, picos e descontrolados

Data: 20/10/2026. Continuação do design v1 (`2026-10-20-monitor-memoria-design.md`), cujas restrições, anti-objetivos e decisões continuam valendo (nunca fechar nada sozinho; leve; Swift nativo; tema escuro do mockup; zero comentários no código).

## Por que

No mesmo dia do lançamento da v1, o Victor encontrou no Monitor um processo `com.apple.Virtualization.VirtualMachine` com 2,2 GB e não sabia o que era: era a máquina virtual do Docker Desktop, ligada há 6 horas para testes. O Monitor mostrou o nome técnico e não deixou fechar (executável em `/System/Library`). Ele também pediu para ver as portas em uso e conseguir matar o processo de uma porta, e aprovou um conjunto de melhorias que servem ao mesmo objetivo: perceber o que pesa e agir antes de o Mac ficar lento.

## Objetivos (todos aprovados pelo Victor)

1. **Máquinas virtuais com nome legível.** Com o Docker Desktop aberto, a VM aparece como "Docker Desktop · máquina virtual", agrupada com o Docker; fechar = sair do Docker normalmente (derruba a VM), com confirmação porque para todos os containers. VMs de outros donos aparecem como "Máquina virtual" (sem nome técnico).
2. **Aba "Portas".** Ao lado de Por app / Por projeto / Lista. Tabela de portas TCP em escuta: porta, quem usa (nome legível), projeto, PID, há quanto tempo, e exposição ("só neste Mac" para localhost, "aberta na rede" para todas as interfaces). Campo "Liberar porta" (digita a porta e fecha o dono) e ✕ por linha, com as mesmas regras de segurança da v1.
3. **Portas no popover.** Uma linha com as portas em uso mais relevantes (servidores de dev e bancos primeiro).
4. **Histórico de picos.** Quando a pressão sai do verde, guardar os maiores consumidores do momento. Tela para ver episódios passados ("ontem às 15:10, pressão crítica por 12 min: Teams 3,1 GB, Next dev 2,5 GB…").
5. **Alerta de processo descontrolado.** Avisar (notificação + etiqueta na lista) quando um processo fica com CPU alta por vários minutos ou com memória crescendo sem parar.
6. **Containers do Docker.** Com o Docker aberto, listar containers com memória e CPU de cada um e permitir parar um container sem fechar o Docker.
7. **Custo total da sessão do Claude.** Para cada sessão do Claude Code, somar a sessão + seus MCPs + o navegador que eles abriram (todos os descendentes), e mostrar esse total.
8. **Reiniciar app.** Botão que fecha o app normalmente e o reabre quando ele terminar.

## Não-objetivos

- Atalho global de teclado (o Victor dispensou).
- Conexões de saída e UDP na aba Portas (poluem; só TCP em escuta).
- Gerenciar imagens/volumes do Docker, ou iniciar/criar containers — só listar e parar.
- Fechar ou reiniciar nada automaticamente; alertas só avisam.

## Anti-objetivos

- O monitor passar a pesar: a coleta de containers e o histórico não podem elevar o consumo do app acima da meta da v1 (~50 MB, CPU desprezível em repouso).
- Alarmes falsos de "descontrolado" em processos que normalmente usam muita CPU por pouco tempo (compilação, indexação do Spotlight, build).
- Parar container ou sair do Docker sem o Victor perceber que outros containers também caem.

## Como deve se comportar

### Máquinas virtuais
- Identificação: executável do serviço de virtualização da Apple (`com.apple.Virtualization.VirtualMachine`). Dono: Docker Desktop quando o app Docker estiver rodando; caso contrário, "Máquina virtual" genérica.
- Docker: aparece no grupo do Docker Desktop (por app). Fechar o grupo ou a linha da VM = sair do Docker (quit normal), com confirmação "Isso vai parar todos os containers (N em execução)".
- VM genérica: continua bloqueada para fechar (sem saber o dono, fechar pode corromper a VM), com o motivo explicado.

### Aba Portas
- Fonte: as portas TCP em escuta já coletadas pela v1, agora com o endereço de escuta, para saber a exposição.
- Linhas ordenadas por porta; servidores de dev e bancos destacados.
- "Liberar porta": aceita um número; se ninguém usa, diz "Porta livre"; se for do sistema/outro usuário, explica e bloqueia; senão, fecha o dono pelo mesmo planejamento da v1 (cadeia do servidor de dev, confirmação quando sensível). Depois, confirma que a porta ficou livre ou avisa "ainda em uso".
- Busca da janela também filtra a aba Portas.

### Histórico de picos
- Um episódio começa quando o nível de pressão sai de normal e termina quando volta a normal. Guardar: início, fim, nível máximo, pressão máxima, e os 5 maiores grupos (por app) no momento do pico, com memória.
- Guardar só os últimos 7 dias (escolha do Claude; quem construir pode ajustar).
- Acesso: botão/aba "Picos" na janela; o popover mostra "último pico: hoje 15:10" quando houver.

### Descontrolados
- CPU: processo acima de ~80% de um núcleo de forma contínua por 5 min ou mais (escolha do Claude).
- Memória: processo cuja memória cresceu de forma contínua por 30 min, somando +50% e +500 MB (escolha do Claude).
- Etiqueta "descontrolado" na lista, dica no painel de detalhes ("CPU acima de 80% há 7 min"), notificação uma vez por processo (mesma política anti-repetição da v1), respeitando "sempre ignorar".

### Containers do Docker
- Só quando o Docker estiver aberto. Lista: nome, imagem, estado, memória, CPU, portas publicadas, projeto do compose quando houver.
- Ação "Parar" por container (confirmação simples). Sem iniciar/remover.
- Coleta pouco frequente (escolha do Claude: a cada 15 s e só com a janela aberta), para não pesar.

### Custo da sessão do Claude
- Para cada sessão: total = memória da sessão + todos os descendentes (MCPs, navegador do Playwright e filhos). Mostrar no grupo "Claude Code" por sessão e no painel de detalhes, com a lista do que compõe o total.
- Fechar uma sessão continua usando as regras da v1 (confirmação quando ativa).

### Reiniciar app
- Só para apps com janela (os que a v1 fecha como ⌘Q). Fecha normalmente; quando o app terminar, reabre. Se o app não fechar em ~20 s (ex.: pediu para salvar), não reabre e avisa.

## Decisões de detalhe (do Claude, após revisão; o Victor pode mudar)

- **Porta publicada por container do Docker:** a linha mostra o container e o projeto do compose (ex.: "immobile-postgres · immobile"), não "Docker". "Liberar porta" / ✕ param **só aquele container**, com confirmação. Nunca saem do Docker por causa de uma porta.
- **Custo da sessão do Claude:** número extra, sem mudar os grupos (MCPs e navegador continuam onde estão; o total aparece na sessão e no painel, com a composição). Escopo: a sessão + seus MCPs + os descendentes dos MCPs (navegador do Playwright). Servidores de dev ou builds que o Claude iniciou pelo terminal **não** entram no custo, porque têm vida própria e já aparecem como servidores de dev.
- **Onde ficam os containers:** aba própria "Docker" na janela, visível só com o Docker aberto. A confirmação de sair do Docker consulta a quantidade de containers na hora, mesmo com a janela fechada.
- **Dono da VM:** neste Mac não há outras ferramentas de VM instaladas (UTM, OrbStack, Parallels, Colima, Tart…: verificado em 20/10), então vale a regra simples "Docker aberto ⇒ a VM é do Docker". Se no futuro houver outra VM rodando junto, ela pode ser rotulada errado; aceito como limite conhecido.
- **Descontrolados — quem conta:** só processos do próprio usuário que o Monitor deixa fechar. Processos do sistema e de outro usuário (Spotlight, VM, daemons) não geram alerta. Daemons de build conhecidos (Gradle, Kotlin, Bazel, `cargo`, `swift-build`, `tsc --watch` etc.) não geram alerta de CPU, só de memória.

## Restrições (herdadas)

Swift 6.2 + SwiftPM sem Xcode, `scripts/test.sh` e `scripts/bundle.sh`; sem dependências de terceiros; interface em pt-BR; tema e componentes da v1; zero comentários; commits em inglês sem coautoria.

## Deixado para quem construir

- Como obter endereço de escuta e dados de containers (ex.: `lsof` com endereço, CLI `docker` em `/usr/local/bin/docker`), formato e local de armazenamento do histórico, layout exato das novas abas seguindo o visual da v1, limites finos das heurísticas dentro dos valores acima.

# Monitor — aba Disco: o que ocupa espaço e o que dá para limpar

Data: 20/10/2026. Continuação dos designs v1 (`2026-10-20-monitor-memoria-design.md`) e v2 (`2026-10-20-monitor-v2-design.md`). As restrições e os anti-objetivos deles continuam valendo: nunca fazer nada sozinho, ser leve, Swift nativo, tema escuro, zero comentários no código.

Mockup aprovado: `docs/design/mockup-disco.html`.

## Por que

O disco do Victor está com 84% de uso (358 de 460 GB, 73 GB livres) e ele nunca limpou. Ao desinstalar um app, ele só arrasta o `.app` de Applications para a Lixeira, então as sobras em `~/Library` ficam. Ele não sabe o que pode apagar com segurança.

O levantamento feito em 20/10 (só leitura) mostrou onde está o espaço:

| O quê | Tamanho | Tipo |
|---|---|---|
| Steam (jogos) | 75 GB | dado de app em uso |
| WhatsApp (Containers + Group Containers) | 30 GB | dado de app em uso |
| Docker (`Containers/com.docker.docker`) | 21 GB | imagens, build cache e volumes |
| `node_modules` em `~/Development` | ~10 GB ou mais (10 pastas de 0,7 a 1,5 GB) | regenerável |
| `~/.cache` (uv 5,3, huggingface 3,3, opencode 1,0) | 10 GB | regenerável |
| `~/Library/Caches` (ms-playwright-mcp 3,8, JetBrains 2,2, Arc 1,9, Dia 1,4…) | 14 GB | regenerável |
| `~/.npm` | 4,2 GB | regenerável |
| `Application Support/com.apple.wallpaper` | 9,2 GB | wallpapers dinâmicos baixados |
| Sobras de apps desinstalados (ChatGPT Atlas 857 MB, Adobe, Farming Simulator 2025, Logitech G HUB) | ~1,5 GB | lixo |
| Arquivos acima de 200 MB sem abrir há mais de 6 meses em Downloads/Documents/Movies/Pictures | nenhum | — |

Conclusão: o espaço que dá para recuperar com segurança está no lixo regenerável de dev, não em arquivos esquecidos. As sobras de apps valem a limpeza, mas liberam pouco.

## Objetivos (aprovados pelo Victor)

1. **Aba "Disco"** na janela principal, ao lado de Portas, Docker e Picos.
2. **Resumo em cards** no topo, no estilo dos `MetricCards`: Livre, Seguro limpar, Sobras de apps e Dados de apps. Abaixo, uma barra do disco dividida nessas categorias.
3. **Lista completa sempre visível**, em seções: Seguro, Sobras de apps desinstalados e Seus dados. Clicar num card rola até a seção dele.
4. **Duas formas de limpar**, ambas pedidas pelo Victor:
   - O botão "Limpar o seguro…" no card verde limpa tudo o que é seguro.
   - Ele também pode marcar item por item. O rodapé mostra o total marcado e o botão "Limpar marcados…".

## Não-objetivos

- Varrer o disco inteiro ou montar uma árvore de pastas como DaisyDisk ou GrandPerspective. O Monitor olha só os lugares conhecidos listados abaixo.
- Limpar arquivos do sistema, Time Machine local, snapshots do APFS ou caches de outros usuários.
- Apagar dados de apps em uso, como jogos do Steam ou mídia do WhatsApp. Essa parte é só informativa.
- Desinstalar apps. Só as sobras de apps que já foram removidos aparecem.
- Análise automática periódica e notificação de disco cheio.

## Anti-objetivos (se acontecer, a feature falhou)

- **Apagar algo que o Victor queria.** Isso vale principalmente para uma sobra que na verdade pertence a um app ou CLI instalado, ou que guarda dados (bancos do MySQL, saves de jogo). Na dúvida, o item não aparece como sobra.
- **Apagar sem passar pela Lixeira**, exceto no Docker, que não tem Lixeira. Nesse caso a confirmação avisa que é permanente.
- **Pesar o app.** A análise não pode travar a interface nem rodar sozinha em segundo plano.
- **Quebrar um app aberto** por apagar o cache dele enquanto ele roda.

## Como deve se comportar

### Quando analisa
- Ao abrir a aba pela primeira vez na sessão e quando o Victor clica em ↻. O topo mostra "analisado há X min".
- A análise roda fora da thread principal. Enquanto roda, a tela mostra o progresso, e o resultado anterior continua visível, se houver.
- Não roda com a janela fechada nem junto com o ciclo de 3 s/10 s de CPU e memória.

### Card Livre e barra do disco
- Espaço livre e total do volume de dados. Use a capacidade disponível "para uso importante", que é o mesmo número do Finder.
- A barra divide o espaço usado em Sistema e outros (o resto), Seguro, Sobras e Dados de apps, e mostra o espaço livre.

### Seção "Seguro: se recria sozinho"
Catálogo fixo de lugares conhecidos. Cada item só aparece se existir e tiver mais de 50 MB. Itens marcados por padrão, exceto onde indicado:

- **`node_modules`:** pastas `node_modules` dentro de `~`, menos `~/Library` e as pastas ocultas, que tenham `package.json` ao lado.
  - Aparecem agrupadas numa linha ("node_modules · N projetos"). O "Ver ▸" expande a lista por projeto, com tamanho e "sem mexer desde" (a data de modificação do `package.json` ou da pasta do projeto, a que for mais recente).
  - Ordem: os mais antigos primeiro.
  - Projetos com processo rodando agora (um servidor de dev com cwd dentro do projeto, usando os dados do `ProcessSampler`) aparecem desmarcados e com o aviso "em uso".
- **Caches de dev:**
  - `~/.npm/_cacache`, `~/Library/Caches/pnpm`, store do pnpm, cache do yarn, `~/.cache/uv`
  - `~/Library/Caches/ms-playwright` e `ms-playwright-mcp`, `~/Library/Caches/Homebrew`
  - `~/Library/Developer/Xcode/DerivedData`, `~/Library/Caches/JetBrains`, `~/.gradle/caches`
  - Quem construir pode acrescentar outros do mesmo tipo, desde que se recriem sozinhos sem perda de dados.
- **Hugging Face (`~/.cache/huggingface`):** aparece, mas desmarcado, com o aviso "baixar de novo é lento".
- **Docker** (decisão do Victor), em duas linhas:
  - **Imagens órfãs + build cache:** marcadas por padrão.
  - **Imagens que nenhum container usa:** as de projetos parados. Ficam numa linha separada, **desmarcada**, com a lista dos projetos ou imagens afetados e o aviso "o Docker baixa de novo quando você subir o projeto". Não entram no "Limpar o seguro".
  - Só com o Docker aberto. Fechado, as linhas mostram "abra o Docker para medir".
  - Volumes **nunca** entram, porque guardam dados dos bancos.
  - A remoção é feita pela CLI `docker` (o `DockerClient` já existe) e é permanente. A confirmação diz isso.

### Seção "Sobras de apps desinstalados"
- Olha pastas e arquivos em `~/Library/Application Support`, `Caches`, `Containers`, `Group Containers`, `Preferences`, `Logs`, `Saved Application State`, `HTTPStorages` e `WebKit`.
- Agrupa por app ("ChatGPT Atlas · Application Support, Caches, Preferences") e mostra o total de cada um.
- Só é sobra se der para dizer com confiança que o dono é um app e que ele não está mais instalado:
  - **Identificação:** pelo bundle id (o nome da pasta ou do plist, ou o metadata do container) e pela busca do sistema por apps com esse bundle id em qualquer lugar, não só em `/Applications`.
  - **Nunca é sobra:** `com.apple.*`, itens de CLIs e serviços instalados pelo Homebrew ou por gerenciadores de pacotes, e qualquer pasta cujo dono não se consegue identificar.
- Itens desmarcados por padrão, com o botão "Revelar" (abre no Finder). Fora do "Limpar o seguro".
- **"Talvez sobra · confira antes"** (decisão do Victor): uma sublista separada para pastas sem bundle id, identificadas só pelo nome, como `Adobe`, `Farming Simulator 2025` e `Logitech G HUB`.
  - Entra aqui uma pasta cujo nome não bate com nenhum app instalado (nome do app ou do fabricante), nenhuma fórmula ou cask do Homebrew e nenhum executável no PATH.
  - Sempre desmarcada, com o botão "Revelar". Nunca entra no "Limpar o seguro".
  - Pastas com cara de dados, como bancos (`MySQL`, `Postgres`…) e saves, nunca aparecem, nem aqui.
  - O fechamento com confiança, citado acima, continua valendo só para a lista principal de sobras.

### Seção "Seus dados: só informativo"
- As maiores pastas de dados de apps instalados (Application Support, Containers e Group Containers somados por app), acima de 1 GB, com o botão "Abrir app".
- Os wallpapers dinâmicos da Apple aparecem aqui com a dica "remova em Ajustes › Papel de Parede". O Monitor não apaga.
- Sem checkbox, nada aqui é apagado pelo Monitor.

### Limpar
- **"Limpar o seguro…"** marca todos os itens da seção Seguro que estão marcados por padrão e abre a confirmação. **"Limpar marcados…"** abre a confirmação com o que está marcado.
- **Confirmação:** a lista dos itens e o total.
  - "Vai para a Lixeira. Esvazie a Lixeira para liberar o espaço."
  - Se o Docker estiver incluído: "As imagens do Docker são apagadas na hora, sem Lixeira."
- **Execução:** cada item vai para a Lixeira pelo sistema. Se um item falhar (sem permissão, em uso), os outros continuam e a tela mostra quais falharam e por quê.
- **App aberto:** se o dono de um cache estiver rodando (ex.: JetBrains com o IntelliJ aberto), o item aparece desmarcado com o aviso "feche o app primeiro". O Monitor não limpa esse item enquanto o app estiver aberto.
- **Depois de limpar:** a tela analisa de novo e mostra "X GB na Lixeira".

### Permissões
- Ler pastas de outros apps em `~/Library/Containers` e `Group Containers` pode exigir Acesso Total ao Disco. A análise não pode fazer aparecer o pedido de permissão do sistema. Sem o acesso, as pastas ilegíveis não somam nem aparecem como sobra, e um aviso discreto explica como dar o acesso. A feature continua funcionando com o que conseguir ler.

## Decisões do Claude (o Victor pode mudar)

- Tudo vai para a Lixeira, exceto o Docker. Isso segue a filosofia "nunca fazer nada sem você" e permite desfazer.
- Hugging Face desmarcado por padrão: baixar os modelos de novo é lento.
- `node_modules` agrupado numa linha, com detalhe por projeto e os antigos primeiro. Projetos com processo rodando ficam desmarcados.
- A análise roda sob demanda, não a cada 3 s. Medir o disco é pesado.
- Docker: volumes ficam de fora. A limpeza de imagens **revisa o não-objetivo da v2** "gerenciar imagens/volumes do Docker", liberando só a limpeza de imagens e do build cache, que o Victor aprovou no mockup.
- Arquivos grandes esquecidos (o pedido original do Victor) ficaram fora desta versão. O levantamento não achou nenhum acima de 200 MB parado há 6 meses. Dá para adicionar depois como mais uma seção.
- Limite de 50 MB para um item aparecer e de 1 GB para um app entrar em "Seus dados", para não poluir a lista.
- **Categorias disjuntas:** cada byte conta em uma categoria só. A prioridade é Seguro > Sobras > Dados de apps.
  - Um cache dentro do container de um app instalado conta em Seguro, não em Dados.
  - No Docker, Dados mostra o tamanho do container menos o que é recuperável.
  - Os wallpapers contam em Dados de apps.
  - Arquivos com hard link (store do pnpm × `node_modules`) contam uma vez só (deduplicação por inode). Sistema e outros = usado − (Seguro + Sobras + Dados).
- **Permissões:** a análise nunca provoca o pedido do sistema "acessar dados de outros apps". Sem Acesso Total ao Disco, pula as pastas protegidas e mostra o aviso.

## Restrições (herdadas)

- Swift 6.2 + SwiftPM sem Xcode, com `scripts/test.sh` e `scripts/bundle.sh`, sem dependências de terceiros.
- Interface em pt-BR, tema e componentes da v1 (`Theme`, cards no estilo dos `MetricCards`), zero comentários.
- Commits em inglês, sem coautoria.
- A lógica de classificação (catálogo do seguro, detecção de sobras, agrupamento por app) fica em `MonitorCore` e é testável com um sistema de arquivos falso, como os outros módulos.

## Deixado para quem construir

- **APIs:** como medir o tamanho das pastas (tamanho alocado), como buscar apps instalados por bundle id e como ler o identificador dos containers.
- **Desempenho:** o limite de profundidade na busca por `node_modules`.
- **Layout:** o layout exato seguindo o mockup.
- **Docker:** o formato do `docker system df` e o comando de limpeza usado.

<p align="center"><img src="docs/brand/logo.svg" alt="vernio" width="300"></p>

<p align="center">Monitoramento preciso de dev servers, apps e disco no macOS.</p>

---

App de barra de menus para macOS:
- mostra a pressão de memória, a CPU e a GPU;
- explica o que é cada processo (projeto, porta, há quanto tempo está aberto);
- aponta os processos esquecidos e os descontrolados;
- mostra o que ocupa o disco e o que dá para limpar.

Nunca fecha nem apaga nada sozinho.

- Testes: `scripts/test.sh`
- Gerar e instalar: `scripts/bundle.sh` (instala em `~/Applications/Vernio.app`)
- Ícone: `swift scripts/make-icon.swift` (gera `Resources/AppIcon.icns`)
- Marca: `docs/brand/`
- Design: `docs/superpowers/specs/`

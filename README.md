# Último Amanhecer

Jogo de sobrevivência zumbi 3D, co-op de até 5 jogadores, com combate por armas de fogo, melee ou magia. O design completo está em [docs/GDD.md](docs/GDD.md).

**Engine:** Godot 4.6 (Forward+, física Jolt) · **Linguagem:** GDScript

## Como abrir

1. Abra o Godot 4.6.
2. Clique em **Importar**, escolha a pasta deste projeto (`project.godot`) e abra.
3. Aperte **F5**. Abre o menu: **Jogar sozinho**, **Hospedar partida** ou **Entrar** (IP do host).

Controles: WASD move, Shift corre (gasta stamina), Ctrl agacha, Espaço pula, **V** troca 1ª/3ª pessoa, Esc solta o mouse (clique para capturar de novo).

Hotbar: teclas **1–9** (ou rodinha) escolhem o slot; o item na mão define o botão esquerdo (arco: segure para puxar e solte; machado; feitiço; comida/água/bandagem: usa). Botão direito mira, **R** recarrega, **Q** lança o 1º feitiço da hotbar.

Itens: passar por cima pega sozinho; **E** pega o que está na mira; **Tab** abre inventário e fabricação nas mãos (ex.: flecha = pena + graveto). Fique de olho na **fome** e na **sede** (barras abaixo da vida).

Morte: a mochila cai numa **bag** onde você morreu (a hotbar fica com você) e você renasce com **Fraqueza** temporária, que piora se morrer de novo antes de passar.

Dia e noite: um dia de jogo dura 24 min (dia 06h–20h, noite 20h–06h). À noite os zumbis ficam mais rápidos e ouvem melhor; segure a **tocha** para iluminar. Para testar, **F8** (no host) adianta 1 hora. O mapa completo de teclas (GDD 13.3) já está em *Projeto > Configurações do Projeto > Mapa de Entrada*.

## Testar o co-op no mesmo PC

1. No editor: *Depurar > Personalizar instâncias de execução*, ative **Ativar várias instâncias** e escolha 2 (ou mais).
2. Aperte F5. Numa janela clique **Hospedar partida**; na outra, **Entrar** com `127.0.0.1`.

Atalhos de linha de comando (pulam o menu): `godot -- --host`, `godot -- --join=IP`, `godot -- --solo`.

Entre PCs: na mesma rede use o IP local do host (ex.: `192.168.0.10`). Pela internet, o host libera a porta **7777 UDP** no roteador (ou usa uma VPN como Tailscale/ZeroTier/Radmin).

**Como a rede funciona** (autoload `Network`): o host é o servidor e manda nos zumbis, na vida, no dano e nas mortes. Cada jogador controla o movimento do próprio personagem. Ataques detectam o acerto em quem atacou e pedem o dano ao servidor (`Health.take_damage`).

## Estrutura

```
assets/        Arte e som (veja assets/README.md e assets/LICENSES.md)
data/          Conteúdo do jogo em JSON: itens, receitas, zumbis, feitiços,
               proficiências, passados. Carregado pelo autoload GameData.
scenes/        Cenas .tscn, separadas por módulo
  main.tscn    Cena inicial: menu e contêiner do nível
  levels/      Mapas (test_arena.tscn é a arena da Fase 1)
  player/ enemies/ weapons/ building/ ui/
scripts/       Código GDScript, um diretório por módulo do GDD (16.2)
  autoload/    EventBus (sinais globais) e GameData (dados JSON)
  network/     Network (autoload): host, entrar, barulho até o servidor
  player/ combat/ enemies/ inventory/ crafting/ building/
  world/ progression/ ui/ save/ audio/ network/
addons/        Plugins do Godot
docs/          GDD e outros documentos
tests/         Testes (ex.: GUT ou gdUnit4, quando for adicionado)
```

## Convenções

- Pastas e arquivos em `snake_case`; classes em `PascalCase` (`class_name Player`).
- Código e identificadores em inglês, comentários e textos do jogo em português.
- Números de balanceamento ficam em `data/*.json`, nunca fixos no código.
- Módulos conversam pelo `EventBus` em vez de referências diretas entre si.
- Camadas de física já nomeadas: 1 world, 2 player, 3 zombies, 4 buildings, 5 projectiles, 6 interactables.

## Ao exportar

Os arquivos `.json` de `data/` não entram na exportação por padrão. Em *Projeto > Exportar*, na aba **Recursos**, adicione `data/*` em "Filtros para exportar arquivos que não são recursos".

## Roadmap

Concluídas: **1. Núcleo** (zumbis que perseguem, arco/machado/dardo de fogo, co-op em rede) e **2. Sobrevivência** (inventário e hotbar, coleta de recursos, fabricação nas mãos, fome e sede, ciclo dia/noite, morte com bag e Fraqueza). Próxima: **Fase 3. Crafting** (estações, qualidade, durabilidade). Detalhes no GDD, seção 17.

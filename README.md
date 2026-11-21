# Último Amanhecer

Jogo de sobrevivência e fantasia 3D (mundo aberto infinito com monstros, coleta, fabricação e construção), co-op de até 5 jogadores, com combate por arco e besta, corpo a corpo, mãos vazias ou magia. O design completo está em [docs/GDD.md](docs/GDD.md).

**Engine:** Godot 4.6 (Forward+, física Jolt) · **Linguagem:** GDScript

## Como abrir

1. Abra o Godot 4.6.
2. Clique em **Importar**, escolha a pasta deste projeto (`project.godot`) e abra.
3. Aperte **F5**. A tela inicial (um vale gerado na hora) tem **Singleplayer**, **Multiplayer**, **Personagens**, **Configurações** e **Sair do jogo**. Em **Personagens** você cria (nome + **vocação**: Guerreiro, Arqueiro, Mago ou Pugilista) e exclui personagens. Singleplayer e Hospedar pedem o **mundo** (criar, continuar ou excluir) e depois o **personagem** que entra nele; Entrar pede o endereço e o personagem. O personagem leva inventário, equipamento, níveis e habilidades para qualquer mundo.

Ao entrar num mundo aparece uma **tela de carregamento** (barra de progresso, etapa atual e uma dica) enquanto o terreno, os recursos, as construções e os caminhos dos monstros em volta de onde você vai nascer ficam prontos. Leva poucos segundos; o personagem só é solto quando o chão está pronto.

## Começo e vocações

Personagem novo começa só com **1 tocha e 5 frutas silvestres**: o resto se coleta, acha ou fabrica (machado e picareta de pedra, lança e cajado saem nas mãos). Perto de onde se nasce há **pedras soltas** (E: +1 pedra) e galhos para começar. Itens recebidos aparecem à direita da tela ("+1 Graveto").

A **classe** (Guerreiro, Arqueiro, Mago, Pugilista) só define onde você começa na **árvore passiva**; a especialização vem dos pontos e, no nível 30, da **ascendência**. Cada classe tem um **conjunto inicial** de 5 peças feito na bancada com recursos naturais e drops de monstros:

- **Armadura de pedra** (Guerreiro): muita pedra + presas de ogro.
- **Traje de patrulheiro** (Arqueiro): couro de goblins.
- **Manto do aprendiz** (Mago): tecido + pó arcano, moído do cristal arcano na bancada.
- **Trajes de pugilista** (Pugilista): tendões de carniçais.

**Visual (KayKit):** cada classe tem o seu personagem: Guerreiro = Cavaleiro, Arqueiro = Patrulheiro, Mago = Mago, Pugilista = Bárbaro. A arma selecionada aparece na mão (3ª pessoa e para os outros jogadores) e na 1ª pessoa. Monstros: goblins, xamã, ogro, troll, espectro e diabrete usam os personagens KayKit tingidos; carniçal, draugr e necromante são esqueletos. O Pugilista luta de mãos vazias: proficiência **Pugilismo** e um setor próprio da árvore com dano desarmado.

Recursos e saques são raros (madeira caída e pedras são a exceção). Mouse em cima de um item mostra o que ele faz (ex.: "Regenera 30 de vida em 10 s"), com as etiquetas **Material** (usado em receitas) e **Consumível**.

## Controles

- **Câmera em 3ª pessoa** (estilo RPG de ação): o mouse fica sempre livre; **segure o botão direito** para girar a câmera; **roda do mouse** aproxima/afasta (até 2x a distância padrão).
- **WASD** anda em relação à câmera e o personagem vira para onde anda. **Shift** corre (gasta stamina), **Ctrl** agacha, **Espaço** pula, **Esc** abre o menu de pausa.
- **Clique esquerdo** ataca. **Tab** seleciona o inimigo mais próximo como **alvo** (anel vermelho; apertar de novo passa para o próximo); clicar num inimigo também o seleciona. **Arco, magia e arremesso vão sempre no alvo**, segurando ou não o botão direito; sem alvo, pegam sozinhos o inimigo mais próximo. Os tiros voam reto (sem queda), mas batem em paredes e no terreno. Golpes corpo a corpo vão **para onde o personagem está olhando**; segurando o **botão direito**, para onde a **câmera** aponta (o corpo vira para ela). A câmera nunca gira sozinha ao atacar. Atacando, o personagem anda mais devagar; a animação acelera com a velocidade de ataque.
- **Hotbar:** teclas **1–9** escolhem o slot; o item na mão define o botão esquerdo (arco: segure para puxar e solte; machado; feitiço; comida/poção: usa). Botão direito mira.
- **Q** tocado conjura a última habilidade; **Q segurado** abre a roda de habilidades (mova o mouse e solte para escolher, sem conjurar).
- **E** interage com o que está sob o cursor (ou o mais perto) (portas, baús, estações); passar por cima de itens pega sozinho.
- **B** inventário (mochila e fabricação), **V** equipamentos e status, **P** personagem (árvore passiva, ascendência, proficiências), **C** auras, **M** mapa, **T** modo construção.
- **F8** (host) adianta 1 hora; **F10** (host) troca o clima.

O mapa completo de teclas (GDD 13.3) está em *Projeto > Configurações do Projeto > Mapa de Entrada*.

## HUD

- **Vida** numa esfera à esquerda e **mana** à direita, enchendo de baixo para cima, com os números. A parte **reservada** por auras aparece escura em cima; o **escudo de energia** é um anel azul claro em volta da esfera de vida.
- **Stamina** num arco "(" perto da mira (some quando está cheia).
- **Buffs** (por enquanto as auras que você recebe) como ícones acima da hotbar.
- **Engrenagem** ao lado da hotbar (com o mouse livre, Alt): arraste as esferas e os buffs, roda do mouse numa esfera muda o tamanho, escolha **esferas** ou **arcos "( )" perto da mira** para vida e mana. Fica salvo.

## Configurações

Em **Esc → Configurações** (ou no menu inicial):

- **Idioma**, com bandeira: português, inglês, chinês simplificado e russo. As traduções ficam em `data/i18n/<idioma>.json` (texto em português → tradução).
- Sensibilidade do mouse e volume.
- **Shift** e **Ctrl**: "segurar" ou "alternar".
- **Minimapa** ligado/desligado.
- **Mostrar FPS** (canto da tela) e **VSync** ligado/desligado.

## Sobrevivência, fabricação e equipamento

Não há fome nem sede. A vida **não regenera sozinha**: a regeneração vem da árvore passiva, da ascendência, de itens, de auras e da **comida** (frutas silvestres regeneram vida por alguns segundos). **Poções de cura** curam na hora. A madeira se junta no chão (não existe mais graveto).

**Inventário (B):** fabricação nas mãos (ex.: flecha = pena + madeira). **Clique duplo** num item: equipamento vai para o corpo (troca com a peça vestida); arma ou ferramenta vai para a mão.

**Estações:** fabrique **Fogueira** e **Bancada** nas mãos, selecione na hotbar e clique para colocar. **E** numa estação abre a tela dela, só com as receitas daquela estação (na bancada, também reparar/refinar/desmontar). Cada receita mostra os recursos como "Madeira 12/5" (o que você tem / o que pede; verde se tem, vermelho se falta) e o botão Fabricar fica verde ou vermelho. Fabricar entra numa **fila com tempo** (receitas de estação só andam perto dela).

**Base:** **Baú** (guarda 30 pilhas para o grupo) e **Cama** (E: renasce nela).

**Equipamento** (B, à esquerda do inventário, arrumado como um corpo): capacete, armadura, calça, botas, luvas, 2 anéis e colar; arraste uma peça para o slot, clique no slot ou dê clique duplo no item. Embaixo, o painel de status: **Primários** (vida, stamina, mana e regenerações, redução de recarga, velocidade, velocidade de ataque, resistência a dano e a magia, dano por tipo) e **Secundários** (bônus de conjuntos, aumento de loot, capacidade de carga e outros). Quatro conjuntos, um por estilo: **Caçador** (arqueiro), **Guerreiro** (corpo a corpo e tanque), **Arcano** (magia) e **Sombra** (furtividade); vestir 2, 4 e 6 peças do mesmo conjunto dá bônus extras.

## Combate e progressão

**Carga** (segurar o botão esquerdo): **melee** carrega o golpe gastando stamina (até 2,5× de dano); o **cajado** canaliza a habilidade queimando toda a mana da barra (efeito até 3×); a **faca de arremesso** ganha força e a **adaga** dá muito mais dano em ataque surpresa. A barra de carga aparece acima da hotbar (inclusive puxando o arco). Armas de longe são só arco e besta.

**Magia:** **grimórios** são lidos (clique) e somem: ensinam uma habilidade, ou sobem o nível dela se você já sabe (até 5). Habilidades: Dardo de fogo, Nova de gelo, Remendar (cura o grupo), Muro de terra e Raio em cadeia. O ícone à esquerda da hotbar mostra a última. A mana regenera 4× mais rápido depois de 3 s sem conjurar nem atacar. A bancada copia grimórios com cristal arcano.

**Progressão (P):** as proficiências sobem pelo uso (golpear, atirar, conjurar, lutar desarmado, correr, levar dano, agachar perto de monstros, coletar, fabricar) e cada tipo de arma ganha maestria.

- **Árvore passiva** (aba de P): 393 nós em formato radial; cada nível do personagem (até 100) dá 1 ponto. Aloca-se um nó ligado a outro já alocado, a partir do início da sua classe. Nós pequenos, **notáveis** (bônus maiores) e **pedras angulares** (efeito forte com custo). Clique aloca, botão direito devolve, arrastar move, roda dá zoom, busca por nome ou efeito. A árvore é gerada por `tools/gen_passive_tree.py` → `data/passives/passive_tree.json`.
- **Atributos** (aba de P): 5 pontos por nível em Força (vida, regeneração, dano pesado), Destreza (velocidade, stamina, dano leve), Inteligência (mana, escudo de energia) e Sorte (loot). Armas e equipamentos são **Pesados**, **Leves** ou **Mágicos**. O **escudo de energia** absorve dano antes da vida (faixa azul clara na barra de vida) e recarrega depois de 3 s sem levar dano.
- **Ascendência** (aba de P): no nível 30 escolha uma das 2 da sua classe (definitivo); bônus fixo e 4 pontos (níveis 30, 45, 60, 75) para 4 dos 6 nós dela. Para testar rápido: modo criativo, "+10 níveis".
- **Auras (C):** bônus em área para você e aliados próximos, pagos com reserva de mana. Clique num ícone para ver o nível, a descrição e a barra de reserva (1% a 35%, o efeito cresce junto); o interruptor embaixo (verde/vermelho) liga e desliga. Sobem de nível com o tempo ligadas, mas só com a reserva no máximo (35%). A mesma aura de dois jogadores não soma. O **Pacto de Sangue** (nó da Vanguarda ou do Rompe-Ossos) converte até 50% da reserva de mana em vida; eficiência de reserva de mana e de vida vem da árvore.

**Morte:** nada cai no chão; você perde **15% da XP** rumo ao próximo nível e **15% do ouro** carregado, e renasce com **Fraqueza** temporária, que piora se morrer de novo antes de passar.

**Ouro:** cai de cada monstro e é dividido entre os jogadores vivos por perto (40 m). Aparece no inventário.

**Buffs e debuffs:** ícones acima da hotbar com o tempo restante (debuffs com borda vermelha). Frutas regeneram vida por 10 s; ficar 10 s perto de uma **fogueira** dá **Descansado** (3 min de regeneração maior e +10% de velocidade). Monstros aplicam **veneno** (ácido), **queimadura** (explosão) e **lentidão** (golpe gelado).

## Construção

**T** liga o modo construção (prévia verde/vermelha na grade). Roda troca a peça (fundação, parede, porta, piso/teto, escada), **G** troca madeira/pedra, **R** gira, clique constrói e **X** desmonta. Porta abre com **E**. A grade acompanha o relevo: cada célula tem a altura do chão e as fundações descem até ele. Com o **Martelo** na mão: clique conserta a peça na mira, **R** melhora de madeira para pedra. Peças sem apoio até o chão desabam em cadeia (piso pode avançar até 2 células sem parede embaixo). Monstros presos do lado de fora batem na peça mais fraca. Armadilhas (bancada): **espetos** ferem e deixam lento, **mandíbula** prende; **E** recolhe.

## Mundo

**Infinito**, gerado em blocos de 64 m enquanto se anda, com **relevo** (colinas, vales com lagos e montanhas) e biomas por ruído (floresta, pântano, tundra, zona contaminada e outros), com árvores, pedras e plantas do Nature MegaKit. Lugares (cabanas, casas, vilarejos, fortes e ruínas, com móveis e saque próprios) são raros: no máximo um por região de 256 m. Mundos criados antes do mundo infinito não combinam com o terreno novo: crie um mundo novo.

**Mapa (M):** só mostra o que você já explorou; **roda do mouse** dá zoom, arrastar move, **Centralizar** volta para você, botão direito marca um ponto. **Minimapa** no canto superior direito (some quando o mouse está solto). A **bússola** no topo mostra a direção, as marcações e os outros jogadores com a distância.

**Dia e noite:** um dia de jogo dura 24 min (dia 06h–20h, noite 20h–06h). À noite os monstros ficam mais ferozes e ouvem melhor; segure a **tocha** para iluminar.

**Clima:** chuva (abafa sons), neblina (ninguém enxerga longe), tempestade (raios) e frio extremo (neve).

**Monstros:** carniçais, goblins, ogros, xamãs goblins, espectros noturnos, diabretes flamejantes e draugrs gélidos, conforme a região. Chefes: o **Necromante** surge nas ruínas à noite e o **Troll ancião** desce das montanhas à noite.

**Desempenho:** o terreno, a posição das árvores e pedras, as imagens do mapa e os caminhos dos monstros são calculados em segundo plano (threads); recursos e construções entram e saem aos poucos, com limite de tempo por quadro. Correndo pelo mundo, o pior quadro medido fica em ~24 ms (antes chegava a 690 ms).

## Salvamento

O jogo salva sozinho a cada 2 minutos, ao fechar a janela e pelo menu de pausa (**Esc**). O host salva o mundo (construções, itens no chão, regiões já geradas, dia, clima); cada jogador salva o próprio personagem (inventário, progressão), que pode ser levado para o mundo de um amigo. Saves ficam em `user://worlds/` e `user://characters/` (o save antigo vira "Mundo 1" e "Personagem 1").

## Multiplayer

### No mesmo PC

1. No editor: *Depurar > Personalizar instâncias de execução*, ative **Ativar várias instâncias** e escolha 2 (ou mais).
2. Aperte F5. Numa janela vá em Multiplayer → **Hospedar**; na outra, **Entrar** com `127.0.0.1`.

Atalhos de linha de comando (pulam o menu): `godot -- --host`, `godot -- --join=IP`, `godot -- --solo` (usam o personagem e o mundo mais recentes; `--new` cria um mundo novo, `--world=<id>` e `--character=<id>` escolhem, `--save-root=user://pasta` isola os saves para testes, `--no-upnp` não tenta abrir a porta).

Na mesma rede, use o IP local do host (ex.: `192.168.0.10`).

### Pela internet (amigos em outras cidades)

1. Todos usam **o mesmo executável** (o jogo confere a versão e os dados ao conectar e recusa versões diferentes com um aviso).
2. O host clica em Multiplayer → Hospedar. O jogo tenta abrir a porta **7777 UDP** sozinho (UPnP) e mostra no canto da tela (e no **Esc**, com botão de copiar) o endereço para passar aos amigos.
3. Se aparecer que não deu (roteador sem UPnP), abra a porta 7777 UDP no roteador apontando para o PC do host. Se aparecer **CGNAT** (comum em operadoras brasileiras), abrir porta não adianta: usem uma VPN de jogos (**Radmin VPN**, ZeroTier ou Tailscale) — todos entram na mesma rede da VPN e os amigos usam o IP da VPN do host.
4. Os amigos digitam o endereço em Multiplayer → Entrar (aceita `IP` ou `IP:porta`). O canto da tela mostra o ping.

Quem entra no mundo de um amigo salva o próprio personagem na hora em que sai (inclusive se o host fechar ou a conexão cair).

**Como a rede funciona** (autoload `Network`): o host é o servidor e manda nos monstros, na vida, no dano e nas mortes. Cada jogador controla o movimento do próprio personagem. Ataques detectam o acerto em quem atacou e pedem o dano ao servidor (`Health.take_damage`). Os pacotes são comprimidos e o movimento dos outros jogadores é previsto entre um pacote e outro.

## Estrutura

```
assets/        Arte e som (veja assets/README.md e assets/LICENSES.md)
  models/      KayKit (estilo visual do jogo): characters/kaykit (Adventurers),
               enemies/skeletons, weapons/kaykit, environment/kaykit_forest;
               ainda Quaternius: props/fantasy e buildings/village
  animations/  kaykit (Character Animations, esqueleto Rig_Medium)
data/          Conteúdo do jogo em JSON: itens, receitas, monstros (data/zombies), feitiços,
               proficiências, classes (data/backgrounds), árvore passiva (data/passives),
               ascendências, auras, conjuntos, saques e traduções (data/i18n).
               Carregado pelo autoload GameData.
tools/         gen_passive_tree.py: gera data/passives/passive_tree.json
scenes/        Cenas .tscn, separadas por módulo
  main.tscn    Cena inicial: menu, tela de carregamento e contêiner do nível
  levels/      world.tscn (mundo infinito) e test_arena.tscn
  player/ enemies/ weapons/ building/ ui/
scripts/       Código GDScript, um diretório por módulo do GDD (16.2)
  autoload/    EventBus, GameData, Settings, SaveGame, Structures, WorldItems, Sfx
  network/     Network (autoload): host, entrar, UPnP, verificação de versão
  world/       Mundo infinito (world.gd), vegetação, lugares, dia/noite, clima
  player/ combat/ enemies/ inventory/ crafting/ building/
  progression/ ui/ save/ audio/
addons/        Plugins do Godot
docs/          GDD e outros documentos
```

## Convenções

- Pastas e arquivos em `snake_case`; classes em `PascalCase` (`class_name Player`).
- Código e identificadores em inglês, comentários e textos do jogo em português (o português é a chave das traduções).
- Números de balanceamento ficam em `data/*.json`, nunca fixos no código.
- Módulos conversam pelo `EventBus` em vez de referências diretas entre si.
- Camadas de física já nomeadas: 1 world, 2 player, 3 zombies (monstros), 4 buildings, 5 projectiles, 6 interactables.

## Ao exportar

Os arquivos `.json` de `data/` não entram na exportação por padrão. Em *Projeto > Exportar*, na aba **Recursos**, adicione `data/*` em "Filtros para exportar arquivos que não são recursos". O preset "Windows Desktop" já está pronto (na primeira vez o Godot pede para baixar os modelos de exportação).

## Roadmap

Concluídas: **1. Núcleo** (monstros que perseguem, arco/machado/dardo de fogo, co-op em rede), **2. Sobrevivência** (inventário e hotbar, coleta, fome e sede, dia/noite, morte com bag e Fraqueza), **3. Crafting** (estações, fila com tempo, durabilidade, reparo, desmontagem, qualidade Q1–Q5 e refino +1 a +12), **4. Construção** (grade no relevo, madeira/pedra, martelo, integridade, armadilhas), **6. Progressão** (proficiências, nível, trilhas, maestria, grimórios e vocações), **7. Mundo** (mundo infinito com relevo, biomas, lugares raros, clima, mapa e minimapa) e **8. Polimento** (salvamento por mundo e personagem, menu inicial, configurações, idiomas, tela de carregamento, otimização).

Feito depois: **árvore passiva, ascendência e auras** (substituem as trilhas de habilidades). Próximo em crafting: **afixos** (6 slots, 3 prefixos e 3 sufixos, de 1 a 6 abertos ao fabricar) e a estação **Upgrading Machine** (slots, refino e qualidade), GDD 8.4.

Próxima virada: **RPG de exploração** (sem fome/sede, hotbar de habilidades, HUD nova, inimigos com nível). Plano em [docs/PROXIMOS_PASSOS.md](docs/PROXIMOS_PASSOS.md).

Mudança de rumo: o jogo deixou o tema de zumbis e virou **fantasia com monstros**; as hordas e as armas de fogo saíram. Próxima: **9. Expansão** (mais conteúdo de fantasia). Detalhes no GDD, seção 17.

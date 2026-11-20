# Último Amanhecer

Jogo de sobrevivência e fantasia 3D (mundo aberto infinito com monstros, coleta, fabricação e construção), co-op de até 5 jogadores, com combate por arco e besta, corpo a corpo, mãos vazias ou magia. O design completo está em [docs/GDD.md](docs/GDD.md).

**Engine:** Godot 4.6 (Forward+, física Jolt) · **Linguagem:** GDScript

## Como abrir

1. Abra o Godot 4.6.
2. Clique em **Importar**, escolha a pasta deste projeto (`project.godot`) e abra.
3. Aperte **F5**. A tela inicial (um vale gerado na hora) tem **Singleplayer**, **Multiplayer**, **Personagens**, **Configurações** e **Sair do jogo**. Em **Personagens** você cria (nome + **vocação**: Guerreiro, Arqueiro, Mago ou Pugilista) e exclui personagens. Singleplayer e Hospedar pedem o **mundo** (criar, continuar ou excluir) e depois o **personagem** que entra nele; Entrar pede o endereço e o personagem. O personagem leva inventário, equipamento, níveis e habilidades para qualquer mundo.

Ao entrar num mundo aparece uma **tela de carregamento** (barra de progresso, etapa atual e uma dica) enquanto o terreno, os recursos, as construções e os caminhos dos monstros em volta de onde você vai nascer ficam prontos. Leva poucos segundos; o personagem só é solto quando o chão está pronto.

## Começo e vocações

Personagem novo começa só com **1 tocha, 2 garrafas de água e 3 frutas silvestres**: o resto se coleta, acha ou fabrica (machado e picareta de pedra, lança e cajado saem nas mãos). Perto de onde se nasce há **pedras soltas** (E: +1 pedra) e galhos para começar. Itens recebidos aparecem à direita da tela ("+1 Graveto").

A **classe** (Guerreiro, Arqueiro, Mago, Pugilista) só define onde você começa na **árvore passiva**; a especialização vem dos pontos e, no nível 30, da **ascendência**. Cada classe tem um **conjunto inicial** de 5 peças feito na bancada com recursos naturais e drops de monstros:

- **Armadura de pedra** (Guerreiro): muita pedra + presas de ogro.
- **Traje de patrulheiro** (Arqueiro): couro de goblins.
- **Manto do aprendiz** (Mago): tecido + pó arcano, moído do cristal arcano na bancada.
- **Trajes de pugilista** (Pugilista): tendões de carniçais.

O traje de patrulheiro e o de pugilista aparecem no personagem (Modular Character Outfits). O Pugilista luta de mãos vazias: proficiência **Pugilismo** e um setor próprio da árvore com dano desarmado.

Recursos e saques são raros (galhos e pedras são a exceção). Mouse em cima de um item mostra o que ele faz (ex.: "Recupera 40 de sede"), com as etiquetas **Material** (usado em receitas) e **Consumível**.

## Controles

- **WASD** move, **Shift** corre (gasta stamina), **Ctrl** agacha, **Espaço** pula, **V** troca 1ª/3ª pessoa, **Esc** abre o menu de pausa e solta o mouse.
- **Hotbar:** teclas **1–9** (ou rodinha) escolhem o slot; o item na mão define o botão esquerdo (arco: segure para puxar e solte; machado; feitiço; comida/água/bandagem: usa). Botão direito mira.
- **Q** tocado conjura a última habilidade; **Q segurado** abre a roda de habilidades (mova o mouse e solte para escolher, sem conjurar).
- **E** pega o que está na mira e interage (portas, baús, estações); passar por cima de itens pega sozinho.
- **Tab** inventário, **P** personagem (árvore passiva, ascendência, proficiências), **C** auras, **M** mapa, **B** modo construção.
- **F8** (host) adianta 1 hora; **F10** (host) troca o clima.

O mapa completo de teclas (GDD 13.3) está em *Projeto > Configurações do Projeto > Mapa de Entrada*.

## Configurações

Em **Esc → Configurações** (ou no menu inicial):

- **Idioma**, com bandeira: português, inglês, chinês simplificado e russo. As traduções ficam em `data/i18n/<idioma>.json` (texto em português → tradução).
- Sensibilidade do mouse e volume.
- **Shift** e **Ctrl**: "segurar" ou "alternar".
- **Minimapa** ligado/desligado.
- **Mostrar FPS** (canto da tela) e **VSync** ligado/desligado.

## Sobrevivência, fabricação e equipamento

Fique de olho na **fome** e na **sede** (barras abaixo da vida). Água: beber a garrafa deixa uma garrafa vazia; encha no **lago** (água suja, pode fazer passar mal) e ferva na fogueira.

**Inventário (Tab):** fabricação nas mãos (ex.: flecha = pena + graveto). **Clique duplo** num item: equipamento vai para o corpo (troca com a peça vestida); arma ou ferramenta vai para a mão.

**Estações:** fabrique **Fogueira** e **Bancada** nas mãos, selecione na hotbar e clique para colocar. **E** numa estação abre a tela dela, só com as receitas daquela estação (na bancada, também reparar/refinar/desmontar). Cada receita mostra os recursos como "Madeira 12/5" (o que você tem / o que pede; verde se tem, vermelho se falta) e o botão Fabricar fica verde ou vermelho. Fabricar entra numa **fila com tempo** (receitas de estação só andam perto dela).

**Base:** **Baú** (guarda 30 pilhas para o grupo), **Cama** (E: renasce nela) e **Coletor de água** (água limpa, mais rápido na chuva).

**Equipamento** (Tab, à esquerda do inventário, arrumado como um corpo): capacete, armadura, calça, botas, luvas, 2 anéis e colar; arraste uma peça para o slot, clique no slot ou dê clique duplo no item. Embaixo, o painel de status: **Primários** (vida, stamina, mana e regenerações, redução de recarga, velocidade, velocidade de ataque, resistência a dano e a magia, dano por tipo) e **Secundários** (bônus de conjuntos, aumento de loot, capacidade de carga e outros). Quatro conjuntos, um por estilo: **Caçador** (arqueiro), **Guerreiro** (corpo a corpo e tanque), **Arcano** (magia) e **Sombra** (furtividade); vestir 2, 4 e 6 peças do mesmo conjunto dá bônus extras.

## Combate e progressão

**Carga** (segurar o botão esquerdo): **melee** carrega o golpe gastando stamina (até 2,5× de dano); o **cajado** canaliza a habilidade queimando toda a mana da barra (efeito até 3×); a **faca de arremesso** ganha força e a **adaga** dá muito mais dano em ataque surpresa. A barra de carga aparece acima da hotbar (inclusive puxando o arco). Armas de longe são só arco e besta.

**Magia:** **grimórios** são lidos (clique) e somem: ensinam uma habilidade, ou sobem o nível dela se você já sabe (até 5). Habilidades: Dardo de fogo, Nova de gelo, Remendar (cura o grupo), Muro de terra e Raio em cadeia. O ícone à esquerda da hotbar mostra a última. A mana regenera 4× mais rápido depois de 3 s sem conjurar nem atacar. A bancada copia grimórios com cristal arcano.

**Progressão (P):** as proficiências sobem pelo uso (golpear, atirar, conjurar, lutar desarmado, correr, levar dano, agachar perto de monstros, coletar, fabricar) e cada tipo de arma ganha maestria.

- **Árvore passiva** (aba de P): 393 nós em formato radial; cada nível do personagem (até 100) dá 1 ponto. Aloca-se um nó ligado a outro já alocado, a partir do início da sua classe. Nós pequenos, **notáveis** (bônus maiores) e **pedras angulares** (efeito forte com custo). Clique aloca, botão direito devolve, arrastar move, roda dá zoom, busca por nome ou efeito. A árvore é gerada por `tools/gen_passive_tree.py` → `data/passives/passive_tree.json`.
- **Ascendência** (aba de P): no nível 30 escolha uma das 2 da sua classe (definitivo); bônus fixo e 4 pontos (níveis 30, 45, 60, 75) para 4 dos 6 nós dela. Para testar rápido: modo criativo, "+10 níveis".
- **Auras (C):** bônus em área para você e aliados próximos, pagos com reserva de mana (ou vida). Passe o mouse num quadrado para ver o nível, o efeito e a barra de reserva (1% a 35%, o efeito cresce junto); clique liga/desliga. Sobem de nível com o tempo ligadas. A mesma aura de dois jogadores não soma.

**Morte:** a mochila cai numa **bag** onde você morreu (a hotbar fica com você) e você renasce com **Fraqueza** temporária, que piora se morrer de novo antes de passar.

## Construção

**B** liga o modo construção (prévia verde/vermelha na grade). Roda troca a peça (fundação, parede, porta, piso/teto, escada), **T** troca madeira/pedra, **R** gira, clique constrói e botão direito desmonta. Porta abre com **E**. A grade acompanha o relevo: cada célula tem a altura do chão e as fundações descem até ele. Com o **Martelo** na mão: clique conserta a peça na mira, **R** melhora de madeira para pedra. Peças sem apoio até o chão desabam em cadeia (piso pode avançar até 2 células sem parede embaixo). Monstros presos do lado de fora batem na peça mais fraca. Armadilhas (bancada): **espetos** ferem e deixam lento, **mandíbula** prende; **E** recolhe.

## Mundo

**Infinito**, gerado em blocos de 64 m enquanto se anda, com **relevo** (colinas, vales com lagos e montanhas) e biomas por ruído (floresta, pântano, tundra, zona contaminada e outros), com árvores, pedras e plantas do Nature MegaKit. Lugares (cabanas, casas, vilarejos, fortes e ruínas, com móveis e saque próprios) são raros: no máximo um por região de 256 m. Mundos criados antes do mundo infinito não combinam com o terreno novo: crie um mundo novo.

**Mapa (M):** só mostra o que você já explorou; **roda do mouse** dá zoom, arrastar move, **Centralizar** volta para você, botão direito marca um ponto. **Minimapa** no canto superior direito (some quando o mouse está solto). A **bússola** no topo mostra a direção, as marcações e os outros jogadores com a distância.

**Dia e noite:** um dia de jogo dura 24 min (dia 06h–20h, noite 20h–06h). À noite os monstros ficam mais ferozes e ouvem melhor; segure a **tocha** para iluminar.

**Clima:** chuva (abafa sons), neblina (ninguém enxerga longe), tempestade (raios) e frio extremo (fome mais rápida longe de fogueira).

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
  models/      environment/nature (Nature MegaKit), props/fantasy (Fantasy Props),
               buildings/village (Medieval Village), characters/outfits (trajes)
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

Mudança de rumo: o jogo deixou o tema de zumbis e virou **fantasia com monstros**; as hordas e as armas de fogo saíram. Próxima: **9. Expansão** (mais conteúdo de fantasia). Detalhes no GDD, seção 17.

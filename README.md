# Último Amanhecer

Jogo de sobrevivência zumbi 3D, co-op de até 5 jogadores, com combate por armas de fogo, melee ou magia. O design completo está em [docs/GDD.md](docs/GDD.md).

**Engine:** Godot 4.6 (Forward+, física Jolt) · **Linguagem:** GDScript

## Como abrir

1. Abra o Godot 4.6.
2. Clique em **Importar**, escolha a pasta deste projeto (`project.godot`) e abra.
3. Aperte **F5**. Abre o menu (escolha o **passado** do personagem): **Jogar sozinho**, **Hospedar partida** ou **Entrar** (IP do host).

Controles: WASD move, Shift corre (gasta stamina), Ctrl agacha, Espaço pula, **V** troca 1ª/3ª pessoa, Esc solta o mouse (clique para capturar de novo).

Hotbar: teclas **1–9** (ou rodinha) escolhem o slot; o item na mão define o botão esquerdo (arco: segure para puxar e solte; machado; feitiço; comida/água/bandagem: usa). Botão direito mira, **R** recarrega, **Q** lança o 1º feitiço da hotbar.

Itens: passar por cima pega sozinho; **E** pega o que está na mira; **Tab** abre inventário e fabricação nas mãos (ex.: flecha = pena + graveto). Fique de olho na **fome** e na **sede** (barras abaixo da vida).

Estações: fabrique **Fogueira** e **Bancada** nas mãos, selecione na hotbar e clique para colocar; **E** nelas abre as receitas da estação. Fabricar entra numa **fila com tempo** (receitas de estação só andam perto dela). Água: beber a garrafa deixa uma garrafa vazia; encha no **lago** (água suja, pode fazer passar mal) e ferva na fogueira.

Construção: **B** liga o modo construção (prévia verde/vermelha na grade). Roda troca a peça (fundação, parede, porta, piso/teto, escada), **T** troca madeira/pedra, **R** gira, clique constrói e botão direito desmonta. Porta abre com **E**. Com o **Martelo** na mão: clique conserta a peça na mira, **R** melhora de madeira para pedra. Zumbis presos do lado de fora batem na peça mais fraca.

Progressão: **P** abre o personagem. As proficiências sobem pelo uso (golpear, atirar, conjurar, correr, levar dano, agachar perto de zumbis, coletar, fabricar), cada tipo de arma ganha maestria, e cada nível do personagem dá 1 ponto para as habilidades das trilhas (Atirador, Guerreiro, Arcano, Sobrevivente).

Carga (segurar o botão esquerdo): **melee** carrega o golpe gastando stamina (até 2,5× de dano); o **cajado** canaliza a habilidade gastando mana (até 6× o custo, até 3× de dano/alcance); a **faca de arremesso** ganha força e a **adaga** dá muito mais dano em ataque surpresa. A barra de carga aparece acima da hotbar (inclusive puxando o arco).

Equipamento (**P**): capacete, armadura, calça, botas, luvas, 2 anéis e colar. Quatro conjuntos, um por estilo: **Caçador** (atirador), **Guerreiro** (corpo a corpo e tanque), **Arcano** (magia) e **Sombra** (furtividade). Vestir 2, 4 e 6 peças do mesmo conjunto dá bônus extras. Fabricados na bancada ou achados (casas, posto militar, ruínas). Clique numa peça na hotbar para vestir.

Magia: **grimórios** são lidos (clique) e somem: ensinam uma habilidade, ou sobem o nível dela se você já sabe (até 5; mais mana, mais dano e alcance). Habilidades: Dardo de fogo, Nova de gelo, Remendar (cura o grupo), Muro de terra e Raio em cadeia. **Q** tocado conjura a última; **Q segurado** abre a roda de habilidades (mova o mouse e solte). O ícone à esquerda da hotbar mostra a última. Com o **cajado** na mão, o clique também conjura. A bancada copia grimórios com cristal arcano.

Mapa (**M**): só mostra o que você já explorou; botão direito marca um ponto. A **bússola** no topo mostra a direção, as marcações e os outros jogadores com a distância. **Ctrl** agacha e levanta (alterna).

Clima: chuva (abafa sons), neblina (ninguém enxerga longe), tempestade (raios) e frio extremo (fome mais rápida longe de fogueira). **F10** (host) troca o clima.

Hordas: a cada **7 dias**, ao anoitecer, uma horda ataca em ondas (o relógio mostra quantos dias faltam; o céu fica vermelho na tarde da horda). Sobreviver dá recompensa. **F9** (host) chama uma horda agora, para testar.

Salvamento: o jogo salva sozinho a cada 2 minutos, ao fechar a janela e pelo menu de pausa (**Esc**). O host salva o mundo (construções, itens no chão, dia, clima); cada jogador salva o próprio personagem (inventário, progressão), que pode ser levado para o mundo de um amigo. No menu, marque **Continuar mundo/personagem salvo**.

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

Concluídas: **1. Núcleo** (zumbis que perseguem, arco/machado/dardo de fogo, co-op em rede), **2. Sobrevivência** (inventário e hotbar, coleta de recursos, fome e sede, ciclo dia/noite, morte com bag e Fraqueza) e **3. Crafting** (estações fogueira e bancada, fila com tempo, durabilidade, reparo, desmontagem, qualidade Q1–Q5 e refino +1 a +12 com pedras que caem de inimigos). Concluídas também: **4. Construção**, **5. Hordas** (horda a cada 7 dias em ondas, cuspidor, explosivo, bruto, infectado noturno e o chefe Colosso) **6. Progressão** (proficiências, nível, trilhas de habilidades, maestria, grimórios e passado) e **7. Mundo** (mapa de 320 m gerado por semente com biomas, lagos, montanhas e zona contaminada; vilarejo, cabanas, posto militar e ruínas com saque próprio; zumbis por região; clima; mapa na tecla **M**). Fase **8. Polimento**: salvamento, menu de pausa (sensibilidade, volume), sons provisórios sintetizados, marca de acerto na mira, chefe que escala com o grupo e otimização feitos. Para gerar o executável para outras pessoas testarem: no editor, **Projeto → Exportar** (o preset "Windows Desktop" já está pronto; na primeira vez o Godot pede para baixar os modelos de exportação). Próxima: **9. Expansão** (mais conteúdo). Feito: modo construção (B) com grade e prévia, fundação/parede/porta/piso/escada em madeira ou pedra, e zumbis que atacam a peça mais fraca quando a base os bloqueia. Também: martelo para consertar e melhorar peças. Integridade: peças sem apoio até o chão desabam em cadeia (piso pode avançar até 2 células sem parede embaixo). Armadilhas (bancada): **espetos** ferem e deixam lento, **mandíbula** prende; **E** recolhe. Detalhes no GDD, seção 17.

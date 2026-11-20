# Próximos passos: virada para RPG de exploração

Documento de planejamento. **Nada daqui está implementado ainda.** Complementa o [GDD](GDD.md) (seções 4.2 e 8.4) e substitui a seção 22 dele como lista do que vem a seguir.

**Direção:** o jogo deixa de ser de sobrevivência e vira um **RPG de exploração mais dinâmico**, em mundo aberto, mantendo construção, coleta e crafting (com outras regras). Inspiração principal: Path of Exile (árvore passiva, ascendência, auras, afixos), com mais inimigos, níveis e combate com habilidades.

Cada seção traz: **o que fazer**, **regras**, **o que muda no projeto atual** e **a decidir** (dúvidas para responder antes de implementar).

---

## 1. Interface de auras (refeita)

**O que fazer:** reorganizar a tela de auras (tecla C) em duas partes: a lista de ícones e o detalhe da aura selecionada.

**Regras:**

- **Lista (parte de cima):** só os ícones das auras, **com mais espaço entre eles**, e o **nome completo da aura escrito em cima** de cada ícone.
- **Clicar num ícone não liga/desliga mais.** O clique **seleciona** a aura: uma **cópia do ícone** aparece **abaixo da lista, centralizada**, com a **descrição completa** embaixo dela (nível como título, efeito, raio, progresso do próximo nível).
- **Barra de reserva** (1% a 35%) continua no detalhe, **mais estreita** do que hoje, com a % no topo/centro.
- **Na parte de baixo do detalhe:** um **interruptor (toggle) com bolinha** escrito **Ativar/Desativar**. **Ativado = verde**, **desativado = vermelho**.
- Aura bloqueada (nível insuficiente): o toggle fica desabilitado e mostra "Disponível no nível N".

**O que muda:** `scripts/ui/aura_ui.gd` (layout e o clique); `Auras.toggle()` continua sendo a ação, só chamada pelo interruptor.

**A decidir:** o ícone de cada aura (hoje são as iniciais do nome). Precisamos de arte ou de ícones desenhados por código.

---

## 2. Pacto de Sangue vira conversor de reserva

**O que fazer:** o *Pacto de Sangue* deixa de ser uma aura de dano e passa a **converter parte do custo de reserva de mana em reserva de vida**.

**Regras:**

- O jogador escolhe a conversão de **0% a 50%** (limite de 50% do valor). Ex.: auras somando 60% de reserva de mana, com 50% convertidos → 30% de mana + 30% de vida.
- **Ordem do cálculo (importante):**
  1. Soma do custo bruto das auras ligadas (as % escolhidas).
  2. **Conversão do Pacto de Sangue** (parte vai para vida).
  3. **Eficiência de reserva de mana** aplicada só à parte que ficou em mana.
  4. **Eficiência de reserva de vida** aplicada só à parte que foi para vida.
  5. Limite de 90% por recurso.
- Assim, a eficiência de mana **não afeta** a parte convertida, e vice-versa.

**O que muda:** `data/auras/auras.json` (tirar os efeitos de dano do `blood_pact`, marcar como conversor); `Auras.reserved_fraction()` passa a seguir a ordem acima.

**A decidir:**

- O Pacto de Sangue continua sendo uma "aura" ligada na tela C (com a barra indo de 0% a 50% em vez de 1% a 35%), ou vira um nó/pedra angular da árvore ou um nó de ascendência?
- Ele tem custo próprio ou efeito colateral (ex.: menos regeneração de vida)?

---

## 3. Eficiência de reserva separada (árvore passiva)

**O que fazer:** trocar a chave única `reservation_efficiency` por duas:

- `mana_reservation_efficiency`: reduz só a reserva que fica em mana.
- `life_reservation_efficiency`: reduz só a reserva que vai para vida (via Pacto de Sangue).

**Regras:** adicionar **nós secundários** (pequenos) das duas na árvore. Mana: setores do Mago e do Monge. Vida: setores do Guerreiro e do Bárbaro, perto de nós de vida. Pelo menos 1 notável de cada. Limite de 60% cada.

**O que muda:** `tools/gen_passive_tree.py` (tabelas `PATH_SMALLS`/`NOTABLES`; regerar o JSON), `data/ascendancies/ascendancies.json` (Vanguarda e Oráculo usam `reservation_efficiency`), `Auras.reserve_cost()`, `ProgressionUI.BONUS_NAMES` e o painel de status.

---

## 4. Fim de fome e sede

**O que fazer:** remover o sistema de fome e sede e tudo que só existe por causa dele.

**O que sai:**

- Barras de fome/sede do HUD; dano por fome/sede; penalidade de stamina por estar "fraco"; "bem alimentado regenera vida".
- Itens: `water_bottle`, `dirty_water`, `empty_bottle`. `berries` e `canned_food` saem ou viram consumíveis de cura (ver "a decidir").
- Receita `boil_water` (fogueira), o **Coletor de água** (`water_collector`) e a interação de encher garrafa no lago (`water_source.gd`).
- Modificador `food` da árvore passiva, da ascendência (*Sobrevivente Nato*) e dos itens; frio do clima que aumentava a fome (`Weather.hunger_factor`).
- Kit inicial atual (`Player.STARTER_KIT`: tocha, 2 garrafas de água, 3 frutas).

**O que muda:** `scripts/player/survival.gd` (sobra só a regeneração de vida, ou o arquivo some e ela vai para outro lugar), `debug_hud.gd`, `save_game.gd` (deixa de salvar hunger/thirst, mas continua aceitando saves antigos), `weather.gd`, `world.gd`, `data/items/food.json`, receitas, `gen_passive_tree.py`.

**A decidir:**

- Regeneração de vida base sem comida: fixa pequena, só fora de combate, ou só por itens e árvore?
- Cura: **frascos com cargas** que recarregam matando inimigos (como no Path of Exile) substituem comida e bandagens? (Ver ideias, seção 14.)
- A fogueira continua (luz, ponto de descanso, culinária para buffs temporários) ou sai?

---

## 5. Hotbar de habilidades (5 slots por classe)

**O que fazer:** a barra inferior deixa de ser de itens e passa a ser de **habilidades**.

**Regras:**

- **5 slots** (teclas 1 a 5), em vez de 9.
- **Cada classe tem as suas habilidades.**
- Interface **menor por padrão** (ícones e barra menores que os atuais).
- O jogador pode clicar nos slots com o mouse livre (ver seção 7).

**O que muda:** `Inventory.HOTBAR_SIZE` e a ideia de hotbar como parte do inventário; `weapon_holder.gd` (hoje a mão segura o item do slot); roda do Q e grimórios (`Progression.spells`); `debug_hud.gd` (`_bind_inventory`); regra de morte (hoje a hotbar fica com o jogador e a mochila cai na bag).

**A decidir:**

- Onde fica a **arma**: um slot fixo de arma no equipamento (troca rápida com uma tecla) e as 5 teclas só para habilidades?
- Como se **ganham habilidades**: por nível, por grimório, pela árvore, ou por "gemas" encaixadas no equipamento (ideia na seção 14)?
- Consumíveis (frascos, tochas, comida de buff) vão para uma **segunda barra pequena**?
- Quantas habilidades por classe no início (ex.: 2 no nível 1 e as outras liberadas por nível)?

---

## 6. Coleta e ferramentas

**O que fazer:** mudar a coleta: ferramentas em slots próprios e uma ação de coleta com tempo.

**Regras:**

- **Graveto deixa de existir.** Tudo que pedia graveto passa a pedir **Madeira**. Madeira passa a ser **coletada no chão**, no lugar do graveto.
- Itens soltos no chão para pegar: **madeira e pedra**.
- **3 slots novos no equipamento:** **Picareta**, **Machado** e **Pesca** (vara).
- Para coletar **árvores** e **pedras grandes**, é preciso ter a ferramenta certa equipada nesse slot (não na mão).
- **Interação:** ao chegar perto de uma árvore ou rocha, aparece na tela "**[E] Cortar árvore (4 s)**" / "**[E] Minerar (3 s)**", com o tempo ao lado. Segurar ou apertar E começa a coleta, com uma **barra de progresso igual à de canalização**. Mover-se ou levar dano cancela (a decidir).
- O tempo depende da ferramenta (qualidade e refino), da proficiência e de `gather_yield`.

**O que muda:** `data/items/resources.json` (sai `stick`), `data/recipes/*.json` (13 receitas usam `stick`), `data/buildings/pieces.json`, `data/nodes/nodes.json` (6 nós dão graveto), `world.gd` (galhos no chão viram madeira), `resource_node.gd` (coleta por interação com tempo, e não por golpe), `equipment.gd` e `equipment_panel.gd` (3 slots), `channel_bar.gd` (reaproveitar).

**A decidir:**

- O texto original diz "ainda terá pedra e graveto para pegar". Está entendido como **pedra e madeira** (já que o graveto sai). Confirmar.
- **Pesca:** onde se pesca (lagos existentes), mecânica (minijogo ou tempo) e para que servem os peixes sem a fome (buffs, crafting, venda)?
- Machado e picareta continuam podendo ser **armas**, ou viram só ferramentas?

---

## 7. Câmera e mouse livre (Alt esquerdo)

**O que fazer:** além de 1ª/3ª pessoa (V), dois modos de controle da câmera, alternados com **Alt esquerdo**:

1. **Mouse travado (atual):** girar o mouse gira a câmera.
2. **Mouse livre:** o cursor aparece e a câmera **só gira segurando o botão direito**. Com o cursor livre, o jogador **clica na HUD**: hotbar, barra da party, engrenagem de layout etc.

**O que muda:** `player.gd` (mouse e câmera; hoje o botão direito é "mirar"), `Input.mouse_mode` espalhado pelas telas (cada tela trava o mouse ao fechar; precisa voltar ao modo escolhido), `debug_hud.gd` (`MOUSE_FILTER_IGNORE` na hotbar vira clicável), Configurações (modo padrão), `project.godot` (ação nova).

**A decidir:** no modo livre, o ataque mira **para onde o cursor aponta** (estilo ARPG) ou **para o centro da tela**? Com o botão direito ocupado pela câmera, onde fica a mira do arco?

---

## 8. HUD nova

### 8.1 Barra da party (lateral esquerda)

- Um quadro por jogador do grupo: **nome**, barras de **vida, stamina e mana**.
- **Clicar** no quadro de um aliado: menu com **Selecionar (alvo)**, **Trocar itens (trade)** e **Seguir automaticamente (follow)**.

### 8.2 Vida, mana e stamina

- **Vida:** esfera (bolinha) à **esquerda** da HUD, que **enche de baixo para cima**.
- **Mana:** esfera à **direita** da HUD, mesmo estilo.
- **Valores numéricos** nas barras (ex.: "84 / 120"), incluindo stamina e mana. Na vida e na mana, mostrar a parte reservada pelas auras (faixa escura em cima da esfera).
- **Stamina:** arco em formato "**(**" no **centro da tela**, com espaço entre ele e a mira.
- **Opção:** vida e mana também podem virar arcos "**(**" e "**)**" perto da mira, no lugar das esferas.

### 8.3 HUD personalizável

- **Botão de engrenagem pequeno** ao lado da hotbar abre o **modo de edição da HUD**.
- No modo de edição, o jogador **arrasta** e **redimensiona** as barras laterais (party, esferas) e escolhe **esferas ou arcos** para vida/mana.
- Botão "Restaurar padrão". O layout é salvo nas Configurações (por máquina, não por personagem).

**O que muda:** `debug_hud.gd` e `scenes/ui/debug_hud.tscn` (precisam ser divididos em componentes: esfera, arco, quadro de party), `settings.gd` (layout salvo), `Network` (lista de jogadores e nomes para a party).

---

## 9. Mundo de RPG: mais inimigos, nomes, níveis

**O que fazer:** **muito mais inimigos e mais variedade** pelo mundo.

**Regras:**

- Cada inimigo tem **nome, nível e barra de HP em cima da cabeça**.
- Nível do inimigo pela **região/distância do spawn** (zonas de nível), para guiar a exploração.
- XP e loot escalam com o nível. Diferença grande de nível reduz a XP (evita farmar área fácil).

**O que muda:** `data/zombies/` (renomear para `data/monsters/` e dar nível base, escalas por nível, nomes de fantasia), `zombie.gd` (barra flutuante e nível), `world.gd` (densidade e spawn por zona), `Progression.send_kill_xp`.

**A decidir:** densidade alvo (inimigos por chunk), respawn (tempo ou ao sair da área), limite de inimigos ativos por desempenho (hoje há IA simplificada a mais de 40 m).

---

## 10. Alvo em aliados

**O que fazer:** poder **selecionar um aliado como alvo** (clicando nele no mundo ou no quadro da party) para **feitiços de cura** e **buffs temporários**.

**Regras:** feitiços de suporte vão no alvo selecionado. Sem alvo, vão em si mesmo (ou no aliado na mira). O alvo aparece destacado (anel/contorno) e no quadro da party. Alcance máximo por feitiço.

**O que muda:** `spell_caster.gd` (hoje *Remendar* cura todos num raio), servidor confere distância como em `Health.heal_by`, buffs temporários precisam de um sistema novo (efeitos com duração, ícones no HUD, sincronizados como as auras).

---

## 11. Trade e follow

- **Trade:** janela de troca entre dois jogadores (cada um coloca itens, os dois confirmam, o servidor faz a troca de forma atômica).
- **Follow:** o personagem anda sozinho atrás do aliado escolhido. Qualquer tecla de movimento cancela.

**A decidir:** trade só perto (ex.: 10 m) ou à distância? Follow atravessa obstáculos com pathfinding (navmesh) ou só segue em linha?

---

## 12. Afixos e Upgrading Machine (já planejado)

Ver [GDD 8.4](GDD.md): 6 slots (3 prefixos, 3 sufixos) nos equipamentos fabricáveis, de 1 a 6 desbloqueados ao fabricar, e a estação **Upgrading Machine** com as categorias **slots**, **refino** e **qualidade**. Custos e valores a definir. As ferramentas da seção 6 também podem receber afixos (velocidade de coleta, rendimento).

---

## 13. Ordem sugerida

Cada passo termina jogável:

1. **Limpeza:** fim de fome/sede (4), fim do graveto (6, parte de dados).
2. **Auras:** interface nova (1), Pacto de Sangue conversor (2), eficiências separadas (3).
3. **Controles:** Alt e mouse livre (7). Destrava a HUD clicável.
4. **HUD:** esferas, arco de stamina, números, engrenagem e layout (8.2, 8.3).
5. **Habilidades:** hotbar de 5 com habilidades por classe (5).
6. **Coleta:** slots de ferramentas e coleta com tempo (6).
7. **Mundo RPG:** inimigos com nível, nome, barra e zonas (9).
8. **Grupo:** party lateral, alvo em aliados, buffs temporários, trade e follow (8.1, 10, 11).
9. **Afixos e Upgrading Machine** (12).

---

## 14. Ideias para aproximar de Path of Exile e outros ARPGs

Sugestões para discutir, não compromissos.

### Itens e loot

- **Raridade:** normal (branco), mágico (azul, até 1 prefixo + 1 sufixo), raro (amarelo, até 3 + 3) e **único** (laranja, efeito especial fixo). Encaixa direto nos 6 slots de afixo.
- **Nível de item:** o nível da área onde caiu limita quais afixos podem sair. Explorar longe dá itens melhores.
- **Moedas de crafting:** em vez de recursos genéricos, orbes que fazem uma ação no item (abrir slot, re-sortear afixos, subir qualidade). Viram os "custos" da Upgrading Machine e a moeda de troca entre jogadores.
- **Filtro de loot** simples (esconder brancos, destacar raros e únicos) e som/feixe de luz para drop raro.

### Habilidades

- **Gemas de habilidade e de suporte:** a habilidade vem de uma gema; gemas de suporte ligadas a ela mudam o comportamento (mais projéteis, área maior, converter para gelo). Dá profundidade aos 5 slots sem precisar de 50 habilidades por classe.
- **Habilidade de movimento** em todas as classes (rolamento, salto, teleporte curto) e **troca rápida de arma** (dois conjuntos).
- **Tipos de dano e estados:** físico, fogo (queimadura), gelo (lentidão/congelar), raio (choque = mais dano recebido), caos/veneno; **acerto crítico**; **resistências** que caem conforme a zona é mais difícil.

### Sobrevivência de combate (no lugar de comida)

- **Frascos com cargas:** vida, mana e utilidade, recarregados matando inimigos. Podem ter afixos próprios.
- **Escudo de energia** como segunda barra de vida para classes mágicas (combina com o Oráculo e o Arcanista).

### Mundo aberto

- **Zonas de nível** em anéis a partir do spawn, com biomas mais perigosos longe.
- **Monstros mágicos e raros** com nome gerado e modificadores ("Rápido", "Explode ao morrer", "Aura de gelo"), em grupos com um líder.
- **Masmorras instanciadas** (entradas no mundo) com modificadores sorteados, um chefe e loot melhor. Fazem o papel dos "mapas" do Path of Exile.
- **Eventos dinâmicos:** a noite traz invasões, fendas que abrem no mapa e caravanas atacadas. Recompensas para quem estiver perto.
- **Pontos de viagem rápida** (pedras/portais) descobertos explorando, com um portal de volta para a base.
- **Provas de ascendência:** no lugar de só chegar ao nível 30, um desafio (masmorra especial) libera a ascendência e cada ponto dela.

### Base e construção como parte do RPG

- **Estações que dão buffs** quando o jogador descansa na base (santuário: +10% de XP por 30 min).
- **NPCs que se mudam para a base** depois de resgatados (vendedor, ferreiro que destrava a Upgrading Machine, cartógrafo de masmorras).
- **Baú compartilhado com abas** (como o stash) e um **mercado de troca** entre jogadores.
- **Defesa de base** como evento (ondas de monstros atraídas pelo tamanho da base), reaproveitando as armadilhas.

### Progresso de longo prazo

- **Bestiário:** matar N de cada tipo dá bônus pequenos permanentes.
- **Atlas/mapa de conquistas:** marcar regiões limpas e chefes derrotados libera modificadores mais difíceis e recompensas melhores.
- **Temporadas:** uma mecânica nova a cada atualização, com mundo novo opcional.

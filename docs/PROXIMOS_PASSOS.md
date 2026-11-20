# Próximos passos: virada para RPG de exploração

Documento de planejamento. **Nada daqui está implementado ainda.** Complementa o [GDD](GDD.md) (seções 4.2 e 8.4) e substitui a seção 22 dele como lista do que vem a seguir.

**Direção:** o jogo deixa de ser de sobrevivência e vira um **RPG de exploração mais dinâmico**, em mundo aberto, mantendo construção, coleta e crafting (com outras regras). Inspiração principal: Path of Exile (árvore passiva, ascendência, auras, afixos), com mais inimigos, níveis e combate com habilidades.

Cada seção traz: **o que fazer**, **regras** (incluindo o que já foi **decidido**), **o que muda no projeto atual** e o que ainda está **a decidir**.

### Teclas novas (resumo)

| Tecla | Função |
| --- | --- |
| 1 a 5 | Habilidades |
| Alt esquerdo | Alterna mouse travado / mouse livre |
| F1 | Câmera 1ª / 3ª pessoa (era V) |
| V | Tela de equipamentos (nova, separada do inventário) |
| Tab | Inventário (menor, sem os equipamentos) |
| C | Auras |
| P | Personagem (árvore passiva, ascendência, proficiências) |
| E | Interagir / coletar (segurar durante a coleta) |

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

**A decidir:** o ícone de cada aura (hoje são as iniciais do nome). Sugestão: ícones desenhados por código até ter arte.

---

## 2. Pacto de Sangue vira conversor de reserva

**O que fazer:** o *Pacto de Sangue* deixa de ser uma aura de dano e passa a **converter parte do custo de reserva de mana em reserva de vida**.

**Regras:**

- **Decidido:** é uma **aura nova desbloqueada por um nó de ascendência**. Não fica disponível para todos pelo nível, como as outras.
- **Decidido:** tem **custo próprio**: ligada, ela reserva uma parte fixa do recurso (valor a definir), além do que converte.
- O jogador escolhe a conversão de **0% a 50%** (limite de 50% do valor). Ex.: auras somando 60% de reserva de mana, com 50% convertidos → 30% de mana + 30% de vida.
- **Ordem do cálculo (importante):**
  1. Soma do custo bruto das auras ligadas (as % escolhidas).
  2. **Conversão do Pacto de Sangue** (parte vai para vida).
  3. **Eficiência de reserva de mana** aplicada só à parte que ficou em mana.
  4. **Eficiência de reserva de vida** aplicada só à parte que foi para vida.
  5. Limite de 90% por recurso.
- Assim, a eficiência de mana **não afeta** a parte convertida, e vice-versa.

**O que muda:** `data/auras/auras.json` (tirar os efeitos de dano do `blood_pact`, marcar como conversor e como "liberada por ascendência"); `data/ascendancies/ascendancies.json` (nó que libera a aura); `Auras.is_unlocked()` e `Auras.reserved_fraction()` (seguir a ordem acima).

**A decidir:**

- **Quais ascendências** têm o nó que libera o Pacto de Sangue. Sugestão: Vanguarda (Guerreiro) e Rompe-Ossos (Pugilista), que combinam com vida alta.
- **Valor do custo próprio** e se ele é cobrado em vida ou em mana. Sugestão: 10% de vida.

---

## 3. Eficiência de reserva separada (árvore passiva)

**O que fazer:** trocar a chave única `reservation_efficiency` por duas:

- `mana_reservation_efficiency`: reduz só a reserva que fica em mana.
- `life_reservation_efficiency`: reduz só a reserva que vai para vida (via Pacto de Sangue).

**Regras:** adicionar **nós secundários** (pequenos) das duas na árvore. Mana: setores do Mago e do Monge. Vida: setores do Guerreiro e do Bárbaro, perto de nós de vida. Pelo menos 1 notável de cada. Limite de 60% cada.

**O que muda:** `tools/gen_passive_tree.py` (tabelas `PATH_SMALLS`/`NOTABLES`; regerar o JSON), `data/ascendancies/ascendancies.json` (Vanguarda e Oráculo usam `reservation_efficiency`), `Auras.reserve_cost()`, `ProgressionUI.BONUS_NAMES` e o painel de status.

---

## 4. Fim de fome e sede; cura e regeneração

**O que fazer:** remover o sistema de fome e sede e tudo que só existe por causa dele. Refazer a cura e a regeneração de vida.

**O que sai:**

- Barras de fome/sede do HUD; dano por fome/sede; penalidade de stamina por estar "fraco"; "bem alimentado regenera vida".
- Itens: `water_bottle`, `dirty_water`, `empty_bottle`, `canned_food` e **as bandagens** (decidido).
- Receita `boil_water` (fogueira), o **Coletor de água** (`water_collector`) e a interação de encher garrafa no lago (`water_source.gd`; o lago passa a servir para pesca, seção 6.2).
- Modificador `food` da árvore passiva, da ascendência (*Sobrevivente Nato*) e dos itens; frio do clima que aumentava a fome (`Weather.hunger_factor`).
- Kit inicial atual (`Player.STARTER_KIT`: tocha, 2 garrafas de água, 3 frutas).

**Regras (decidido):**

- **Regeneração de vida base = 0.** Ela aumenta com comida, itens e pontos da árvore passiva. **Classes corpo a corpo** (Guerreiro, Pugilista) têm mais nós de regeneração de vida no setor delas.
- **Cura:** sem bandagens nem frascos. A cura vem como **regeneração temporária** ao consumir **frutas silvestres** (`berries`) e **peixes pescados** (seção 6.2). Feitiços de cura (*Remendar*) continuam.
- **Fogueira continua**, com três funções:
  - **Luz.**
  - **Culinária:** cozinhar peixes e outros alimentos para **buffs temporários** mais fortes.
  - **Buff "Descansado":** ficar **10 s ou mais perto de uma fogueira** dá **3 min** de: **mais regeneração de todos os status** (vida, mana, stamina) e **+10% de velocidade de movimento**.

**O que muda:** `scripts/player/survival.gd` (sai fome/sede; a regeneração de vida fica só com `life_regen_add`), `debug_hud.gd`, `save_game.gd` (deixa de salvar hunger/thirst, mas continua aceitando saves antigos), `weather.gd`, `world.gd`, `data/items/food.json`, receitas, `gen_passive_tree.py` (mais `life_regen_add` nos setores corpo a corpo), `utility.gd`/fogueira (área do "Descansado"). Precisa de um **sistema de buffs temporários** (efeito, duração, ícone no HUD), o mesmo da seção 10.

**A decidir:** quanto de regeneração dão as frutas, os peixes e o "Descansado" (valores e duração da regeneração por alimento).

---

## 5. Habilidades, arma e inventário

**O que fazer:** a barra inferior deixa de ser de itens e passa a ser de **habilidades**. Inventário e equipamento viram telas separadas.

**Regras (decidido):**

- **Hotbar de habilidades:** **5 slots** (teclas 1 a 5), interface **menor por padrão**. Clicável com o mouse livre (seção 7).
- **Cada classe tem as suas habilidades.** No **nível 1**, só **1 habilidade básica**; as outras são **desbloqueadas por nível do personagem**.
- **Desbloquear e evoluir habilidade custa ouro** (moeda nova, seção 13). **Nível máximo da habilidade: 20.** A cada **5 níveis** (5, 10, 15, 20) a evolução pede também um **recurso específico que cai de chefes** (com % de chance).
- **Habilidades exclusivas:** **grimórios consumíveis** que **caem de chefes** (com % de chance) ensinam habilidades fora das da classe.
- **Arma:** **slot fixo de arma** na tela de equipamentos. As teclas 1 a 5 são só para habilidades.
- **Consumíveis** (comida, peixes, tochas) **ficam só no inventário**, sem barra própria. Usar = clique duplo no item (ou clique com o mouse livre).
- **Inventário (Tab):** **menor** e **sem os equipamentos**.
- **Equipamentos (tecla V):** tela própria, com os slots de armadura, arma e ferramentas (seção 6).
- **Câmera 1ª/3ª pessoa** passa do V para o **F1**.

**O que muda:**

- `Inventory.HOTBAR_SIZE` e a ideia de hotbar como parte do inventário; `weapon_holder.gd` (a mão passa a segurar a arma do slot fixo, não o item da hotbar).
- `Progression.spells`, a roda do Q, os grimórios atuais e `MAX_SPELL_LEVEL` (5 → 20).
- `inventory_ui.gd` e `equipment_panel.gd` (separar em duas telas), `ui_tabs.gd` (aba nova "Equipamentos (V)"), `project.godot` (V e F1).
- Regra de morte: hoje a hotbar fica com o jogador e a mochila cai na bag. Com a hotbar só de habilidades, decidir o que fica protegido (ver abaixo).
- Dados novos: habilidades por classe (`data/skills/` voltando com outro formato: classe, nível de desbloqueio, custo em ouro por nível, recurso de chefe a cada 5).

**A decidir:**

- Quais são as habilidades de cada classe e em que níveis elas abrem.
- Na morte, o que não cai na bag (antes eram as 9 da hotbar). Sugestão: equipamento vestido, arma e ferramentas nunca caem.
- As teclas Q e F (habilidade rápida e segunda habilidade hoje) saem ou ganham outra função?

---

## 6. Coleta, ferramentas e pesca

### 6.1 Coleta

**Regras (decidido):**

- **Graveto deixa de existir.** Tudo que pedia graveto passa a pedir **Madeira**. Madeira passa a ser **coletada no chão**, no lugar do graveto. Itens soltos no chão: **madeira e pedra**.
- **3 slots novos no equipamento:** **Picareta**, **Machado** e **Vara de pesca**.
- **Machado e picareta são só ferramentas**: deixam de ser armas. São **só fabricáveis** (não caem de inimigos) e **equipáveis** no slot.
- Para coletar **árvores** e **pedras grandes**, é preciso ter a ferramenta certa equipada.
- **Interação:** perto de uma árvore ou rocha aparece "**[E] Cortar árvore (4 s)**" / "**[E] Minerar (3 s)**", com o tempo ao lado. A coleta mostra uma **barra de progresso igual à de canalização**.
- O tempo depende da ferramenta (nível de upgrade, qualidade, refino), da proficiência e de `gather_yield`.
- **Upgrade de ferramenta:** nova função que usa a **ferramenta anterior + recursos coletáveis + drops de chefe** (com % de chance) para fazer a próxima. Cada nível aumenta a **efetividade** (rendimento) e a **velocidade** de coleta.

**O que muda:** `data/items/resources.json` (sai `stick`), `data/recipes/*.json` (13 receitas usam `stick`), `data/buildings/pieces.json`, `data/nodes/nodes.json` (6 nós dão graveto), `world.gd` (galhos no chão viram madeira), `resource_node.gd` (coleta por interação com tempo, e não por golpe), `melee_weapon.gd` (hoje o machado coleta golpeando), `equipment.gd` e `equipment_panel.gd` (3 slots), `channel_bar.gd` (reaproveitar), loot (machado/picareta saem dos drops).

**A decidir:**

- Se mover ou levar dano **cancela** a coleta?
- **Onde** se faz o upgrade de ferramenta. Sugestão: uma quarta categoria na Upgrading Machine (seção 12).
- Quantos níveis de ferramenta existem (ex.: pedra → ferro → aço → arcano) e quais drops de chefe cada um pede.

### 6.2 Pesca (decidido)

- Pesca-se nos **lagos que já existem**, com a **vara de pesca** equipada (fabricável).
- A vara tem **"Força de pesca"**: quanto maior, mais chance de peixes melhores. **Iscas** aumentam a força de pesca.
- **Peixes são consumíveis** que dão **buffs** (incluindo regeneração de vida, seção 4). **Cozinhar** na fogueira aumenta a efetividade.
- Peixes poderão ser **vendidos** a NPCs no futuro (seção 13).

**A decidir:** a mecânica da pesca em si (minijogo ou só tempo de espera), a lista de peixes e os buffs de cada um, as iscas (de onde vêm).

---

## 7. Câmera e mouse livre (Alt esquerdo)

**O que fazer:** além de 1ª/3ª pessoa (agora no **F1**), dois modos de controle da câmera, alternados com **Alt esquerdo**:

1. **Mouse travado (atual):** girar o mouse gira a câmera.
2. **Mouse livre:** o cursor aparece e a câmera **só gira segurando o botão direito**. Com o cursor livre, o jogador **clica na HUD**: hotbar, barra da party, engrenagem de layout etc.

**Regras (decidido):**

- **A mira é sempre no centro da tela**, nos dois modos.
- O modo livre serve principalmente para **interagir com a HUD** e para **corpo a corpo**, que não precisa tanto de mira.
- **Magos** podem conjurar **magias em área com um círculo no chão** no modo livre: o círculo segue o cursor, e o clique conjura ali (até o alcance máximo da magia).

**O que muda:** `player.gd` (mouse e câmera; hoje o botão direito é "mirar"), `Input.mouse_mode` espalhado pelas telas (cada tela trava o mouse ao fechar; precisa voltar ao modo escolhido), `debug_hud.gd` (`MOUSE_FILTER_IGNORE` na hotbar vira clicável), `spell_caster.gd` (mira no chão para magias de área: Nova de gelo, Muro de terra), Configurações (modo padrão), `project.godot` (ações novas).

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
- **Buffs temporários** (Descansado, comida, peixes, feitiços de aliados) e **auras recebidas** aparecem como ícones com tempo restante.

### 8.3 HUD personalizável

- **Botão de engrenagem pequeno** ao lado da hotbar abre o **modo de edição da HUD**.
- No modo de edição, o jogador **arrasta** e **redimensiona** as barras laterais (party, esferas) e escolhe **esferas ou arcos** para vida/mana.
- Botão "Restaurar padrão". O layout é salvo nas Configurações (por máquina, não por personagem).

**O que muda:** `debug_hud.gd` e `scenes/ui/debug_hud.tscn` (precisam ser divididos em componentes: esfera, arco, quadro de party, ícones de buff), `settings.gd` (layout salvo), `Network` (lista de jogadores e nomes para a party).

---

## 9. Mundo de RPG: mais inimigos, nomes, níveis

**O que fazer:** **muito mais inimigos e mais variedade** pelo mundo.

**Regras:**

- Cada inimigo tem **nome, nível e barra de HP em cima da cabeça**.
- Nível do inimigo pela **região/distância do spawn** (zonas de nível), para guiar a exploração.
- XP, **ouro** e loot escalam com o nível. Diferença grande de nível reduz a XP (evita farmar área fácil).
- **Chefes** ganham importância: são a fonte dos grimórios exclusivos, dos recursos de evolução de habilidade e dos drops do upgrade de ferramenta (seções 5 e 6). Precisa de mais chefes espalhados pelo mundo.

**O que muda:** `data/zombies/` (renomear para `data/monsters/` e dar nível base, escalas por nível, nomes de fantasia, tabela de drops de chefe), `zombie.gd` (barra flutuante e nível), `world.gd` (densidade e spawn por zona; locais de chefe), `Progression.send_kill_xp`.

**A decidir:** densidade alvo (inimigos por chunk), respawn (tempo ou ao sair da área), limite de inimigos ativos por desempenho (hoje há IA simplificada a mais de 40 m), quantos chefes e onde.

---

## 10. Alvo em aliados e buffs temporários

**O que fazer:** poder **selecionar um aliado como alvo** (clicando nele no mundo ou no quadro da party) para **feitiços de cura** e **buffs temporários**.

**Regras:** feitiços de suporte vão no alvo selecionado. Sem alvo, vão em si mesmo (ou no aliado na mira). O alvo aparece destacado (anel/contorno) e no quadro da party. Alcance máximo por feitiço.

**O que muda:** `spell_caster.gd` (hoje *Remendar* cura todos num raio); o servidor confere a distância, como em `Health.heal_by`. O **sistema de buffs temporários** (efeito, duração, ícone, sincronizado em rede como as auras) é compartilhado com comida, peixes e o "Descansado" da fogueira.

---

## 11. Trade e follow

**Regras (decidido):**

- **Trade:** janela de troca entre dois jogadores (cada um coloca itens e ouro, os dois confirmam, o servidor faz a troca de uma vez só). **Só perto** (ex.: até 10 m).
- **Follow:** o personagem anda sozinho atrás do aliado escolhido, **com pathfinding** (desvia de obstáculos pelo mapa de navegação, como os monstros). Qualquer tecla de movimento cancela.

---

## 12. Afixos e Upgrading Machine (já planejado)

Ver [GDD 8.4](GDD.md): 6 slots (3 prefixos, 3 sufixos) nos equipamentos fabricáveis, de 1 a 6 desbloqueados ao fabricar, e a estação **Upgrading Machine** com as categorias **slots**, **refino** e **qualidade**. Custos e valores a definir. As ferramentas da seção 6 também podem receber afixos (velocidade de coleta, rendimento), e o **upgrade de ferramenta** pode virar uma quarta categoria dela.

---

## 13. Sistemas novos que as decisões pedem

- **Ouro:** moeda nova. Cai de inimigos (escala com o nível) e paga desbloqueio e evolução de habilidades. No futuro: compra e venda com NPCs (peixes, itens). Precisa de: contador no inventário, salvar no personagem, cair na morte ou não (a decidir), entrar no trade.
- **Drops de chefe com % de chance:** grimórios exclusivos, recursos de evolução de habilidade (níveis 5, 10, 15, 20) e materiais de upgrade de ferramenta. Precisa de tabela de drops por chefe em `data/` e de chefes fixos no mundo.
- **Buffs temporários:** ver seção 10.
- **NPCs vendedores** (futuro): onde vendem peixes e outros itens.

---

## 14. Ordem sugerida

Cada passo termina jogável:

1. **Limpeza:** fim de fome/sede e das bandagens, cura por frutas (4); fim do graveto (6.1, parte de dados).
2. **Auras:** interface nova (1), eficiências separadas (3), Pacto de Sangue conversor liberado por ascendência (2).
3. **Telas e controles:** inventário e equipamentos separados (V), câmera no F1, Alt e mouse livre (5, 7).
4. **HUD:** esferas, arco de stamina, números, ícones de buff, engrenagem e layout (8.2, 8.3).
5. **Ouro, buffs temporários e fogueira "Descansado"** (13, 10, 4).
6. **Habilidades:** hotbar de 5, habilidades por classe por nível, evolução com ouro até 20, slot fixo de arma (5).
7. **Coleta e pesca:** slots de ferramentas, coleta com tempo, vara, iscas, peixes e culinária (6).
8. **Mundo RPG:** inimigos com nível, nome, barra e zonas; chefes com drops (9, 13).
9. **Grupo:** party lateral, alvo em aliados, trade e follow (8.1, 10, 11).
10. **Afixos, Upgrading Machine e upgrade de ferramenta** (12, 6.1).

---

## 15. Ideias para aproximar de Path of Exile e outros ARPGs

Sugestões para discutir, não compromissos.

### Itens e loot

- **Raridade:** normal (branco), mágico (azul, até 1 prefixo + 1 sufixo), raro (amarelo, até 3 + 3) e **único** (laranja, efeito especial fixo). Encaixa direto nos 6 slots de afixo.
- **Nível de item:** o nível da área onde caiu limita quais afixos podem sair. Explorar longe dá itens melhores.
- **Moedas de crafting:** em vez de recursos genéricos, orbes que fazem uma ação no item (abrir slot, re-sortear afixos, subir qualidade). Viram os "custos" da Upgrading Machine e a moeda de troca entre jogadores, junto do ouro.
- **Filtro de loot** simples (esconder brancos, destacar raros e únicos) e som/feixe de luz para drop raro.

### Habilidades

- **Gemas de suporte:** encaixadas no equipamento, mudam uma habilidade da hotbar (mais projéteis, área maior, converter para gelo). Dão profundidade aos 5 slots sem precisar de muitas habilidades por classe.
- **Habilidade de movimento** em todas as classes (rolamento, salto, teleporte curto) e **troca rápida de arma** (dois conjuntos no slot fixo).
- **Tipos de dano e estados:** físico, fogo (queimadura), gelo (lentidão/congelar), raio (choque = mais dano recebido), caos/veneno; **acerto crítico**; **resistências** que caem conforme a zona é mais difícil.

### Combate

- **Escudo de energia** como segunda barra de vida para classes mágicas (combina com o Oráculo e o Arcanista).
- **Frascos com cargas** continuam como ideia para depois, se a cura por comida e peixes não bastar no combate.

### Mundo aberto

- **Zonas de nível** em anéis a partir do spawn, com biomas mais perigosos longe.
- **Monstros mágicos e raros** com nome gerado e modificadores ("Rápido", "Explode ao morrer", "Aura de gelo"), em grupos com um líder.
- **Masmorras instanciadas** (entradas no mundo) com modificadores sorteados, um chefe e loot melhor. Fazem o papel dos "mapas" do Path of Exile e são um bom lugar para os chefes dos drops de habilidade.
- **Eventos dinâmicos:** a noite traz invasões, fendas que abrem no mapa e caravanas atacadas. Recompensas para quem estiver perto.
- **Pontos de viagem rápida** (pedras/portais) descobertos explorando, com um portal de volta para a base.
- **Provas de ascendência:** no lugar de só chegar ao nível 30, um desafio (masmorra especial) libera a ascendência e cada ponto dela.

### Base e construção como parte do RPG

- **Estações que dão buffs** além da fogueira (santuário: +10% de XP por 30 min).
- **NPCs que se mudam para a base** depois de resgatados (vendedor que compra peixes, ferreiro que destrava a Upgrading Machine, cartógrafo de masmorras).
- **Baú compartilhado com abas** (como o stash) e um **mercado de troca** entre jogadores.
- **Defesa de base** como evento (ondas de monstros atraídas pelo tamanho da base), reaproveitando as armadilhas.

### Progresso de longo prazo

- **Bestiário:** matar N de cada tipo dá bônus pequenos permanentes.
- **Atlas/mapa de conquistas:** marcar regiões limpas e chefes derrotados libera modificadores mais difíceis e recompensas melhores.
- **Temporadas:** uma mecânica nova a cada atualização, com mundo novo opcional.

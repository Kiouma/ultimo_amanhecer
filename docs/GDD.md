# Documento de Design do Jogo: Zumbi 3D de Sobrevivência

*Título provisório: **Último Amanhecer** (troque quando quiser)*

Versão 0.1 · Documento vivo, para ser atualizado a cada fase do desenvolvimento.

## 1. Visão geral

**Gênero:** sobrevivência em mundo aberto, 3D, primeira pessoa (com opção de terceira pessoa), com crafting, construção de base e combate variado.

**Referência principal:** *7 Days to Die*, com a diferença de que o jogador escolhe um estilo de combate muito mais amplo: **armas de fogo, corpo a corpo (melee) ou magia**, além de combinações entre eles.

**Resumo em uma frase:** *Sobreviva em um mundo tomado por zumbis, colete recursos, construa uma base e escolha como lutar: com balas, aço ou magia.*

**Plataforma-alvo inicial:** PC (Windows/Linux). Mobile e consoles ficam fora do escopo inicial.

**Modo de jogo inicial:** cooperativo online para 4 a 5 jogadores, projetado desde o início; o modo solo também funciona (ver seção 14).

## 2. Pilares de design

Estes pilares guiam toda decisão. Se uma ideia não reforça ao menos um deles, ela entra na lista de "talvez depois".

1. **Liberdade de estilo.** Nenhum estilo de combate (tiro, melee, magia) pode ser claramente superior. Cada um tem força, fraqueza e custo diferentes.
2. **Sobrevivência com tensão.** Recursos são limitados, a noite é perigosa e a horda periódica exige preparação.
3. **Construir é defender.** A base não é decorativa: ela é a principal ferramenta contra as hordas.
4. **Progressão por escolhas.** O jogador evolui pelo que faz e pelas decisões que toma, não só por subir de nível.
5. **Escopo realista.** Começar pequeno, ter um jogo jogável cedo e crescer em camadas.

## 3. Loop de jogo

**Loop de curto prazo (minutos):** explorar → coletar recursos → combater zumbis → voltar à base.

**Loop de médio prazo (um dia de jogo):** de dia, sair para coletar e saquear; ao entardecer, reforçar a base; de noite, defender e sobreviver.

**Loop de longo prazo (várias horas):** evoluir o personagem, desbloquear receitas melhores, expandir a base, enfrentar hordas maiores, explorar áreas perigosas e sobreviver o máximo de dias possível.

## 4. Personagem e estilos de jogo

### 4.1 Proficiências

O jogo não tem atributos. O personagem evolui pelo uso: cada proficiência sobe sozinha quando o jogador faz a ação ligada a ela.

| Proficiência | Como sobe | Efeito |
| --- | --- | --- |
| **Crafting e construção** | Construir peças e fabricar itens | Mais qualidade e velocidade ao fabricar, menor custo de materiais, novas receitas |
| **Atletismo** | Correr e pular | Maior velocidade de movimento, menos dano de queda |
| **Resistência** | Receber dano | Redução do dano recebido |
| **Armas de fogo** | Disparar e acertar | Mais precisão, recarga mais rápida, menos recuo |
| **Melee** | Golpear inimigos | Mais dano e velocidade, menos stamina por golpe |
| **Magia** | Conjurar feitiços | Mais mana, menor custo, mais dano |
| **Furtividade** | Agachar e se mover sem ser ouvido | Menos barulho, mais dano em ataque surpresa |
| **Sobrevivência** | Coletar, cozinhar e curar | Mais rendimento, comida e kits médicos melhores |

**Regras gerais (propostas):** cada proficiência vai do nível 1 ao 100 (valor provisório) e pede mais experiência a cada nível. Ações repetidas sem risco, como pular em loop, dão ganho decrescente para evitar abuso. Resistência só sobe com dano real recebido em jogo.

**Como está implementado (Fase 6):** XP para subir do nível N = 10·N^1,4. Acima de 60 XP por minuto numa proficiência, o ganho cai para 20% (anti-abuso). Cada nível dá um bônus pequeno (ex.: Melee +0,5% de dano e −0,4% de stamina por nível; Resistência −0,25% de dano recebido por nível, até −25% no 100; Atletismo +0,2% de velocidade). Pontaria (nome no jogo de "Armas de fogo") cobre arcos e armas de fogo. Metade da XP de proficiência vai para o nível do personagem; abates dão vida máxima do inimigo ÷ 5 (andarilho 20, Colosso 500). A morte tira 10% da XP acumulada rumo aos próximos níveis (sem perder nível). **Maestria de arma:** cada tipo (arco, arma de fogo, armas brancas, feitiços) sobe com o uso, até +10% de dano. Painel na tecla **P**.

### 4.2 Árvore passiva, ascendência e auras

O sistema de classes segue a ideia dos ARPGs de árvore passiva grande: **a classe inicial só define o ponto de partida na árvore**; a especialização de verdade vem dos nós escolhidos e, no nível 30, da **ascendência**. As antigas trilhas de habilidades (Atirador, Guerreiro, Arcano, Sobrevivente) saíram; os efeitos delas viraram nós da árvore.

#### 4.2.1 Árvore passiva (implementado)

- **393 nós:** 340 pequenos, 41 notáveis, 8 pedras angulares e 4 inícios de classe. Dados em `data/passives/passive_tree.json`, **gerado** por `tools/gen_passive_tree.py` (nomes e efeitos ficam em tabelas no script; posições e ligações são calculadas). Para mudar a árvore, edite o script e rode `py tools/gen_passive_tree.py`.
- **Formato:** radial. No centro, o notável *Último Amanhecer* ligado às 4 classes por raios de 3 nós. Anel interno com os inícios: **Guerreiro** à esquerda (corpo a corpo, vida, defesa), **Pugilista** em cima (mãos vazias, ritmo, regeneração), **Mago** à direita (magia, mana, auras) e **Arqueiro** embaixo (arco, arremesso, velocidade). Cada classe tem 3 ramos com 2 clusters (anel de 6 nós pequenos com um notável no meio) e termina em notável (laterais) ou pedra angular (meio). Entre as classes ficam 4 setores híbridos (Monge, Arcano-arqueiro, Caçador, Bárbaro), ligados aos vizinhos por pontes.
- **Tipos de nó:** pequeno (+3 a 5% de algo), notável (bônus maior e combinado, ~3×) e **pedra angular** (efeito forte com um custo, ex.: *Fúria Imprudente*: +40% de dano corpo a corpo e +15% de dano recebido).
- **Regras:** 1 ponto por nível do personagem (nível máximo 100 → 99 pontos para 389 nós, então é preciso escolher). Só se aloca um nó ligado a outro já alocado (ou ao início da sua classe). O início de outra classe não pode ser alocado nem atravessado; o anel interno e as ligações entre os primeiros nós dos ramos permitem chegar a qualquer setor por fora. **Botão direito devolve** o ponto, se nenhum outro nó depender dele; "Devolver tudo" limpa a árvore. Por enquanto devolver é grátis (no futuro pode custar um recurso).
- **Efeitos** são os mesmos modificadores do resto do jogo (`melee.damage`, `max_mana_add`...) mais os novos: `max_health_add` (vida máxima), `life_regen_add` (vida/s, sempre ligada), `mana_regen` e `stamina_regen` (multiplicam a regeneração), `aura_effect`, `aura_radius` e `reservation_efficiency` (auras).
- **Tela:** Personagem (P) → aba *Árvore passiva*. Arrastar move, roda dá zoom, a busca destaca nós pelo nome ou efeito, passar o mouse mostra o nó, o efeito e se dá para alocar.

#### 4.2.2 Ascendência (implementado)

- Escolhida a partir do **nível 30**, uma das 2 da classe, **definitiva**. Dá um bônus fixo na hora e **pontos de ascendência** nos níveis 30, 45, 60 e 75 (4 no total) para desbloquear 4 dos 6 nós dela (livres, sem ordem).
- Guerreiro: **Vanguarda** (tanque e auras de grupo) ou **Carniceiro** (ofensiva com armas). Arqueiro: **Sentinela** (precisão) ou **Andarilho** (mobilidade, arremesso, coleta). Mago: **Arcanista** (poder mágico) ou **Oráculo** (suporte: auras mais fortes, maiores e mais baratas). Pugilista: **Asceta** (socos rápidos e regeneração) ou **Rompe-Ossos** (força bruta).
- Dados em `data/ascendancies/ascendancies.json`. Tela: Personagem (P) → aba *Ascendência*.

#### 4.2.3 Auras (implementado)

- **Bônus em área** para o jogador e os aliados próximos (raio base 12 m), pagos com uma **reserva de mana** (ou de vida, no *Pacto de Sangue*) enquanto ficam ligadas. A parte reservada não pode ser usada: com 40% de mana reservada, a barra só enche até 60%.
- **Tela (tecla C):** quadrados com as auras; clique liga/desliga. Passar o mouse mostra embaixo o **nível da aura como título**, a descrição e o efeito atual, e a **barra de reserva** com a % no topo: o jogador escolhe de **1% a 35%** e o efeito cresce na mesma proporção (os efeitos do JSON são por 1% reservado). A soma reservada de cada recurso vai até 90%.
- **Nível 1 a 20:** sobe com o tempo ligada (90·N^1,3 segundos para o próximo); cada nível dá +4% de efeito.
- **Não acumula:** a mesma aura de dois jogadores não soma, vale a mais forte. Auras diferentes somam.
- **9 auras:** Brasa da Guerra (dano corpo a corpo e desarmado), Olhar do Caçador (dano à distância e arremesso), Maré Arcana (dano mágico e regeneração de mana), Égide de Pedra (menos dano recebido, nível 5), Fôlego Coletivo (stamina, nível 8), Vento Ligeiro (velocidade de movimento e ataque, nível 10), Fonte Vital (regeneração de vida e cura, nível 12), Véu Antimágico (resistência a magia, nível 15) e Pacto de Sangue (todo dano; reserva vida, nível 20). Dados em `data/auras/auras.json`.
- **Rede:** o dono publica as auras ligadas em `Player.net_auras` ("id,força,raio;..."), replicado pelo MultiplayerSynchronizer; cada máquina calcula só o que o próprio jogador recebe (com limites de força e raio). Quem tem aura ligada aparece com um anel colorido nos pés. O HUD lista as auras recebidas ("Auras: Brasa da Guerra (Fulano)").

### 4.2.4 Equipamento (implementado)

Oito slots: capacete, armadura, calça, botas, luvas, 2 anéis e colar. Cada peça dá **proteção** (armadura A reduz o dano em A/(A+100)) e um bônus próprio. Quatro **conjuntos** de 7 peças (5 de armadura + anel + colar), um por estilo: Caçador (atirador), Guerreiro (melee/tanque, mais proteção e um pouco mais lento), Arcano (mana e dano mágico) e Sombra (silêncio, ataque surpresa e arremesso). 2, 4 e 6 peças do mesmo conjunto liberam bônus extras. Peças gastam durabilidade ao levar golpes e quebradas não protegem até o conserto. Dados em `data/items/gear.json` e `data/sets/sets.json`.

### 4.3 Builds de exemplo

| Build | Combinação | Estilo de jogo |
| --- | --- | --- |
| **Franco-atirador** | Arqueiro → Sentinela; setor Caçador e pedra *Tiro Certeiro* | Mata de longe, tiros na cabeça |
| **Tanque de machado** | Guerreiro → Vanguarda; clusters de vida e defesa | Entra no meio dos monstros e segura portas |
| **Mago de campo** | Mago → Arcanista; pedra *Pacto Arcano* | Feitiços fortes, usa fogo e gelo |
| **Cavaleiro arcano** | Guerreiro indo pelo centro até o setor do Mago | Corpo a corpo com magia de apoio |
| **Monge** | Pugilista → Asceta; setor Monge e aura Brasa da Guerra | Socos rápidos, regeneração e aura |
| **Curandeiro / suporte** | Mago → Oráculo; *Coração das Auras* e várias auras ligadas | Sustenta o grupo com auras (útil no co-op) |

### 4.4 Criação de personagem

O jogador escolhe aparência básica, um **passado** (que dá pequenos bônus iniciais) e começa com todas as proficiências no nível 1. Exemplos de passado: Ex-militar (Armas de fogo mais alta, começa com arco e flechas extras; arma de fogo só achando ou fabricando), Lenhador (Melee mais alta, começa com machado), Estudante de ocultismo (Magia mais alta, começa com um grimório simples), Enfermeiro (Resistência mais alta, kit médico).

**Implementado:** a **classe** (Guerreiro, Arqueiro, Mago, Pugilista) é escolhida no menu inicial e define **só o início na árvore passiva** (seção 4.2); não dá mais níveis de proficiência. Cada classe tem um conjunto inicial fabricável e o Mago já conhece *Dardo de fogo* (sem isso não teria o que conjurar). Aparência ainda não é escolhível. Dados em `data/backgrounds/backgrounds.json` (campo `tree_start`).

## 5. Sistema de combate

### 5.1 Princípios

- Combate em tempo real, com impacto físico (feedback de golpes, tremor de câmera leve, sons marcantes).
- Cada estilo usa um recurso diferente: **flechas ou munição** (à distância), **stamina** (melee), **mana** (magia).
- Os zumbis reagem a barulho: tiros e magias explosivas chamam mais inimigos; arco, melee e magias silenciosas chamam menos.

### 5.2 Armas à distância

**Arco e flecha (arma inicial):**

- Segurar o ataque puxa a corda; quanto mais puxada, mais dano e alcance. Soltar dispara.
- A flecha é um projétil com queda (gravidade). Quase não faz barulho: ideal para furtividade.
- **Flecha = pena + graveto**, fabricada nas mãos. Flechas que erram ficam cravadas e podem ser recuperadas (chance).
- Tipos futuros: flechas de pedra/metal, incendiárias, encantadas.

**Armas de fogo (alto custo, emergência):**

- Para hordas e chefes. Raras no saque; munição cara (metal, pólvora, bancada de armas).
- Tipos: pistola, revólver, submetralhadora, escopeta, rifle de ação, rifle de precisão.
- Mecânicas: recarga, recuo, dispersão, mira com zoom, durabilidade da arma, modificações (mira, cano, silenciador, carregador estendido).
- Munição é fabricada ou saqueada. Existem tipos especiais (perfurante, incendiária).

### 5.3 Melee

- Categorias: leve (faca, cano), média (machado, espada), pesada (marreta, martelo de guerra), alcance (lança).
- Mecânicas: ataque rápido e ataque carregado, bloqueio/aparar, stamina por golpe, durabilidade, sangramento em lâminas, atordoamento em armas pesadas.
- Armas melee podem ser melhoradas na bancada (afiar, reforçar, encantar).

### 5.2.1 Armas da expansão (Fase 9)

Facão (rápido, também corta árvore), Marreta (lenta, 70 de dano, ótima em rocha), Besta (virotes; puxada de 1,6 s e 75 de dano), Escopeta (8 chumbos de 14, cartuchos, 25 m) e Rifle de caça (85 de dano, 160 m, zoom forte ao mirar). Facão, marreta, besta e virotes saem na bancada; escopeta e rifle (e a munição deles) só no saque, principalmente no posto militar.

### 5.3.1 Carga e canalização (implementado)

Segurar o botão esquerdo: melee carrega o golpe (gasta stamina enquanto segura; até 2,5× de dano em 1,5 s); o cajado canaliza a última habilidade (gasta mana enquanto segura, até 6× o custo; até 3× de dano, cura, alcance e raio em 2 s); a faca de arremesso ganha força (até 2× de dano e mais alcance). Adaga (rápida, 2× de bônus em ataque surpresa) e faca de arremesso (recuperável, 1,6×) servem à furtividade. Barra de carga acima da hotbar.

### 5.4 Magia

- A magia é rara: grimórios e cristais são difíceis de achar. Feitiços são aprendidos com **grimórios** encontrados ou fabricados. O jogador equipa um número limitado de feitiços (3 a 5 slots).
- Cada feitiço tem custo de mana, tempo de conjuração e recarga.
- **Interações elementais:** zumbi molhado + raio = dano extra; gelo + marreta = estilhaçar; fogo em prédio de madeira = risco de incêndio (para o jogador também).
- Regeneração de mana é lenta. Itens (poções, cristais) ajudam, o que mantém a magia equilibrada.

**Feitiços implementados:** Dardo de fogo (projétil), Nova de gelo (dano e lentidão de 65% por 4 s num raio de 5 m em volta), Raio em cadeia (acerta o zumbi mirado e pula para até 3 vizinhos a 6 m, perdendo 20% por pulo), Remendar (cura você e os aliados a até 5 m) e Muro de terra (parede de terra com 400 de vida à frente, por 20 s). **Grimórios** ensinam feitiços ao serem lidos (clique com ele na mão) e pedem um nível mínimo de Magia (vida 2, gelo 3, terra 5, tempestade 6). Os da vida e do gelo aparecem no mapa; a bancada copia qualquer um com cristal arcano (que vem das hordas e do Colosso).

### 5.5 Equilíbrio entre estilos

| Estilo | Dano | Alcance | Custo recorrente | Barulho | Risco |
| --- | --- | --- | --- | --- | --- |
| Arco | Médio | Médio/longo (com queda) | Flechas (baratas) | Muito baixo | Errar e ficar sem flechas |
| Fogo | Alto | Longo | Munição (cara) | Alto | Atrair a horda, gastar recurso raro |
| Melee | Médio | Curto | Stamina e durabilidade | Baixo | Ser cercado |
| Magia | Médio/alto em área | Médio | Mana | Variável | Ficar sem mana |

Todos os números são provisórios e serão ajustados com testes (seção 16).

## 6. Zumbis e inimigos

### 6.1 Tipos de zumbi

| Tipo | Comportamento | Desafio |
| --- | --- | --- |
| **Andarilho** | Lento, em grupo | Básico, perigoso em número |
| **Corredor** | Rápido, frágil | Surpreende, exige reação |
| **Bruto** | Muito resistente, ataque forte | Quebra paredes e portas |
| **Cuspidor** | Ataque à distância (ácido) | Danifica construções e armaduras |
| **Infectado noturno** | Mais forte e rápido à noite | Faz a noite ser temida |
| **Explosivo** | Explode ao morrer ou chegar perto | Pune quem luta perto da base |
| **Necromante** (chefe) | Levanta zumbis, resiste a magia comum | Exige estratégia |
| **Colosso** (chefe de horda) | Gigante, destrói muros | Evento especial |

**Implementados:** Andarilho, Corredor, Bruto (1,3× maior, 3× dano em construções), Cuspidor (cospe ácido em arco de 4 a 14 m; o ácido respinga e corrói construções 2,5×), Infectado noturno (escuro, muito rápido à noite), Explosivo (explode ao chegar perto ou ao morrer: até 60 de dano num raio de 4 m, também em zumbis e construções) e o chefe **Colosso** (2,2× maior, 2500 de vida, 6× dano em construções, vem na última onda de cada horda, barra de vida no topo da tela, deixa 6 pedras de refino e 2 cristais). Tamanho e cor de cada tipo vêm de `scale` e `tint` em zombies.json. Em `drops`, valor menor que 1 é chance; 1 ou mais é quantidade garantida.

**Expansão (Fase 9):** **Congelado** (tundra; o golpe deixa você 45% mais lento por 2,5 s) e o chefe **Necromante** (900 de vida, resiste a 50% do dano mágico, levanta 3 andarilhos a cada 12 s, até 8; surge uma vez por noite nas ruínas quando alguém está na zona contaminada e é o chefe das hordas pares; o Colosso fica com as ímpares).

### 6.2 Inteligência artificial

- **Percepção:** visão (cone e distância), audição (barulho de tiros, passos, construção) e olfato (sangue, comida).
- **Estados:** vagando → investigando → perseguindo → atacando → perdendo o alvo.
- **Navegação:** pathfinding até o jogador; se o caminho está bloqueado, zumbis atacam a estrutura mais fraca.
- **Horda:** os zumbis seguem um líder e se espalham para contornar obstáculos, o que evita filas perfeitas.

### 6.3 Outras ameaças

Animais infectados (cães, corvos), saqueadores humanos em fases posteriores e perigos do ambiente (radiação, armadilhas antigas).

## 7. Sobrevivência

Os sistemas abaixo criam pressão sem tornar o jogo cansativo. Todos são ajustáveis nas opções de dificuldade.

- **Vida:** reduzida por dano; regenera devagar se o jogador está bem alimentado.
- **Fome e sede:** caem com o tempo e mais rápido com esforço. Comida cozida dá mais e traz bônus.
- **Stamina:** usada em correr, pular e atacar com melee.
- **Mana:** usada em magias (seção 5.4).
- **Temperatura:** frio e calor afetam o jogador; roupas e fogueiras ajudam.
- **Ferimentos:** sangramento (precisa de bandagem), fratura (reduz velocidade, precisa de tala) e infecção (precisa de antibiótico ou magia de cura).
- **Peso:** o inventário tem limite de peso, incentivando baús e organização da base.

**Morte:**

- Os itens do inventário caem em uma **bag** no local da morte, exceto os itens equipados e as 9 hotkeys principais.
- O personagem perde parte do XP.
- Mortes consecutivas aplicam um **debuff temporário** que escala a cada morte e some com o tempo.

Porcentagem de XP e duração do debuff são provisórias e ajustáveis nas opções de dificuldade.

Implementado na Fase 2 (valores provisórios): a **hotbar (9 slots) conta como o equipado** e fica com o jogador; a mochila vai para a bag, que qualquer jogador pode pegar (E pega tudo; o que não couber cai no chão) e some quando esvazia. Debuff **Fraqueza**: 2 min; cada nível = −7% de velocidade, −10% de dano e −15% de recuperação de stamina; morrer com a Fraqueza ativa sobe um nível (máx. 5) e soma 1 min. Perda de XP: 10%, aplicada quando a progressão existir (Fase 6).

## 8. Crafting

### 8.1 Recursos básicos

Madeira, graveto, pena, pedra, sucata de metal, tecido, couro, ervas, comida, combustível, componentes eletrônicos e **cristais arcanos** (raros, usados em magia).

### 8.2 Estações de crafting

| Estação | O que produz |
| --- | --- |
| **Mãos (sem estação)** | Itens primitivos: tocha, bandagem simples, lança de madeira, **flecha (pena + graveto)** |
| **Fogueira / fogão** | Comida, água fervida |
| **Bancada** | Ferramentas, armas melee, flechas, reparos |
| **Forja** | Metais, lâminas, peças de armas |
| **Bancada de armas** | Armas de fogo, munição, modificações |
| **Mesa arcana** | Poções, grimórios, encantamentos, cristais carregados |
| **Bancada elétrica** | Armadilhas elétricas, torretas, geradores |

### 8.3 Regras de crafting

- **Receitas por desbloqueio:** o jogador aprende receitas por nível, por livros encontrados e por praticar (fabricar muito de um item o melhora).
- **Qualidade:** itens têm qualidade que depende da proficiência de crafting e das habilidades; qualidade maior significa mais dano, durabilidade e eficiência.
- **Desmontar:** itens encontrados podem ser desmontados para recuperar parte dos recursos.
- **Reparo:** armas e ferramentas se desgastam e podem ser reparadas.

Implementado na Fase 3 (valores provisórios): fogueira e bancada como estações colocáveis; fila de fabricação com tempo (receita de estação só avança perto dela). Qualidade **Q1 a Q5** em armas e ferramentas fabricadas: +12% de dano, durabilidade máxima e eficiência de coleta por nível, e menos stamina por golpe; sorteio base Q1 50%, Q2 30%, Q3 14%, Q4 5%, Q5 1%, deslocado para cima pela proficiência de Crafting (Fase 6). Reparo na bancada custa metade da receita proporcional ao desgaste; desmontar devolve metade da receita proporcional à condição.

**Durabilidade zero não destrói o item:** ele fica 0/máx no inventário, sem poder ser usado, até ser reparado (vale também para a tocha).

### 8.4 Próximo: afixos e Upgrading Machine (planejado)

Ainda não implementado; custos e valores serão definidos depois.

- **Slots de atributos adicionais:** todo equipamento fabricável terá **6 slots de afixo**: **3 prefixos** e **3 sufixos** (no estilo dos ARPGs: prefixos tendem a dano e vida/mana; sufixos a velocidades, resistências e utilidade). Os slots nascem **bloqueados**.
- **Ao fabricar**, o item já vem com **1 a 6 slots desbloqueados** (sorteio; a proficiência de Crafting e a qualidade podem puxar para cima). Cada slot desbloqueado recebe um afixo sorteado do grupo dele (prefixo ou sufixo), com valor dentro de uma faixa.
- **Upgrading Machine:** nova estação de fabricação, específica para melhorar equipamento. Três categorias:
  1. **Slots:** desbloquear os slots fechados (e sortear o afixo do slot aberto).
  2. **Refino:** o refino +1 a +12 que hoje fica na bancada passa para cá.
  3. **Qualidade:** aumentar a qualidade (Q1 a Q5) de um item já fabricado.
- **A definir:** recursos gastos por ação, chance de falha (se houver), se é possível re-sortear um afixo, faixas de valores por nível do item, como os afixos aparecem na dica do item e no painel de status. Os afixos devem usar as mesmas chaves de modificador da árvore passiva (`melee.damage`, `max_health_add`, `aura_effect`...), somadas pelo Equipment.

**Refino (+1 a +12):** feito na bancada com **Pedra de refino**, que cai **exclusivamente de inimigos** (campo `drops` em zombies.json; andarilho 15%, bruto 60%...). Cada nível dá +5% de dano e de eficiência de coleta (+12 = +60%); na tocha, mais alcance de luz. Custo por nível: +1 a +3 = 1 pedra, +4 a +6 = 2, +7 a +9 = 3, +10 a +12 = 4 (30 no total). Sempre dá certo (sem chance de falha, por enquanto). Multiplica com a qualidade: Q5 +12 ≈ 2,4× o dano de Q1 +0.

## 9. Construção e base

### 9.1 Sistema de construção

- Construção modular por **blocos e peças** (fundação, parede, piso, teto, escada, porta, janela), encaixadas em grade.
- **Materiais** em níveis: madeira → pedra/tijolo → concreto → aço. Cada nível aumenta vida da peça e custo.
- **Integridade estrutural:** peças precisam de suporte. Remover pilares pode derrubar partes da construção, e zumbis fortes exploram isso.
- **Reparo e melhoria:** peças danificadas podem ser reparadas ou melhoradas sem ser refeitas.

**Como está implementado (Fase 4, etapa 1):**

- Tecla **B** liga o modo construção. A prévia da peça fica verde (dá para construir) ou vermelha (o painel diz o motivo). Roda do mouse troca a peça, **T** troca o material, **R** gira (porta e escada), clique constrói e botão direito desmonta a peça na mira, devolvendo metade do custo proporcional à vida que sobra.
- Grade fixa no mundo: células de 3 × 3 m e andares de 2,5 m. Peças: fundação (só no chão), parede, porta (abre com E), piso/teto (do 1º andar para cima) e escada (rampa de ~40° até o andar de cima).
- Materiais: madeira e pedra (pedra custa mais e tem cerca de 3× a vida). Dados em `data/buildings/pieces.json`.
- **Integridade:** toda peça precisa de um caminho de apoio até o chão. Parede acima do térreo fica sobre outra parede ou sobre um piso; piso fica sobre parede (em uma das bordas) ou preso a um piso vizinho, com balanço de no máximo 2 células; escada acima do térreo fica sobre piso. Quando uma peça some (destruída, desmontada), tudo que perdeu o caminho **desaba em cadeia** e deixa destroços com 25% do material.
- Só inimigos danificam construções. Um zumbi que fica preso atrás de uma construção (ou sem caminho até o alvo) ataca a parede ou porta **mais fraca** na direção do alvo. O campo `structure_damage` em zombies.json é o multiplicador contra construções (o Bruto tem 3×).
- **Martelo** (fabricado nas mãos: 2 madeira + 2 pedra; vem no kit inicial): clique conserta 25% da vida da peça na mira por martelada (custo: metade do custo da peça, proporcional), **R** melhora de madeira para pedra (custo cheio da peça de pedra, volta com vida cheia). Gasta durabilidade do martelo.
- A porta fica fora da malha de navegação: os zumbis traçam caminho por ela e, se estiver fechada, ela costuma ser o primeiro alvo.

### 9.2 Defesa

- **Armadilhas:** espetos, fosso, cerca elétrica, mina, armadilha de fogo.
  - Implementadas (fabricadas na bancada, colocadas pela hotbar como as estações, só ferem inimigos, zumbis passam por cima): **espetos** (3 madeira + 8 gravetos; 12 de dano a cada 0,8 s e lentidão de 55%; 60 usos) e **mandíbula** (3 sucata + 2 gravetos; 45 de dano e prende por 3,5 s; 10 usos). Cada acerto gasta durabilidade; com 0 param de funcionar mas não somem: **E** recolhe com a durabilidade atual e a bancada conserta.
- **Torretas:** automáticas, precisam de munição e energia.
- **Magia defensiva:** muros de terra, runas de gelo no chão, totens de cura.
- **Pontos fortes do projeto:** o jogador pode criar um "funil" para guiar zumbis a um caminho de morte.

### 9.3 Utilidades da base

Baús, cama (ponto de renascimento), horta, coletor de água, gerador, iluminação.

**Implementado:** **Baú** (30 pilhas, compartilhado, servidor manda; clique para guardar/pegar), **Cama** (E: passa a renascer nela; vai no save) e **Coletor de água** (junta 1 garrafa de água limpa a cada 90 s, ou 20 s na chuva, até 10; E enche as garrafas vazias). Baú e coletor nas mãos; cama na bancada. A base também pode ser **ocupada em pontos pré-existentes** do mapa (um posto de gasolina, uma casa), poupando tempo no início.

## 10. Mundo e exploração

### 10.1 Estrutura do mapa

- Mapa de mundo aberto gerado proceduralmente a partir de uma semente (*seed*), com **biomas**: florestas densas (foco principal), lagos e margens com casas abandonadas, planícies, pântano, montanhas e uma zona contaminada.
- **Pontos de interesse:** vilarejos e casas abandonadas, cabanas, fazendas, minas, postos militares antigos e ruínas arcanas (onde se encontra magia).
- O terreno **não precisa ser voxel destrutível** (isso é tecnicamente difícil). A destruição fica concentrada em construções e algumas estruturas do cenário.

**Como está implementado (Fase 7):** mapa de 320 × 320 m gerado por semente (o host sorteia; os clientes recebem com a cena). Biomas: planície (centro, nascimento), floresta, pântano (touceiras de ervas), 5 lagos com margem (encher garrafa/beber), montanhas na borda (relevo de até ~20 m) e uma zona contaminada (cristais arcanos, que se minera com picareta). O chão fora das montanhas e do fundo dos lagos fica em y = 0, para a construção funcionar igual. A malha de navegação dos zumbis é dividida em blocos de 64 m; construir ou derrubar algo refaz só o bloco do lugar. A arena antiga continua disponível com `-- --arena`.

**Bioma da expansão:** **Tundra nevada**, na faixa norte do mapa (70 m depois das montanhas): chão de neve, pinheiros, neve caindo e frio permanente (fome 60% mais rápida longe de fogueira), com Congelados.

### 10.2 Saque e dificuldade por região

**Implementado:** pontos de interesse feitos com peças de construção (dá para ocupar, consertar e reforçar): vilarejo de 4 casas, uma cabana na margem de cada lago, 4 cabanas na floresta, um posto militar (muro de pedra 3 × 3) e ruínas arcanas na zona contaminada. Casas abandonadas às vezes têm parede ou telhado faltando. Saque por tipo de lugar (`data/loot/loot.json`): casas (comida, água, pano, bandagem), posto militar (munição, pistola, kit médico, sucata) e ruínas (cristais, grimórios, pedras de refino).

Regiões mais perigosas têm mais zumbis fortes e melhor saque.

**População implementada:** o servidor mantém zumbis em volta de cada jogador conforme o bioma onde ele está (planície 5, floresta 7, pântano 8 com cuspidores, montanhas 5 com brutos, zona contaminada 11 com infectados, explosivos, cuspidores e brutos), 50% a mais à noite. Eles nascem a 35–60 m (fora de lagos e construções) e somem quando ficam a mais de 95 m de todos sem caçar ninguém; teto de 50 fora da horda. Casas e vilarejos dão mantimentos e ervas, postos militares antigos dão armas de fogo, ruínas dão grimórios e cristais.

### 10.3 Clima

Chuva, neblina, tempestade e frio extremo. O clima afeta visão, barulho (chuva abafa sons) e magia (raio mais forte em tempestade).

**Implementado:** o servidor sorteia o clima a cada 2,5–6 minutos (limpo 50%, chuva 20%, neblina 14%, tempestade 8%, frio 8%). Chuva: zumbis ouvem 30% menos. Tempestade: ouvem 45% menos, relâmpagos e Raio em cadeia +30%. Neblina: zumbis enxergam 45% menos e a névoa fecha a vista. Frio extremo: neve e fome 60% mais rápida, a não ser a até 6 m de uma fogueira. Aviso na tela e no relógio. **F10** (host) troca o clima, para testes.

## 11. Ciclo dia/noite e hordas

- **Dia:** zumbis mais lentos e dispersos. Bom para explorar e coletar.
- **Noite:** zumbis mais agressivos, visibilidade reduzida, mais perigo fora da base.
- **Horda periódica:** a cada **7 dias de jogo** (ajustável), uma grande horda ataca a base do jogador. O tamanho e a composição crescem a cada ciclo.
- **Aviso:** um contador na interface e sinais no ambiente (sons distantes, céu avermelhado) avisam da aproximação.
- **Recompensa:** sobreviver à horda dá itens raros e pontos de progressão.

**Como está implementado (Fase 5):** a horda começa ao anoitecer dos dias 7, 14, 21... (`Horde.every_days`). Vem em 3 ondas, de 1 ou 2 direções, num anel de 34 a 44 m em volta da base (média das peças construídas) ou dos jogadores, e cada zumbi caça o jogador vivo mais perto; se a base bloqueia, ele a ataca. O tamanho cresce com o número da horda e com o número de jogadores (horda 1, 1 jogador: ~20 zumbis); teto de 60 vivos ao mesmo tempo. Termina quando todos morrem (depois da última onda) ou ao amanhecer; cada jogador vivo ganha pedras de refino, cristal arcano, flechas, munição e kit médico (mais a cada horda). Aviso: contador no relógio ("Horda em N dias"), faixa no dia da horda e céu avermelhado a partir das 16h. F9 (no servidor) começa uma horda na hora, para testes.

## 12. Progressão

- **Nível do personagem (1 a 100):** vem de experiência por matar, coletar, construir e fabricar. Cada nível dá 1 ponto na árvore passiva; no 30 libera a ascendência (seção 4.2). As proficiências (seção 4.1) sobem pelo uso, sem pontos a distribuir.
- **Maestria de arma:** usar um tipo de arma melhora aquele tipo (mais dano, menos recuo, menos stamina).
- **Descoberta de receitas e feitiços:** parte da progressão vem de achar livros, plantas e grimórios no mundo.
- **Evolução da base:** desbloqueia materiais, estações e defesas melhores.

## 13. Interface e controles

### 13.1 Interface (HUD)

Barras de vida, stamina, fome, sede e mana; mira central; hotbar de itens e feitiços; bússola; contador de dia/hora; indicador de barulho (o quanto o jogador está sendo ouvido).

### 13.2 Menus

Inventário com peso, tela de crafting com filtros, árvore de habilidades, mapa, diário de missões e opções (gráficos, áudio, controles, dificuldade).

### 13.3 Controles (PC, padrão)

| Ação | Tecla |
| --- | --- |
| Mover | W A S D |
| Correr / agachar | Shift / Ctrl |
| Pular | Espaço |
| Atacar / disparar | Botão esquerdo |
| Mirar / bloquear | Botão direito |
| Usar / interagir | E |
| Inventário | Tab |
| Trocar arma | 1 a 9, roda do mouse |
| Recarregar | R |
| Feitiço rápido | Q / F (configurável) |
| Câmera 1ª / 3ª pessoa | V |
| Modo construção | B (roda = peça, T = material, R = girar, clique = construir, botão direito = desmontar) |
| Personagem (árvore passiva, ascendência, proficiências) | P |
| Auras | C |
| Mapa | M |

Suporte a controle (gamepad) planejado para depois.

## 14. Modos de jogo

| Modo | Descrição | Fase |
| --- | --- | --- |
| **Cooperativo (até 5 jogadores)** | Modo principal: mundo e base compartilhados, papéis complementares | Fase 1 em diante (MVP) |
| **Solo** | A mesma experiência, sem outros jogadores | MVP |
| **Modo livre** | Sem objetivo final, foco em sobreviver (solo ou co-op) | Fase 4 |

No co-op, os papéis se complementam: tanque (melee e Resistência), dano (armas de fogo e magia ofensiva), suporte (Magia de cura e buffs de grupo) e construtor (Crafting e construção). O servidor é autoritativo, e a dificuldade das hordas escala com o número de jogadores.

## 15. Arte, áudio e atmosfera

### 15.1 Estilo visual

Recomendação para um projeto pequeno: **low poly estilizado** ou **semi-realista simplificado**. Isso reduz o custo de produção e ainda dá identidade. Realismo total exige equipe grande e não é recomendado para o início.

### 15.2 Assets

- **Fase de protótipo:** modelos gratuitos (Kenney, Quaternius, itch.io) e formas simples.
- **Fase de produção:** modelos próprios ou comprados, texturas com apoio de IA, e animações de bibliotecas como o Mixamo.
- Verificar sempre a **licença** de cada asset antes de usar em projeto comercial.

### 15.3 Áudio

Sons de passos, tiros, golpes e feitiços são essenciais para o feedback. A música deve ser esparsa e tensa de noite, mais calma de dia. Os gemidos dos zumbis são também um recurso de gameplay (dão pistas de direção).

## 16. Tecnologia

### 16.1 Escolha da engine

| Engine | Vantagens | Desvantagens |
| --- | --- | --- |
| **Godot 4** | Gratuita, leve, código simples (GDScript), ótima para projetos solo | 3D menos avançado que Unity/Unreal, menos assets prontos |
| **Unity** | Muito material e assets, ótimo para 3D, C# | Licença e mudanças de política já causaram polêmica |
| **Unreal Engine** | Gráficos de ponta | Pesada, curva de aprendizado alta, exagero para um primeiro projeto |

**Recomendação:** começar em **Godot 4** (decisão do dono do projeto). Ela atende bem 3D e co-op de 4 a 5 jogadores, com limites: menos assets prontos e 3D menos avançado que Unity e Unreal. Para o co-op, o plano é usar a API de multiplayer de alto nível da engine com servidor autoritativo.

### 16.2 Arquitetura de sistemas

O jogo será dividido em módulos independentes para facilitar o desenvolvimento por partes:

1. **Jogador:** movimento, câmera, vida, stamina, mana, fome, sede.
2. **Combate:** dano, armas de fogo, melee, magia, hitboxes.
3. **Inimigos:** IA, percepção, tipos, hordas.
4. **Inventário e itens:** itens, empilhamento, peso, equipamento, durabilidade.
5. **Crafting:** receitas, estações, qualidade.
6. **Construção:** grade, peças, integridade, materiais.
7. **Mundo:** terreno, biomas, pontos de interesse, saque, ciclo dia/noite, clima.
8. **Progressão:** nível, proficiências, habilidades, maestria.
9. **Interface:** HUD, menus, opções.
10. **Salvamento:** salvar e carregar o estado do mundo e do jogador.
11. **Áudio:** efeitos, música, sons posicionais.

**Dados em arquivos:** itens, receitas, zumbis e feitiços ficam em arquivos de dados (JSON ou recursos da engine), não dentro do código. Isso permite adicionar conteúdo sem reescrever sistemas.

### 16.3 Desempenho

- Limitar zumbis ativos ao mesmo tempo (por exemplo, 30 a 60 com IA completa, o resto com IA simplificada).
- Usar *object pooling* para balas, efeitos e zumbis.
- Carregar o mundo em pedaços (*chunks*) próximos ao jogador.
- Níveis de detalhe (LOD) para modelos distantes.

### 16.4 Uso de IA no desenvolvimento

- **Código:** gerar sistemas por módulo, revisar, testar e iterar. Pedir um sistema por vez e testar antes de seguir.
- **Conteúdo:** nomes de itens, descrições, receitas, diários e falas.
- **Balanceamento:** discutir tabelas de dano, custos e dificuldade.
- **Cuidado:** código gerado precisa ser testado. O jogador (você) continua sendo quem decide o que está bom ou ruim.

## 17. Roadmap de desenvolvimento

Cada fase termina com algo **jogável**. Não avance para a próxima sem testar a anterior.

| Fase | Objetivo | Entrega jogável |
| --- | --- | --- |
| **0. Preparação** | Escolher engine, configurar projeto, controle de versão (Git) | Projeto vazio rodando |
| **1. Núcleo** | Movimento, câmera (1ª e 3ª pessoa), um mapa plano, um zumbi que persegue, uma arma de cada estilo (tiro, melee, magia simples) e rede desde o início (2 ou mais jogadores no mesmo mapa) | Arena onde você e amigos lutam com os três estilos |
| **2. Sobrevivência** | Vida, fome, sede, stamina, inventário, coleta de recursos, ciclo dia/noite | Sobreviver alguns dias coletando |
| **3. Crafting** | Receitas, estações, qualidade, durabilidade | Fabricar armas e ferramentas |
| **4. Construção** | Sistema de blocos, materiais, integridade, armadilhas | Construir uma base e defendê-la |
| **5. Hordas** | Horda periódica, mais tipos de zumbi, chefe | Ciclo completo de 7 dias |
| **6. Progressão** | Proficiências, árvores de habilidades, maestria, grimórios | Builds distintas |
| **7. Mundo** | Terreno maior, biomas, cidades, saque por região, clima | Exploração real |
| **8. Polimento** | Interface, som, balanceamento, salvamento, otimização | Versão testável por outras pessoas |
| **9. Expansão** | Mais conteúdo (biomas, chefes, armas) | Pós-lançamento |

**Produto mínimo viável (MVP):** fases 0 a 5. Se chegar nisso, já existe um jogo de sobrevivência com os três estilos de combate, crafting, construção e hordas.

**Fase 8 (em andamento):** salvamento implementado. O host salva o mundo em `user://save/world.json` (semente, dia/hora, clima, peças com vida e portas, estações, armadilhas, itens e bags no chão); cada jogador salva o próprio personagem em `user://save/character.json` (inventário, vida, fome/sede, Fraqueza, proficiências, habilidades, maestria e posição, se for o mesmo mundo). Salva a cada 2 min, ao fechar a janela e pelo menu de pausa (Esc), que também tem sair para o menu, sensibilidade do mouse e volume. **Som provisório** sintetizado por código (autoload `Sfx`): arco, tiro, golpe, acerto, gemido de zumbi, explosão, feitiço, trovão, passos, construção, porta. Para trocar por áudio de verdade, basta apontar o nome do som para o arquivo em `Sfx.SOUND_FILES`. **Otimização:** objetos somem com a distância (árvores 140 m, rochas 110 m, coisas pequenas 45 m, nome de item 18 m), sombras do sol só até 70 m e zumbis a mais de 40 m de todos (sem caçar) pensam a cada 4 quadros. No mundo: ~1300 chamadas de desenho (eram ~2300) e física abaixo de 1 ms por quadro. **Interface e balanceamento:** marca de acerto na mira (amarela em ataque surpresa); a vida do Colosso escala com jogadores e com a horda (solo na horda 1: 55%). **Exportação:** preset Windows em `export_presets.cfg` (saída em `build/windows/`, fora do git); falta instalar os modelos de exportação no editor.

## 18. Riscos e como reduzi-los

| Risco | Impacto | Mitigação |
| --- | --- | --- |
| Escopo grande demais | Projeto nunca termina | Seguir o roadmap por fases, cortar sem dó |
| Três estilos de combate desbalanceados | Todos escolhem o mesmo | Testar cedo, ajustar números em arquivos de dados |
| Desempenho com muitos zumbis | Jogo trava | Limite de inimigos ativos, IA simplificada à distância |
| Sistema de construção complexo | Bugs, atrasos | Começar com blocos simples, integridade só na fase 4 |
| Assets inconsistentes | Visual feio ou confuso | Estilo low poly único, paleta definida |
| Licenças de assets | Problemas jurídicos | Registrar a origem e a licença de cada asset |
| Perda de motivação | Abandono | Entregas jogáveis curtas, mostrar para amigos cedo |

## 19. Fora do escopo (por enquanto)

- Terreno voxel totalmente destrutível.
- Servidores públicos e matchmaking (o co-op é entre amigos, por convite).
- Mundo gigante com cidades geradas de forma complexa.
- Gráficos realistas de alto nível.
- Modding oficial.

## 20. Glossário

- **GDD:** *Game Design Document*, este documento.
- **MVP:** produto mínimo viável.
- **HUD:** informações na tela durante o jogo.
- **IA (jogo):** comportamento dos inimigos, diferente da IA generativa.
- **Chunk:** pedaço do mundo carregado por demanda.
- **LOD:** nível de detalhe de um modelo conforme a distância.
- **Seed:** número que gera um mapa de forma repetível.
- **Object pooling:** reaproveitar objetos em vez de criá-los e destruí-los toda hora.

## 21. Decisões tomadas

Respostas do dono do projeto às perguntas da versão 0.1. Elas guiam o resto do documento.

1. Câmera: primeira e terceira pessoa, com troca durante o jogo.
2. Engine: Godot 4 (ver seção 16.1).
3. Ambientação: mundo fantasioso com florestas, recursos para coletar e lagos com casas abandonadas.
4. Magia: séria e rara, mas com especialização possível (por exemplo, um curandeiro que dá buffs ao grupo).
5. Cooperativo: prioridade. O jogo deve suportar pelo menos 4 a 5 amigos jogando juntos.
6. Morte: os itens do inventário caem em uma bag no chão, exceto os equipados e as 9 hotkeys principais. O personagem perde XP e recebe um debuff temporário que escala em mortes consecutivas.
7. Armas à distância: o **arco** é a arma inicial e do dia a dia; flecha = pena + graveto. **Armas de fogo** são equipamento de alto custo, para momentos de extrema necessidade (hordas, chefes).

## 22. Próximos passos

**Virada para RPG de exploração:** o plano detalhado (interface de auras nova, Pacto de Sangue como conversor, fim de fome/sede, hotbar de 5 habilidades por classe, coleta com ferramentas, câmera com Alt, HUD nova e personalizável, inimigos com nível, alvo em aliados, trade/follow e ideias no estilo Path of Exile) está em [PROXIMOS_PASSOS.md](PROXIMOS_PASSOS.md).

**Já planejado antes:**

1. **Afixos e Upgrading Machine** (seção 8.4): 6 slots (3 prefixos, 3 sufixos) nos equipamentos fabricáveis, de 1 a 6 desbloqueados ao fabricar; estação Upgrading Machine com as categorias slots, refino e qualidade. Definir custos e valores.
2. **Balancear a árvore passiva e as auras** jogando: valores dos nós, custo de devolver pontos, curva de XP até o nível 30 (ascendência).
3. Traduzir os textos novos (árvore, ascendência, auras) em `data/i18n`.

**Do início do projeto (concluídos):**

1. Revisar este documento e responder às perguntas em aberto (seção 21).
2. Escolher a engine e instalar.
3. Começar a **Fase 1**: um protótipo com movimento, um zumbi e uma arma de cada estilo. Posso gerar esse código passo a passo ou montar um protótipo jogável no navegador para testar o conceito antes.

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

### 4.2 Trilhas de habilidades

O jogador gasta pontos de habilidade livremente em qualquer trilha, mas cada habilidade exige um nível mínimo da proficiência ligada a ela (por exemplo, golpe giratório pede Melee nível 5). Especializar-se dá bônus fortes; misturar dá flexibilidade.

**Trilha do Atirador (armas de fogo)**

- Pistolas, rifles, escopetas e armas de precisão.
- Habilidades: recarga rápida, tiro na cabeça com bônus de dano, munição reaproveitada (chance de não gastar bala), silenciador, tiro penetrante.
- Ponto forte: dano à distância e controle de zumbis perigosos.
- Ponto fraco: munição escassa e barulho que atrai hordas.

**Trilha do Guerreiro (melee)**

- Facas, machados, marretas, lanças, bastões e espadas improvisadas.
- Habilidades: golpe giratório, defesa/aparar, golpe pesado carregado, execução silenciosa, resistência a dano.
- Ponto forte: silencioso, sem munição, ótimo em corredores e portas.
- Ponto fraco: exige proximidade e gasta stamina.

**Trilha do Arcano (magia)**

- Escolas de magia: **Fogo** (dano em área), **Gelo** (controle e lentidão), **Raio** (cadeia entre inimigos), **Vida/Espírito** (cura, escudos, aliados), **Terra** (muros e armadilhas mágicas).
- Habilidades: aumentar mana, reduzir custo de feitiços, combinar elementos, invocações temporárias e especialização em suporte (Curandeiro): buffs de grupo, cura em área, escudos e auras.
- Ponto forte: poder em área e utilidade (cura, iluminação, construção rápida).
- Ponto fraco: depende de mana, que regenera devagar e exige itens raros para crescer.

**Trilha do Sobrevivente (utilidade)**

- Coleta, culinária, medicina, furtividade, arrombamento, mecânica.
- Habilidades: rendimento maior ao coletar, comida que dá bônus, kits médicos melhores, menos ruído ao andar.

### 4.3 Builds de exemplo

| Build | Combinação | Estilo de jogo |
| --- | --- | --- |
| **Franco-atirador** | Armas de fogo + Furtividade | Mata de longe, usa a base como torre |
| **Tanque de machado** | Melee + Resistência | Entra na horda e segura portas |
| **Mago de campo** | Magia | Controla áreas, usa fogo e gelo |
| **Cavaleiro arcano** | Melee + Magia | Melee com armas encantadas |
| **Engenheiro** | Crafting e construção + Armas de fogo | Armadilhas, torretas e rifles |
| **Curandeiro** | Resistência + Magia (Vida) | Sustenta o grupo (útil no co-op) |

### 4.4 Criação de personagem

O jogador escolhe aparência básica, um **passado** (que dá pequenos bônus iniciais) e começa com todas as proficiências no nível 1. Exemplos de passado: Ex-militar (Armas de fogo mais alta, começa com pistola), Lenhador (Melee mais alta, começa com machado), Estudante de ocultismo (Magia mais alta, começa com um grimório simples), Enfermeiro (Resistência mais alta, kit médico).

## 5. Sistema de combate

### 5.1 Princípios

- Combate em tempo real, com impacto físico (feedback de golpes, tremor de câmera leve, sons marcantes).
- Cada estilo usa um recurso diferente: **munição** (fogo), **stamina** (melee), **mana** (magia).
- Os zumbis reagem a barulho: tiros e magias explosivas chamam mais inimigos, melee e magias silenciosas chamam menos.

### 5.2 Armas de fogo

- Tipos: pistola, revólver, submetralhadora, escopeta, rifle de ação, rifle de precisão.
- Mecânicas: recarga, recuo, dispersão, mira com zoom, durabilidade da arma, modificações (mira, cano, silenciador, carregador estendido).
- Munição é fabricada ou saqueada. Existem tipos especiais (perfurante, incendiária).

### 5.3 Melee

- Categorias: leve (faca, cano), média (machado, espada), pesada (marreta, martelo de guerra), alcance (lança).
- Mecânicas: ataque rápido e ataque carregado, bloqueio/aparar, stamina por golpe, durabilidade, sangramento em lâminas, atordoamento em armas pesadas.
- Armas melee podem ser melhoradas na bancada (afiar, reforçar, encantar).

### 5.4 Magia

- A magia é rara: grimórios e cristais são difíceis de achar. Feitiços são aprendidos com **grimórios** encontrados ou fabricados. O jogador equipa um número limitado de feitiços (3 a 5 slots).
- Cada feitiço tem custo de mana, tempo de conjuração e recarga.
- **Interações elementais:** zumbi molhado + raio = dano extra; gelo + marreta = estilhaçar; fogo em prédio de madeira = risco de incêndio (para o jogador também).
- Regeneração de mana é lenta. Itens (poções, cristais) ajudam, o que mantém a magia equilibrada.

### 5.5 Equilíbrio entre estilos

| Estilo | Dano | Alcance | Custo recorrente | Barulho | Risco |
| --- | --- | --- | --- | --- | --- |
| Fogo | Alto | Longo | Munição | Alto | Acabar sem balas |
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

## 8. Crafting

### 8.1 Recursos básicos

Madeira, pedra, sucata de metal, tecido, couro, ervas, comida, combustível, componentes eletrônicos e **cristais arcanos** (raros, usados em magia).

### 8.2 Estações de crafting

| Estação | O que produz |
| --- | --- |
| **Mãos (sem estação)** | Itens primitivos: tocha, bandagem simples, lança de madeira |
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

## 9. Construção e base

### 9.1 Sistema de construção

- Construção modular por **blocos e peças** (fundação, parede, piso, teto, escada, porta, janela), encaixadas em grade.
- **Materiais** em níveis: madeira → pedra/tijolo → concreto → aço. Cada nível aumenta vida da peça e custo.
- **Integridade estrutural:** peças precisam de suporte. Remover pilares pode derrubar partes da construção, e zumbis fortes exploram isso.
- **Reparo e melhoria:** peças danificadas podem ser reparadas ou melhoradas sem ser refeitas.

### 9.2 Defesa

- **Armadilhas:** espetos, fosso, cerca elétrica, mina, armadilha de fogo.
- **Torretas:** automáticas, precisam de munição e energia.
- **Magia defensiva:** muros de terra, runas de gelo no chão, totens de cura.
- **Pontos fortes do projeto:** o jogador pode criar um "funil" para guiar zumbis a um caminho de morte.

### 9.3 Utilidades da base

Baús, cama (ponto de renascimento), horta, coletor de água, gerador, iluminação. A base também pode ser **ocupada em pontos pré-existentes** do mapa (um posto de gasolina, uma casa), poupando tempo no início.

## 10. Mundo e exploração

### 10.1 Estrutura do mapa

- Mapa de mundo aberto gerado proceduralmente a partir de uma semente (*seed*), com **biomas**: florestas densas (foco principal), lagos e margens com casas abandonadas, planícies, pântano, montanhas e uma zona contaminada.
- **Pontos de interesse:** vilarejos e casas abandonadas, cabanas, fazendas, minas, postos militares antigos e ruínas arcanas (onde se encontra magia).
- O terreno **não precisa ser voxel destrutível** (isso é tecnicamente difícil). A destruição fica concentrada em construções e algumas estruturas do cenário.

### 10.2 Saque e dificuldade por região

Regiões mais perigosas têm mais zumbis fortes e melhor saque. Casas e vilarejos dão mantimentos e ervas, postos militares antigos dão armas de fogo, ruínas dão grimórios e cristais.

### 10.3 Clima

Chuva, neblina, tempestade e frio extremo. O clima afeta visão, barulho (chuva abafa sons) e magia (raio mais forte em tempestade).

## 11. Ciclo dia/noite e hordas

- **Dia:** zumbis mais lentos e dispersos. Bom para explorar e coletar.
- **Noite:** zumbis mais agressivos, visibilidade reduzida, mais perigo fora da base.
- **Horda periódica:** a cada **7 dias de jogo** (ajustável), uma grande horda ataca a base do jogador. O tamanho e a composição crescem a cada ciclo.
- **Aviso:** um contador na interface e sinais no ambiente (sons distantes, céu avermelhado) avisam da aproximação.
- **Recompensa:** sobreviver à horda dá itens raros e pontos de progressão.

## 12. Progressão

- **Nível do personagem:** vem de experiência por matar, coletar, construir e fabricar. Cada nível dá pontos de habilidade; as proficiências (seção 4.1) sobem pelo uso, sem pontos a distribuir.
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
| Feitiço rápido | Q / R (configurável) |
| Modo construção | B |

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

## 22. Próximos passos

1. Revisar este documento e responder às perguntas em aberto (seção 21).
2. Escolher a engine e instalar.
3. Começar a **Fase 1**: um protótipo com movimento, um zumbi e uma arma de cada estilo. Posso gerar esse código passo a passo ou montar um protótipo jogável no navegador para testar o conceito antes.

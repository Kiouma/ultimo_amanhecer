# Assets

Coloque aqui todos os arquivos de arte e som do jogo. Antes de usar qualquer asset, registre a origem e a licença em [LICENSES.md](LICENSES.md) (GDD seção 18).

| Pasta | O que vai nela |
| --- | --- |
| `_incoming/` | Arquivos brutos e downloads ainda não organizados (.zip, .blend, .psd). **O Godot ignora esta pasta** (tem um `.gdignore`). Depois de revisar, exporte/mova para a pasta certa. |
| `models/characters/` | Jogador, NPCs |
| `models/zombies/` | Os tipos de zumbi (GDD 6.1) |
| `models/weapons/` | Armas de fogo, melee, grimórios |
| `models/props/` | Baús, móveis, itens soltos no mapa |
| `models/environment/` | Árvores, pedras, vegetação, terreno |
| `models/buildings/` | Peças de construção e casas pré-existentes |
| `textures/` | Texturas avulsas (albedo, normal, roughness) |
| `materials/` | Materiais `.tres` do Godot |
| `animations/` | Animações (ex.: Mixamo) |
| `audio/sfx/` | Tiros, golpes, feitiços, passos, gemidos |
| `audio/music/` | Trilha (dia calmo, noite tensa) |
| `audio/ambience/` | Vento, chuva, floresta |
| `fonts/` | Fontes da interface |
| `ui/`, `ui/icons/` | Elementos de HUD e ícones de itens |
| `shaders/` | Shaders `.gdshader` |
| `vfx/` | Partículas e efeitos |

## Formatos recomendados

- **Modelos 3D:** `.glb` (glTF binário). Funciona sem configurar nada no Godot.
- **Texturas:** `.png` (ou `.webp`), em potências de 2 (512, 1024, 2048).
- **Áudio:** `.ogg` para música e ambiente, `.wav` para efeitos curtos.
- **Nomes de arquivo:** `snake_case`, sem acentos ou espaços (ex.: `zombie_walker.glb`).

## Fontes gratuitas sugeridas

Kenney (kenney.nl), Quaternius (quaternius.com), itch.io e Mixamo para animações. Mesmo nos gratuitos, confira a licença.

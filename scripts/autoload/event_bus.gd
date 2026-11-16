extends Node
## Barramento global de sinais (autoload "EventBus").
## Os módulos do jogo (GDD 16.2) se comunicam por aqui sem depender uns dos outros.
## Ex.: EventBus.night_started.connect(_on_night_started)

@warning_ignore_start("unused_signal")

# Jogador
signal player_spawned(player: Node)
signal player_died(player: Node)

# Mundo / ciclo dia-noite (GDD 11)
signal day_started(day: int)
signal night_started(day: int)
signal horde_incoming(day: int)
## Clima mudou (GDD 10.3): "clear", "rain", "fog", "storm", "cold".
signal weather_changed(state: String)
## Horda começou (número da horda) / terminou (sobreviveram = recompensa entregue).
signal horde_started(number: int)
signal horde_ended(number: int, survived: bool)

# Crafting e construção (GDD 8 e 9)
signal item_crafted(item_id: StringName, quality: int)
signal structure_placed(structure: Node)
signal structure_destroyed(structure: Node)
## Um jogador apertou E numa estação (fogueira, bancada). A tela de inventário abre nela.
signal station_opened(station: Node, player: Node)
## Baú (GDD 9.3): aberto por um jogador / conteúdo mudou.
signal chest_opened(chest: Node, player: Node)
signal chest_changed(chest: Node)

# Barulho (GDD 5.1): zumbis escutam isto para investigar
signal noise_emitted(position: Vector3, loudness: float, source: Node)

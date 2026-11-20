class_name Survival
extends Node
## Regeneração de vida e de stamina do personagem (nó "Survival" do Player).
## Não há mais fome nem sede (o jogo virou RPG de exploração, docs/PROXIMOS_PASSOS.md).
## - Vida: base 0. Regenera com "life_regen_add" (árvore passiva, ascendência, itens,
##   auras e buffs temporários: comida, Descansado).
## - Stamina: regeneração base do StatPool × Fraqueza (morte) × "stamina_regen".
##
## Rede: roda só na máquina do dono do personagem; a cura passa pelo servidor (Health).

## De quanto em quanto tempo aplica a cura (evita um pedido por frame na rede).
@export var tick_seconds := 1.0

var _tick := 0.0
var _player: Player
var _base_stamina_regen := 0.0


func _ready() -> void:
	_player = get_parent() as Player


func _process(delta: float) -> void:
	if _player == null:
		return
	_apply_stamina_regen()
	if _player.health.is_dead:
		return
	_tick += delta
	if _tick < tick_seconds:
		return
	var span := _tick
	_tick = 0.0
	var regen := life_regen_rate()
	if regen > 0.0 and _player.health.current < _player.health.cap():
		_player.health.heal(regen * span)


## Regeneração total de vida por segundo agora (painel de status).
func life_regen_rate() -> float:
	return maxf(_player.progression.add("life_regen_add"), 0.0)


## Renascer (os buffs de comida somem junto com os outros efeitos).
func reset() -> void:
	if _player and _player.effects:
		_player.effects.clear()


func _apply_stamina_regen() -> void:
	var stamina := _player.stamina
	if _base_stamina_regen == 0.0:
		_base_stamina_regen = stamina.regen_per_second
	stamina.regen_per_second = _base_stamina_regen * _player.death_penalty.stamina_factor() \
		* _player.progression.mult("stamina_regen")

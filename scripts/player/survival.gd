class_name Survival
extends Node
## Regeneração de vida e de stamina do personagem (nó "Survival" do Player).
## Não há mais fome nem sede (o jogo virou RPG de exploração, docs/PROXIMOS_PASSOS.md).
## - Vida: base 0. Regenera com "life_regen_add" (árvore passiva, ascendência, itens,
##   auras) e com a regeneração temporária de comida (frutas; peixes depois).
## - Stamina: regeneração base do StatPool × Fraqueza (morte) × "stamina_regen".
##
## Rede: roda só na máquina do dono do personagem; a cura passa pelo servidor (Health).

## De quanto em quanto tempo aplica a cura (evita um pedido por frame na rede).
@export var tick_seconds := 1.0

## Regenerações temporárias de comida: [vida por segundo, segundos restantes].
var _food_regen: Array = []
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
		_food_regen.clear()
		return
	_tick += delta
	if _tick < tick_seconds:
		return
	var span := _tick
	_tick = 0.0
	var regen := maxf(_player.progression.add("life_regen_add"), 0.0) + food_regen_rate()
	for entry: Array in _food_regen:
		entry[1] = float(entry[1]) - span
	_food_regen = _food_regen.filter(func(entry: Array) -> bool: return float(entry[1]) > 0.0)
	if regen > 0.0 and _player.health.current < _player.health.cap():
		_player.health.heal(regen * span)


## Comida: regenera `per_second` de vida por `seconds`. Retorna false se não adiantaria
## (vida cheia), para não desperdiçar o item.
func add_food_regen(per_second: float, seconds: float) -> bool:
	if per_second <= 0.0 or seconds <= 0.0 or _player.health.current >= _player.health.cap():
		return false
	_food_regen.append([per_second, seconds])
	return true


## Vida por segundo vinda de comida agora (somando o que estiver ativo).
func food_regen_rate() -> float:
	var total := 0.0
	for entry: Array in _food_regen:
		total += float(entry[0])
	return total


## Regeneração total de vida por segundo agora (painel de status).
func life_regen_rate() -> float:
	return maxf(_player.progression.add("life_regen_add"), 0.0) + food_regen_rate()


## Renascer: tira as regenerações de comida em andamento.
func reset() -> void:
	_food_regen.clear()


func _apply_stamina_regen() -> void:
	var stamina := _player.stamina
	if _base_stamina_regen == 0.0:
		_base_stamina_regen = stamina.regen_per_second
	stamina.regen_per_second = _base_stamina_regen * _player.death_penalty.stamina_factor() \
		* _player.progression.mult("stamina_regen")

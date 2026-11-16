class_name Survival
extends Node
## Fome e sede (GDD 7). Valores de 0 (vazio) a 100 (satisfeito).
## Caem com o tempo e mais rápido com esforço (correr). Efeitos:
## - as duas acima de well_fed_threshold: a vida regenera devagar;
## - qualquer uma abaixo de weak_threshold: stamina recupera mais devagar;
## - fome em 0 ou sede em 0: perde vida aos poucos.
## Todos os números são provisórios e vão para as opções de dificuldade depois.
##
## Rede: roda só na máquina do dono do personagem; dano e cura passam pelo
## servidor (Health), como o resto da vida.

signal changed(hunger: float, thirst: float)

@export_group("Queda por minuto (parado/andando)")
## 100 / 40 min
@export var hunger_per_minute := 2.5
## 100 / 25 min
@export var thirst_per_minute := 4.0
## Multiplicador da queda enquanto corre.
@export var sprint_multiplier := 2.5

@export_group("Efeitos")
@export var well_fed_threshold := 60.0
@export var weak_threshold := 20.0
## Vida recuperada por segundo bem alimentado.
@export var regen_per_second := 0.25
@export var starving_damage_per_second := 0.5
@export var dehydrated_damage_per_second := 1.0
## Fator da regeneração de stamina quando fraco.
@export var weak_stamina_factor := 0.5
## De quanto em quanto tempo aplica dano/cura (evita um pedido por frame na rede).
@export var tick_seconds := 2.0

var hunger := 100.0
var thirst := 100.0
## Ligado pelo Player enquanto corre.
var exerting := false

var _tick := 0.0
var _player: Player
var _base_stamina_regen := 0.0


func _ready() -> void:
	_player = get_parent() as Player


func _process(delta: float) -> void:
	if _player == null or _player.health.is_dead:
		return
	var effort := sprint_multiplier if exerting else 1.0
	var cold := Weather.hunger_factor(get_tree(), get_parent().global_position)
	hunger = maxf(hunger - hunger_per_minute / 60.0 * effort * cold * delta, 0.0)
	thirst = maxf(thirst - thirst_per_minute / 60.0 * effort * delta, 0.0)
	changed.emit(hunger, thirst)
	_apply_stamina_penalty()

	_tick += delta
	if _tick < tick_seconds:
		return
	var span := _tick
	_tick = 0.0
	var damage := 0.0
	if hunger <= 0.0:
		damage += starving_damage_per_second * span
	if thirst <= 0.0:
		damage += dehydrated_damage_per_second * span
	if damage > 0.0:
		_player.health.take_damage(damage, _player)
	elif is_well_fed() and _player.health.current < _player.health.max_health:
		_player.health.heal(regen_per_second * span)


func is_well_fed() -> bool:
	return hunger >= well_fed_threshold and thirst >= well_fed_threshold


func is_weak() -> bool:
	return hunger < weak_threshold or thirst < weak_threshold


## Comer/beber. Retorna true se ajudou em algo (para não gastar à toa).
func consume(food: float, water: float) -> bool:
	var useful := (food > 0.0 and hunger < 100.0) or (water > 0.0 and thirst < 100.0)
	if not useful:
		return false
	hunger = clampf(hunger + food, 0.0, 100.0)
	thirst = clampf(thirst + water, 0.0, 100.0)
	changed.emit(hunger, thirst)
	return true


func refill() -> void:
	hunger = 100.0
	thirst = 100.0
	changed.emit(hunger, thirst)


func _apply_stamina_penalty() -> void:
	var stamina := _player.stamina
	if _base_stamina_regen == 0.0:
		_base_stamina_regen = stamina.regen_per_second
	stamina.regen_per_second = _base_stamina_regen * (weak_stamina_factor if is_weak() else 1.0) \
		* _player.death_penalty.stamina_factor()

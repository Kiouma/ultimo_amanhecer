class_name DeathPenalty
extends Node
## Penalidades de morte (GDD 7): debuff temporário "Fraqueza" que escala com mortes
## seguidas e perda de parte do XP.
## - Ao morrer: se a Fraqueza ainda estava ativa, sobe um nível (até max_level);
##   senão, começa no nível 1. A duração recomeça: base + extra por nível.
## - Cada nível: mais lento, menos dano causado, stamina recupera mais devagar.
## - XP: perde xp_loss_fraction quando existir progressão (Fase 6, nó "Progression").
## Números provisórios; vão para as opções de dificuldade.
## Roda na máquina do dono do personagem (como Survival).

signal changed(level: int, time_left: float)

@export var base_duration := 120.0
@export var extra_duration_per_level := 60.0
@export var max_level := 5
@export var speed_penalty_per_level := 0.07
@export var damage_penalty_per_level := 0.10
@export var stamina_penalty_per_level := 0.15
## Fração do XP perdida a cada morte (aplicada quando a progressão existir).
@export var xp_loss_fraction := 0.10

var level := 0
var time_left := 0.0


func _process(delta: float) -> void:
	if level <= 0:
		return
	time_left -= delta
	if time_left <= 0.0:
		level = 0
		time_left = 0.0
	changed.emit(level, time_left)


func is_active() -> bool:
	return level > 0


## Chamado pelo Player ao morrer.
func on_died() -> void:
	level = mini(level + 1, max_level) if is_active() else 1
	time_left = base_duration + extra_duration_per_level * (level - 1)
	_lose_xp()
	changed.emit(level, time_left)


func speed_factor() -> float:
	return 1.0 - speed_penalty_per_level * level


func damage_factor() -> float:
	return 1.0 - damage_penalty_per_level * level


func stamina_factor() -> float:
	return 1.0 - stamina_penalty_per_level * level


func _lose_xp() -> void:
	# Progressão ainda não existe (Fase 6). Quando existir, terá lose_xp_fraction().
	var progression := get_parent().get_node_or_null(^"Progression")
	if progression and progression.has_method(&"lose_xp_fraction"):
		progression.lose_xp_fraction(xp_loss_fraction)

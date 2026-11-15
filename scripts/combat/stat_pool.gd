class_name StatPool
extends Node
## Recurso que se gasta e regenera: stamina, mana (GDD 5.1 e 7).
## Regenera sozinho depois de um tempo sem gastar.

signal changed(current: float, maximum: float)

@export var max_value := 100.0
@export var regen_per_second := 10.0
## Segundos sem gastar até começar a regenerar.
@export var regen_delay := 1.0

var current: float
var _since_spent := 0.0


func _ready() -> void:
	current = max_value


func _process(delta: float) -> void:
	_since_spent += delta
	if _since_spent >= regen_delay and current < max_value:
		current = minf(current + regen_per_second * delta, max_value)
		changed.emit(current, max_value)


func has(amount: float) -> bool:
	return current >= amount


## Gasta se tiver o suficiente. Retorna false (e não gasta nada) se faltar.
func spend(amount: float) -> bool:
	if amount > current:
		return false
	drain(amount)
	return true


## Gasta o que der, mesmo que não tenha tudo (ex.: correr consome por segundo).
func drain(amount: float) -> void:
	current = maxf(current - amount, 0.0)
	_since_spent = 0.0
	changed.emit(current, max_value)


func refill() -> void:
	current = max_value
	changed.emit(current, max_value)

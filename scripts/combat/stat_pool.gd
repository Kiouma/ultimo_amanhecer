class_name StatPool
extends Node
## Recurso que se gasta e regenera: stamina, mana (GDD 5.1 e 7).
## Regenera sozinho depois de um tempo sem gastar. Fora de ação (sem gastar, conjurar
## nem atacar) por OUT_OF_ACTION segundos, regenera out_of_action_factor vezes mais rápido.

signal changed(current: float, maximum: float)

@export var max_value := 100.0
@export var regen_per_second := 10.0
## Segundos sem gastar até começar a regenerar.
@export var regen_delay := 1.0
## Multiplicador da regeneração depois de OUT_OF_ACTION segundos fora de ação.
@export var out_of_action_factor := 1.0

## Canalizando: regenera o tempo todo (sem esperar regen_delay), mas a CHANNEL_REGEN da velocidade.
const CHANNEL_REGEN := 0.25
const OUT_OF_ACTION := 3.0

var current: float
## Fração reservada por auras (0 a 1): o recurso não passa de cap().
var reserved := 0.0
var channeling := false
var _since_spent := 0.0
var _since_action := 0.0


func _ready() -> void:
	current = max_value


func _process(delta: float) -> void:
	_since_spent += delta
	_since_action += delta
	if channeling:
		_since_action = 0.0
		if current < cap():
			current = minf(current + regen_per_second * CHANNEL_REGEN * delta, cap())
			changed.emit(current, max_value)
	elif _since_spent >= regen_delay and current < cap():
		current = minf(current + regen_rate() * delta, cap())
		changed.emit(current, max_value)


## Regeneração por segundo agora (com o bônus fora de ação).
func regen_rate() -> float:
	return regen_per_second * (out_of_action_factor if out_of_action() else 1.0)


func out_of_action() -> bool:
	return _since_action >= OUT_OF_ACTION


## Atacou (ou fez algo de combate sem gastar deste recurso): zera o tempo fora de ação.
func mark_action() -> void:
	_since_action = 0.0


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
	_since_action = 0.0
	changed.emit(current, max_value)


## Devolve (ex.: canalização cancelada devolve o custo já pago).
func restore(amount: float) -> void:
	current = minf(current + amount, cap())
	changed.emit(current, max_value)


## Máximo utilizável (sem a parte reservada por auras).
func cap() -> float:
	return max_value * (1.0 - reserved)


func set_reserved(fraction: float) -> void:
	reserved = clampf(fraction, 0.0, 1.0)
	current = minf(current, cap())
	changed.emit(current, max_value)


func refill() -> void:
	current = cap()
	changed.emit(current, max_value)

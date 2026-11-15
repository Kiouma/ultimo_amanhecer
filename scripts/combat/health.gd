class_name Health
extends Node
## Componente de vida reutilizável (jogador, zumbis, construções).
## Quem causa dano chama Health.find_in(alvo).take_damage(...), sem conhecer o tipo do alvo.

signal changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died(source: Node)

@export var max_health := 100.0

var current: float
var is_dead := false


func _ready() -> void:
	current = max_health


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, source)
	changed.emit(current, max_health)
	if current <= 0.0:
		is_dead = true
		died.emit(source)


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	changed.emit(current, max_health)


func reset(new_max := -1.0) -> void:
	if new_max > 0.0:
		max_health = new_max
	current = max_health
	is_dead = false
	changed.emit(current, max_health)


## Procura o componente Health em um nó (filho direto chamado "Health").
static func find_in(node: Node) -> Health:
	if node == null:
		return null
	return node.get_node_or_null(^"Health") as Health

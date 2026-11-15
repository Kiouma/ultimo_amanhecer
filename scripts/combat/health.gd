class_name Health
extends Node
## Componente de vida reutilizável (jogador, zumbis, construções).
## Quem causa dano chama Health.find_in(alvo).take_damage(...), sem conhecer o tipo do alvo.
##
## Rede: a vida só muda no servidor. Num cliente, take_damage vira um pedido ao
## servidor; o servidor aplica e manda o novo estado para todos. Os sinais
## (damaged, died, revived, changed) disparam em todos os jogadores.

signal changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died(source: Node)
signal revived

## Teto de dano por pedido de cliente (proteção simples contra valores absurdos).
const MAX_DAMAGE_PER_HIT := 500.0

@export var max_health := 100.0

var current: float
var is_dead := false


func _ready() -> void:
	current = max_health


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	if multiplayer.is_server():
		_apply(maxf(current - amount, 0.0), amount, source)
	elif Network.is_online():
		_request_damage.rpc_id(1, amount, source.get_path() if source else NodePath())


func heal(amount: float) -> void:
	if is_dead or amount <= 0.0 or not multiplayer.is_server():
		return
	_apply(minf(current + amount, max_health), 0.0, null)


## Volta à vida cheia. Num cliente, pede ao servidor (ex.: ao renascer).
func reset(new_max := -1.0) -> void:
	if new_max > 0.0:
		max_health = new_max
	if multiplayer.is_server():
		_apply(max_health, 0.0, null, true)
	elif Network.is_online():
		_request_reset.rpc_id(1)


## Define a vida máxima e enche, só nesta máquina. Para configurar ao nascer,
## quando todos os jogadores calculam o mesmo valor (ex.: vida do tipo de zumbi).
func configure(new_max: float) -> void:
	max_health = new_max
	current = new_max
	is_dead = false
	changed.emit(current, max_health)


## Procura o componente Health em um nó (filho direto chamado "Health").
static func find_in(node: Node) -> Health:
	if node == null:
		return null
	return node.get_node_or_null(^"Health") as Health


# --- Interno ---------------------------------------------------------------------

func _apply(new_current: float, amount: float, source: Node, revive := false) -> void:
	var source_path := source.get_path() if source else NodePath()
	_set_state(new_current, revive, amount, source)
	if Network.is_online():
		_sync_state.rpc(current, is_dead, max_health, amount, source_path)


func _set_state(new_current: float, revive: bool, amount: float, source: Node) -> void:
	var was_dead := is_dead
	current = new_current
	if revive:
		is_dead = false
	elif current <= 0.0:
		is_dead = true
	if amount > 0.0:
		damaged.emit(amount, source)
	changed.emit(current, max_health)
	if is_dead and not was_dead:
		died.emit(source)
	elif was_dead and not is_dead:
		revived.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_damage(amount: float, source_path: NodePath) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	var source := get_node_or_null(source_path)
	# O atacante tem que ser o personagem de quem mandou o pedido.
	if source == null or source.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	_apply(maxf(current - clampf(amount, 0.0, MAX_DAMAGE_PER_HIT), 0.0), amount, source)


@rpc("any_peer", "call_remote", "reliable")
func _request_reset() -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_apply(max_health, 0.0, null, true)


@rpc("any_peer", "call_remote", "reliable")
func _sync_state(new_current: float, dead: bool, new_max: float, amount: float, source_path: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	max_health = new_max
	var source := get_node_or_null(source_path) if not source_path.is_empty() else null
	_set_state(new_current, is_dead and not dead, amount, source)
	is_dead = dead

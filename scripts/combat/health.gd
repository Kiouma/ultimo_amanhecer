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
## Teto de cura por pedido de cliente.
const MAX_HEAL_PER_USE := 100.0

@export var max_health := 100.0
## Dano vindo de nós deste grupo é ignorado (ex.: construções ignoram "player").
@export var ignore_group := &""

var current: float
## Multiplicador do dano recebido (Resistência). O dono pede; o servidor guarda.
var damage_taken_multiplier := 1.0
## Multiplicador do dano mágico recebido (resistência a magia dos itens). Soma com o de cima.
var spell_taken_multiplier := 1.0
## Não recebe dano (jogador no modo criativo). O dono pede; o servidor guarda.
var invulnerable := false
var is_dead := false


func _ready() -> void:
	current = max_health


## magic: dano mágico/elemental (ácido, feitiços): a resistência a magia também reduz.
func take_damage(amount: float, source: Node = null, magic := false) -> void:
	if is_dead or invulnerable or amount <= 0.0 or _ignores(source):
		return
	if multiplayer.is_server():
		amount *= _taken_factor(source, magic)
		_apply(maxf(current - amount, 0.0), amount, source)
	elif Network.is_online():
		_request_damage.rpc_id(1, amount, source.get_path() if source else NodePath())


## Cura. Num cliente, pede ao servidor (só o dono do personagem pode pedir).
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	if multiplayer.is_server():
		_apply(minf(current + amount, max_health), 0.0, null)
	elif Network.is_online():
		_request_heal.rpc_id(1, amount)


## Cura vinda de outro jogador (feitiço Remendar). O servidor confere a distância.
func heal_by(amount: float, healer: Node3D) -> void:
	if is_dead or amount <= 0.0:
		return
	if multiplayer.is_server():
		heal(amount)
	elif Network.is_online():
		_request_heal_by.rpc_id(1, amount, healer.get_path())


@rpc("any_peer", "call_remote", "reliable")
func _request_heal_by(amount: float, healer_path: NodePath) -> void:
	var healer := get_node_or_null(healer_path) as Node3D
	var me := get_parent() as Node3D
	if not multiplayer.is_server() or healer == null or me == null \
			or healer.get_multiplayer_authority() != multiplayer.get_remote_sender_id() \
			or healer.global_position.distance_to(me.global_position) > 10.0:
		return
	heal(clampf(amount, 0.0, MAX_HEAL_PER_USE))


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

## Fome/sede (fonte = o próprio dono) não são reduzidas pela Resistência.
func _taken_factor(source: Node, magic := false) -> float:
	if source == get_parent():
		return 1.0
	return damage_taken_multiplier * (spell_taken_multiplier if magic else 1.0)


## Chamado pelo dono (Progression). Num cliente, avisa o servidor.
func set_damage_taken_multiplier(value: float, spell := 1.0) -> void:
	damage_taken_multiplier = clampf(value, 0.25, 1.0)
	spell_taken_multiplier = clampf(spell, 0.25, 1.0)
	if not multiplayer.is_server() and Network.is_online():
		_request_taken_multiplier.rpc_id(1, damage_taken_multiplier, spell_taken_multiplier)


@rpc("any_peer", "call_remote", "reliable")
func _request_taken_multiplier(value: float, spell: float) -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		damage_taken_multiplier = clampf(value, 0.25, 1.0)
		spell_taken_multiplier = clampf(spell, 0.25, 1.0)


func set_invulnerable(on: bool) -> void:
	invulnerable = on
	if Network.is_online() and not multiplayer.is_server():
		_request_invulnerable.rpc_id(1, on)


@rpc("any_peer", "call_remote", "reliable")
func _request_invulnerable(on: bool) -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		invulnerable = on


func _ignores(source: Node) -> bool:
	return ignore_group != &"" and source != null and source.is_in_group(ignore_group)


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
	if _ignores(source):
		return
	amount = clampf(amount, 0.0, MAX_DAMAGE_PER_HIT) * _taken_factor(source)
	_apply(maxf(current - amount, 0.0), amount, source)


@rpc("any_peer", "call_remote", "reliable")
func _request_heal(amount: float) -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		heal(clampf(amount, 0.0, MAX_HEAL_PER_USE))


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

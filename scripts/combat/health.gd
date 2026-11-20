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
## Escudo de energia mudou (todas as máquinas).
signal shield_changed(current: float, maximum: float)

## Escudo de energia: absorve o dano antes da vida. Recarrega SHIELD_RECHARGE do máximo
## por segundo depois de SHIELD_DELAY segundos sem levar dano. O dono pede o máximo
## (set_owner_vitals); o servidor guarda, gasta, recarrega e espalha.
const SHIELD_DELAY := 3.0
const SHIELD_RECHARGE := 0.25
const MAX_SHIELD := 5000.0
## Fração máxima de vida reservável (auras). Com tudo reservado, sobra 1 de vida.
const MAX_RESERVED := 1.0

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
## Fração da vida reservada por auras de vida (0 a 1): a vida não passa de cap() (mínimo 1).
## O dono pede (set_owner_vitals); o servidor guarda; o dono guarda uma cópia para o HUD.
var reserved := 0.0
var shield := 0.0
var max_shield := 0.0
var _since_hit := 99.0
var _shield_sync := 0.0


func _ready() -> void:
	set_process(false)
	current = max_health


## magic: dano mágico/elemental (ácido, feitiços): a resistência a magia também reduz.
func take_damage(amount: float, source: Node = null, magic := false) -> void:
	if is_dead or invulnerable or amount <= 0.0 or _ignores(source):
		return
	if multiplayer.is_server():
		_hit(amount * _taken_factor(source, magic), source)
	elif Network.is_online():
		_request_damage.rpc_id(1, amount, source.get_path() if source else NodePath())


## Servidor: o escudo de energia absorve primeiro; o resto vai para a vida. O sinal
## "damaged" leva o dano todo (reações, XP de Resistência).
func _hit(amount: float, source: Node) -> void:
	_since_hit = 0.0
	var absorbed := minf(shield, amount)
	if absorbed > 0.0:
		_set_shield(shield - absorbed)
	_apply(maxf(current - (amount - absorbed), 0.0), amount, source)


func _process(delta: float) -> void:
	# Só roda no servidor e com escudo (set_process liga em _set_vitals).
	_since_hit += delta
	if _since_hit < SHIELD_DELAY or shield >= max_shield or is_dead:
		return
	shield = minf(shield + max_shield * SHIELD_RECHARGE * delta, max_shield)
	_shield_sync -= delta
	if _shield_sync <= 0.0 or shield >= max_shield:
		_shield_sync = 0.25
		_set_shield(shield)


func _set_shield(value: float) -> void:
	shield = clampf(value, 0.0, max_shield)
	shield_changed.emit(shield, max_shield)
	if Network.is_online() and multiplayer.is_server():
		_sync_shield.rpc(shield, max_shield)


@rpc("authority", "call_remote", "reliable")
func _sync_shield(value: float, maximum: float) -> void:
	max_shield = maximum
	shield = value
	shield_changed.emit(shield, max_shield)


## Cura. Num cliente, pede ao servidor (só o dono do personagem pode pedir).
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	if multiplayer.is_server():
		_apply(minf(current + amount, cap()), 0.0, null)
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
		_apply(cap(), 0.0, null, true)
	elif Network.is_online():
		_request_reset.rpc_id(1)


## Define a vida máxima e enche, só nesta máquina. Para configurar ao nascer,
## quando todos os jogadores calculam o mesmo valor (ex.: vida do tipo de zumbi).
func configure(new_max: float) -> void:
	max_health = new_max
	current = new_max
	is_dead = false
	changed.emit(current, max_health)


## Vida máxima utilizável (sem a parte reservada por auras de vida).
func cap() -> float:
	return maxf(max_health * (1.0 - reserved), 1.0)


## Dono do personagem: vida máxima (árvore passiva, itens) e fração reservada por
## auras de vida. Num cliente, pede ao servidor.
## Dono do personagem: vida máxima (árvore, atributos, itens), fração reservada por
## auras de vida e escudo de energia máximo. Num cliente, pede ao servidor.
func set_owner_vitals(new_max: float, new_reserved: float, new_shield := 0.0) -> void:
	new_max = clampf(new_max, 10.0, 5000.0)
	new_reserved = clampf(new_reserved, 0.0, MAX_RESERVED)
	new_shield = clampf(new_shield, 0.0, MAX_SHIELD)
	if multiplayer.is_server():
		_set_vitals(new_max, new_reserved, new_shield)
	else:
		reserved = new_reserved
		if Network.is_online():
			_request_vitals.rpc_id(1, new_max, new_reserved, new_shield)


func _set_vitals(new_max: float, new_reserved: float, new_shield := 0.0) -> void:
	new_max = clampf(new_max, 10.0, 5000.0)
	new_reserved = clampf(new_reserved, 0.0, MAX_RESERVED)
	new_shield = clampf(new_shield, 0.0, MAX_SHIELD)
	if not is_equal_approx(new_shield, max_shield):
		# O que o máximo aumentou entra na hora (personagem novo nasce com o escudo cheio).
		var gained := maxf(new_shield - max_shield, 0.0)
		max_shield = new_shield
		set_process(max_shield > 0.0)
		_set_shield(minf(shield + gained, max_shield))
	if is_equal_approx(new_max, max_health) and is_equal_approx(new_reserved, reserved):
		return
	max_health = new_max
	reserved = new_reserved
	_apply(minf(current, cap()), 0.0, null)


## Procura o componente Health em um nó (filho direto chamado "Health").
static func find_in(node: Node) -> Health:
	if node == null:
		return null
	return node.get_node_or_null(^"Health") as Health


# --- Interno ---------------------------------------------------------------------

## Dano causado pelo próprio dono não é reduzido pela Resistência.
func _taken_factor(source: Node, magic := false) -> float:
	if source == get_parent():
		return 1.0
	return damage_taken_multiplier * (spell_taken_multiplier if magic else 1.0)


## Chamado pelo dono (Progression). Num cliente, avisa o servidor.
func set_damage_taken_multiplier(value: float, spell := 1.0) -> void:
	damage_taken_multiplier = clampf(value, 0.25, 3.0)
	spell_taken_multiplier = clampf(spell, 0.25, 1.0)
	if not multiplayer.is_server() and Network.is_online():
		_request_taken_multiplier.rpc_id(1, damage_taken_multiplier, spell_taken_multiplier)


@rpc("any_peer", "call_remote", "reliable")
func _request_taken_multiplier(value: float, spell: float) -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		damage_taken_multiplier = clampf(value, 0.25, 3.0)
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
	if revive and max_shield > 0.0:
		_set_shield(max_shield)  # renasce com o escudo cheio


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
	_hit(clampf(amount, 0.0, MAX_DAMAGE_PER_HIT) * _taken_factor(source), source)


@rpc("any_peer", "call_remote", "reliable")
func _request_heal(amount: float) -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		heal(clampf(amount, 0.0, MAX_HEAL_PER_USE))


@rpc("any_peer", "call_remote", "reliable")
func _request_reset() -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_apply(cap(), 0.0, null, true)


@rpc("any_peer", "call_remote", "reliable")
func _request_vitals(new_max: float, new_reserved: float, new_shield: float) -> void:
	if multiplayer.is_server() and get_multiplayer_authority() == multiplayer.get_remote_sender_id():
		_set_vitals(new_max, new_reserved, new_shield)


@rpc("any_peer", "call_remote", "reliable")
func _sync_state(new_current: float, dead: bool, new_max: float, amount: float, source_path: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	max_health = new_max
	var source := get_node_or_null(source_path) if not source_path.is_empty() else null
	_set_state(new_current, is_dead and not dead, amount, source)
	is_dead = dead

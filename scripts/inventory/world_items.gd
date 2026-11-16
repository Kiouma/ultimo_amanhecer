extends Node
## Itens soltos no mundo (autoload "WorldItems").
## Só o servidor cria e remove itens do chão; o MultiplayerSpawner do nível replica.
## Clientes pedem: soltar (já tiraram do próprio inventário) e pegar (o servidor
## confere distância e se o item ainda existe, então concede com Inventory.grant).
##
## Coleta automática (por proximidade): quem soltou um item não o pega de volta
## sozinho por DROP_COOLDOWN segundos, para outro jogador ter tempo de pegar.
## Pegar de propósito (E) não tem essa espera.

const ITEM_SCRIPT := preload("res://scripts/inventory/world_item.gd")
## Distância máxima para pegar/soltar (com folga para o lag).
const MAX_REACH := 4.0
## Segundos em que quem soltou o item não o pega automaticamente.
const DROP_COOLDOWN := 5.0

var _root: Node3D
var _spawner: MultiplayerSpawner


## Chamado pelo nível ao carregar (em todas as máquinas).
func register(root: Node3D, spawner: MultiplayerSpawner) -> void:
	_root = root
	_spawner = spawner
	_spawner.spawn_function = _create


## Itens no chão agora (vazio se não há nível).
func all_items() -> Array[Node]:
	return _root.get_children() if _root else [] as Array[Node]


## by_peer: id do jogador que soltou (0 = o mundo: saque, flecha recuperada...).
func spawn(id: String, count: int, position: Vector3, by_peer := 0) -> void:
	if not multiplayer.is_server() or _spawner == null or count <= 0:
		return
	_spawner.spawn({"id": id, "count": count, "pos": _snap_to_ground(position), "by": by_peer})


## Solta itens no chão (quem chama já tirou do inventário).
## by: jogador que soltou (ganha a espera da coleta automática) ou null.
func drop(id: String, count: int, position: Vector3, by: Node3D) -> void:
	if multiplayer.is_server():
		spawn(id, count, position, by.get_multiplayer_authority() if by else 0)
	elif Network.is_online():
		_request_drop.rpc_id(1, id, count, position, by != null)


## auto = coleta por proximidade (respeita a espera de quem soltou).
func request_pickup(item: Node, player: Node3D, auto := false) -> void:
	if multiplayer.is_server():
		_do_pickup(item, player, auto)
	elif Network.is_online():
		_request_pickup.rpc_id(1, item.name, auto)


## O jogador (peer) pode pegar este item automaticamente agora?
func can_auto_pickup(item: Node, peer_id: int) -> bool:
	return not (item.dropped_by == peer_id and item.age() < DROP_COOLDOWN)


# --- Servidor ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_drop(id: String, count: int, position: Vector3, by_player: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var player := _player_of(sender)
	if player == null or GameData.get_item(id).is_empty():
		return
	if player.global_position.distance_to(position) > MAX_REACH:
		position = player.global_position
	spawn(id, clampi(count, 1, 10000), position, sender if by_player else 0)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(item_name: String, auto: bool) -> void:
	if _root == null:
		return
	_do_pickup(_root.get_node_or_null(item_name), _player_of(multiplayer.get_remote_sender_id()), auto)


func _do_pickup(item: Node, player: Node3D, auto := false) -> void:
	if item == null or player == null or item.is_queued_for_deletion():
		return
	if player.global_position.distance_to(item.global_position) > MAX_REACH:
		return
	if auto and not can_auto_pickup(item, player.get_multiplayer_authority()):
		return
	var inventory := player.get_node_or_null(^"Inventory") as Inventory
	if inventory == null:
		return
	item.queue_free()
	inventory.grant(item.item_id, item.count)


func _player_of(peer_id: int) -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null


func _snap_to_ground(position: Vector3) -> Vector3:
	if _root == null:
		return position
	var from := position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20.0, 1 | 8)
	var hit := _root.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else position


# --- Todas as máquinas -------------------------------------------------------------------

func _create(data: Dictionary) -> Node:
	var item: StaticBody3D = ITEM_SCRIPT.new()
	item.item_id = data.id
	item.count = data.count
	item.position = data.pos
	item.dropped_by = int(data.get("by", 0))
	return item

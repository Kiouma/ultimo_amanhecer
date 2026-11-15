extends Node
## Itens soltos no mundo (autoload "WorldItems").
## Só o servidor cria e remove itens do chão; o MultiplayerSpawner do nível replica.
## Clientes pedem: soltar (já tiraram do próprio inventário) e pegar (o servidor
## confere distância e se o item ainda existe, então concede com Inventory.grant).

const ITEM_SCRIPT := preload("res://scripts/inventory/world_item.gd")
## Distância máxima para pegar/soltar (com folga para o lag).
const MAX_REACH := 4.0

var _root: Node3D
var _spawner: MultiplayerSpawner


## Chamado pelo nível ao carregar (em todas as máquinas).
func register(root: Node3D, spawner: MultiplayerSpawner) -> void:
	_root = root
	_spawner = spawner
	_spawner.spawn_function = _create


func spawn(id: String, count: int, position: Vector3) -> void:
	if not multiplayer.is_server() or _spawner == null or count <= 0:
		return
	_spawner.spawn({"id": id, "count": count, "pos": _snap_to_ground(position)})


## Solta itens no chão (quem chama já tirou do inventário).
func drop(id: String, count: int, position: Vector3, by: Node3D) -> void:
	if multiplayer.is_server():
		spawn(id, count, position)
	elif Network.is_online():
		_request_drop.rpc_id(1, id, count, position)


func request_pickup(item: Node, player: Node3D) -> void:
	if multiplayer.is_server():
		_do_pickup(item, player)
	elif Network.is_online():
		_request_pickup.rpc_id(1, item.name)


# --- Servidor ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _request_drop(id: String, count: int, position: Vector3) -> void:
	var player := _player_of(multiplayer.get_remote_sender_id())
	if player == null or GameData.get_item(id).is_empty():
		return
	if player.global_position.distance_to(position) > MAX_REACH:
		position = player.global_position
	spawn(id, clampi(count, 1, 10000), position)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(item_name: String) -> void:
	if _root == null:
		return
	_do_pickup(_root.get_node_or_null(item_name), _player_of(multiplayer.get_remote_sender_id()))


func _do_pickup(item: Node, player: Node3D) -> void:
	if item == null or player == null or item.is_queued_for_deletion():
		return
	if player.global_position.distance_to(item.global_position) > MAX_REACH:
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
	return item

extends Node
## Estruturas colocadas pelos jogadores (autoload "Structures").
## Por enquanto: estações de fabricação (fogueira, bancada). A construção da Fase 4
## (paredes, pisos, portas) vai usar o mesmo caminho.
## Rede: só o servidor cria/remove; o MultiplayerSpawner do nível replica (inclusive
## para quem entra depois). Clientes pedem com place().

const STATION_SCRIPT := preload("res://scripts/crafting/station.gd")
## Distância máxima entre o jogador e o ponto onde a estrutura vai.
const MAX_PLACE_DISTANCE := 5.0
## Distância mínima entre duas estações.
const MIN_SPACING := 1.4

var _root: Node3D
var _spawner: MultiplayerSpawner


## Chamado pelo nível ao carregar (em todas as máquinas).
func register(root: Node3D, spawner: MultiplayerSpawner) -> void:
	_root = root
	_spawner = spawner
	_spawner.spawn_function = _create


## Dá para colocar aqui? (checagem local, repetida no servidor)
func can_place_at(position: Vector3) -> bool:
	if _root == null:
		return false
	for s in _root.get_children():
		if s.global_position.distance_to(position) < MIN_SPACING:
			return false
	return true


## Quem chama já tirou o item do inventário.
func place(item_id: String, position: Vector3, rotation_y: float) -> void:
	if multiplayer.is_server():
		_spawn(item_id, position, rotation_y)
	elif Network.is_online():
		_request_place.rpc_id(1, item_id, position, rotation_y)


## Estações de um tipo ("campfire") a até `radius` metros de `position`.
func stations_near(station: String, position: Vector3, radius: float) -> Array[Node]:
	var out: Array[Node] = []
	if _root == null:
		return out
	for s in _root.get_children():
		if s.get(&"station") == station and s.global_position.distance_to(position) <= radius:
			out.append(s)
	return out


func _spawn(item_id: String, position: Vector3, rotation_y: float) -> void:
	if _spawner == null or not can_place_at(position):
		return
	_spawner.spawn({"id": item_id, "pos": position, "rot": rotation_y})


@rpc("any_peer", "call_remote", "reliable")
func _request_place(item_id: String, position: Vector3, rotation_y: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var player: Node3D = null
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			player = p
	if player == null or GameData.get_item(item_id).get("type", "") != "station":
		return
	# Recusado (longe demais ou lugar ocupado): devolve o item, que o cliente já tirou.
	if player.global_position.distance_to(position) > MAX_PLACE_DISTANCE or not can_place_at(position):
		(player.get_node(^"Inventory") as Inventory).grant(item_id, 1)
		_notify_refused.rpc_id(sender)
		return
	_spawn(item_id, position, rotation_y)


@rpc("authority", "call_remote", "reliable")
func _notify_refused() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			p.notify("Não deu para colocar aí (item devolvido)")


func _create(data: Dictionary) -> Node:
	var node: StaticBody3D = STATION_SCRIPT.new()
	node.item_id = data.id
	node.position = data.pos
	node.rotation.y = data.rot
	return node

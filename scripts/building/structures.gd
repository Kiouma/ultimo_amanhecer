extends Node
## Estruturas colocadas pelos jogadores (autoload "Structures"):
## - estações de fabricação (fogueira, bancada), colocadas pelo item;
## - peças de construção (GDD 9.1, ver BuildPiece), pagas com material no modo construção (B).
## Rede: só o servidor cria/remove; o MultiplayerSpawner do nível replica (inclusive
## para quem entra depois). Clientes pedem; o servidor confere de novo e, se recusar,
## devolve o item/material que o cliente já tinha tirado.

## Servidor: algo foi construído ou removido (a arena refaz a malha de navegação).
signal layout_changed

const STATION_SCRIPT := preload("res://scripts/crafting/station.gd")
const PIECE_SCRIPT := preload("res://scripts/building/build_piece.gd")
const TRAP_SCRIPT := preload("res://scripts/building/trap.gd")
## Tipos de item colocados no chão pelo item (estação, armadilha).
const PLACEABLE_TYPES := ["station", "trap"]
## Distância máxima entre o jogador e o ponto onde a estação vai.
const MAX_PLACE_DISTANCE := 5.0
## Distância máxima entre o jogador e o centro da peça construída/desmontada.
const MAX_BUILD_DISTANCE := 8.0
## Distância mínima entre duas estações.
const MIN_SPACING := 1.4
## Desmontar devolve esta fração do custo (vezes a vida que sobra).
const DEMOLISH_REFUND := 0.5
## Cada martelada recupera até esta fração da vida máxima.
const REPAIR_STEP := 0.25
## Consertar 100% da vida custa esta fração do custo da peça.
const REPAIR_COST := 0.5
## Ordem dos materiais (melhorar = ir para o próximo).
const TIERS := ["wood", "stone"]

var _root: Node3D
var _spawner: MultiplayerSpawner
## Encaixe ("c:1:2:0"...) → peça. Mantido em todas as máquinas.
var _slots: Dictionary = {}


## Chamado pelo nível ao carregar (em todas as máquinas).
func register(root: Node3D, spawner: MultiplayerSpawner) -> void:
	_root = root
	_spawner = spawner
	_spawner.spawn_function = _create
	if multiplayer.is_server() and not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)


# --- Estações ------------------------------------------------------------------------

## Dá para colocar uma estação aqui? (checagem local, repetida no servidor)
func can_place_at(position: Vector3) -> bool:
	if _root == null:
		return false
	for s in _root.get_children():
		if (s is CraftingStation or s is Trap) and s.global_position.distance_to(position) < MIN_SPACING:
			return false
	return true


## Quem chama já tirou o item do inventário. durability: a do item (-1 = cheia).
func place(item_id: String, position: Vector3, rotation_y: float, durability := -1.0) -> void:
	if multiplayer.is_server():
		_spawn(item_id, position, rotation_y, durability)
	elif Network.is_online():
		_request_place.rpc_id(1, item_id, position, rotation_y, durability)


## Estações de um tipo ("campfire") a até `radius` metros de `position`.
func stations_near(station: String, position: Vector3, radius: float) -> Array[Node]:
	var out: Array[Node] = []
	if _root == null:
		return out
	for s in _root.get_children():
		if s.get(&"station") == station and s.global_position.distance_to(position) <= radius:
			out.append(s)
	return out


func _spawn(item_id: String, position: Vector3, rotation_y: float, durability := -1.0) -> void:
	if _spawner == null or not can_place_at(position):
		return
	_spawner.spawn({"kind": "station", "id": item_id, "pos": position, "rot": rotation_y, "dur": durability})
	layout_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_place(item_id: String, position: Vector3, rotation_y: float, durability: float) -> void:
	var player := _sender_player()
	if player == null or not GameData.get_item(item_id).get("type", "") in PLACEABLE_TYPES:
		return
	# Recusado (longe demais ou lugar ocupado): devolve o item, que o cliente já tirou.
	if player.global_position.distance_to(position) > MAX_PLACE_DISTANCE or not can_place_at(position):
		var extra := {"dur": durability} if durability >= 0.0 else {}
		(player.get_node(^"Inventory") as Inventory).grant(item_id, 1, extra)
		_notify.rpc_id(multiplayer.get_remote_sender_id(), "Não deu para colocar aí (item devolvido)")
		return
	_spawn(item_id, position, rotation_y, durability)


# --- Peças de construção --------------------------------------------------------------

func piece_at(key: String) -> BuildPiece:
	var p: BuildPiece = _slots.get(key)
	return p if is_instance_valid(p) else null


func pieces() -> Array[BuildPiece]:
	var out: Array[BuildPiece] = []
	for p in _slots.values():
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			out.append(p)
	return out


func register_piece(piece: BuildPiece) -> void:
	_slots[piece.slot_key] = piece
	_support_dirty = true


func unregister_piece(piece: BuildPiece) -> void:
	if _slots.get(piece.slot_key) == piece:
		_slots.erase(piece.slot_key)
		_support_dirty = true


## Custo da peça nesse material ({id: quantidade}).
func cost(piece_id: String, tier: String) -> Dictionary:
	return GameData.get_entry("buildings", piece_id).get("tiers", {}).get(tier, {}).get("cost", {})


## Por que não dá para construir ("" = dá). Igual no cliente (prévia) e no servidor.
## Não confere material (isso é do dono do inventário).
func check_build(piece_id: String, key: String, rot: int, builder_pos: Vector3) -> String:
	var data := GameData.get_entry("buildings", piece_id)
	if data.is_empty() or _root == null:
		return "Peça desconhecida"
	var p := key.split(":")
	if p.size() != 4:
		return "Encaixe inválido"
	var kind := p[0]
	var i := int(p[1])
	var j := int(p[2])
	var n := int(p[3])
	var slot := str(data.get("slot", "edge"))
	var expected := {"center": ["c"], "ramp": ["r"], "edge": ["x", "z"]}
	if not kind in expected.get(slot, []):
		return "Encaixe inválido"
	if kind == "x" and rot % 2 != 1 or kind == "z" and rot % 2 != 0:
		return "Encaixe inválido"
	if n < int(data.get("min_level", 0)) or n > int(data.get("max_level", BuildPiece.MAX_LEVEL)):
		return "Fundação só no chão" if piece_id == "foundation" else "Altura inválida"
	if piece_at(key):
		return "Já tem uma peça aí"
	# Escada ocupa o vão até o andar de cima: não convive com piso logo acima.
	if kind == "c" and piece_at("r:%d:%d:%d" % [i, j, n - 1]) \
			or kind == "r" and piece_at("c:%d:%d:%d" % [i, j, n + 1]):
		return "A escada precisa desse espaço"
	if not _is_supported(kind, i, j, n):
		return "Precisa de apoio (parede, piso ou fundação)"
	var xform := BuildPiece.slot_transform(key, rot)
	if builder_pos.distance_to(xform.origin + Vector3.UP * 1.0) > MAX_BUILD_DISTANCE:
		return "Longe demais"
	if _is_obstructed(piece_id, xform):
		return "Tem algo no caminho"
	return ""


## Apoio da peça nova, com a construção como está agora.
func _is_supported(kind: String, i: int, j: int, n: int) -> bool:
	return _support_dist(kind, i, j, n, support_map()) >= 0


# --- Integridade estrutural (GDD 9.1) ---------------------------------------------------
# Toda peça precisa de um caminho de apoio até o chão:
# - no andar 0 (fundação, parede, porta, escada) está apoiada;
# - parede/porta acima: sobre outra parede/porta, ou sobre um piso de uma célula ao lado;
# - piso/teto: sobre uma parede/porta numa das 4 bordas (balanço 0), ou preso a um piso
#   vizinho do mesmo andar (balanço do vizinho + 1, no máximo MAX_OVERHANG);
# - escada acima do chão: sobre o piso da própria célula.
# Quando uma peça some, o que ficou sem caminho desaba (em cadeia).

## Quantas células um piso pode avançar sem parede embaixo.
const MAX_OVERHANG := 2
## Fração do custo que vira destroços no chão quando uma peça desaba.
const COLLAPSE_SALVAGE := 0.25

var _support_cache: Dictionary = {}
var _support_dirty := true


## Encaixe → balanço (0 = apoiada direto). Peças fora do mapa não têm apoio.
func support_map() -> Dictionary:
	if not _support_dirty:
		return _support_cache
	var dist := {}
	var keys: Array = []
	for key: String in _slots:
		if piece_at(key):
			keys.append(key)
	var changed := true
	while changed:
		changed = false
		for key: String in keys:
			var p := key.split(":")
			var d := _support_dist(p[0], int(p[1]), int(p[2]), int(p[3]), dist)
			if d >= 0 and (not dist.has(key) or d < int(dist[key])):
				dist[key] = d
				changed = true
	_support_cache = dist
	_support_dirty = false
	return dist


## Balanço de uma peça nesse encaixe, olhando só peças já apoiadas em `dist` (-1 = sem apoio).
func _support_dist(kind: String, i: int, j: int, n: int, dist: Dictionary) -> int:
	if n == 0:
		return 0
	match kind:
		"c":
			for k in ["x:%d:%d" % [i, j], "x:%d:%d" % [i + 1, j], "z:%d:%d" % [i, j], "z:%d:%d" % [i, j + 1]]:
				if dist.has("%s:%d" % [k, n - 1]):
					return 0
			var best := -1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var neighbor := "c:%d:%d:%d" % [i + d.x, j + d.y, n]
				if dist.has(neighbor):
					var value := int(dist[neighbor]) + 1
					if value <= MAX_OVERHANG and (best < 0 or value < best):
						best = value
			return best
		"r":
			return int(dist.get("c:%d:%d:%d" % [i, j, n], -1))
		_:
			if dist.has("%s:%d:%d:%d" % [kind, i, j, n - 1]):
				return 0
			var other := Vector2i(i - 1, j) if kind == "x" else Vector2i(i, j - 1)
			var a := int(dist.get("c:%d:%d:%d" % [i, j, n], -1))
			var b := int(dist.get("c:%d:%d:%d" % [other.x, other.y, n], -1))
			if a < 0:
				return b
			return a if b < 0 else mini(a, b)


## Servidor: derruba tudo que ficou sem apoio. Deixa destroços com parte do material.
func _collapse_unsupported() -> void:
	var dist := support_map()
	var fallen := 0
	for piece in pieces():
		if dist.has(piece.slot_key):
			continue
		var price := cost(piece.piece_id, piece.tier)
		for id: String in price:
			var amount := floori(float(price[id]) * COLLAPSE_SALVAGE)
			if amount > 0:
				WorldItems.spawn(id, amount, piece.global_position + Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)))
		unregister_piece(piece)
		piece.queue_free()
		fallen += 1
	if fallen > 0:
		_collapse_fx_all(fallen)


func _collapse_fx_all(count: int) -> void:
	var text := "A construção desabou (%d peça%s)" % [count, "" if count == 1 else "s"]
	_notify(text)
	if Network.is_online():
		_notify.rpc(text)


## Árvore, rocha, caixote, estação, jogador ou zumbi dentro do volume da peça?
## (peças vizinhas não contam: estão em outra camada)
func _is_obstructed(piece_id: String, xform: Transform3D) -> bool:
	var space := _root.get_world_3d().direct_space_state
	var volumes: Array = BuildPiece.parts(piece_id)
	if piece_id == "foundation":
		volumes = [[Vector3(BuildPiece.CELL, 1.4, BuildPiece.CELL), Vector3(0, 0.85, 0), 0.0]]  # espaço acima dela
	for part: Array in volumes:
		var box := BoxShape3D.new()
		var size: Vector3 = part[0]
		box.size = Vector3(maxf(size.x - 0.3, 0.05), maxf(size.y - 0.3, 0.05), maxf(size.z - 0.3, 0.05))
		if piece_id == "stairs":
			box.size.z = size.z - 0.8  # não encosta no chão nem no piso de cima
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = xform * BuildPiece.part_transform(part)
		q.collision_mask = 1 | 2 | 4  # mundo, jogadores, zumbis
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false


# --- Muro de terra (feitiço) ---------------------------------------------------------

## Encaixe de parede à frente de quem conjura: [chave, rot].
func wall_slot_in_front(player: Node3D) -> Array:
	var forward := -player.global_basis.z
	var point := player.global_position + Vector3(forward.x, 0, forward.z).normalized() * 2.5
	var cell := BuildPiece.CELL
	var level := maxi(roundi(player.global_position.y / BuildPiece.HEIGHT), 0)
	if absf(forward.x) > absf(forward.z):
		return ["x:%d:%d:%d" % [roundi(point.x / cell), floori(point.z / cell), level], 1]
	return ["z:%d:%d:%d" % [floori(point.x / cell), roundi(point.z / cell), level], 0]


func cast_earth_wall(player: Node3D, duration: float) -> void:
	if multiplayer.is_server():
		_earth_wall(player, duration)
	elif Network.is_online():
		_request_earth_wall.rpc_id(1, duration)


@rpc("any_peer", "call_remote", "reliable")
func _request_earth_wall(duration: float) -> void:
	var player := _sender_player()
	if player:
		_earth_wall(player, clampf(duration, 1.0, 60.0))


func _earth_wall(player: Node3D, duration: float) -> void:
	var slot := wall_slot_in_front(player)
	if check_build("earth_wall", slot[0], slot[1], player.global_position) != "":
		return
	_spawn_piece("earth_wall", "earth", slot[0], slot[1])
	var piece := piece_at(slot[0])
	get_tree().create_timer(duration, false).timeout.connect(func() -> void:
		if is_instance_valid(piece) and not piece.is_queued_for_deletion():
			_remove(piece))


## Quem chama já tirou o custo do inventário.
func build(piece_id: String, tier: String, key: String, rot: int) -> void:
	if multiplayer.is_server():
		_spawn_piece(piece_id, tier, key, rot)
	elif Network.is_online():
		_request_build.rpc_id(1, piece_id, tier, key, rot)


func _spawn_piece(piece_id: String, tier: String, key: String, rot: int) -> void:
	_spawner.spawn({"kind": "piece", "id": piece_id, "tier": tier, "slot": key, "rot": rot})
	layout_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_build(piece_id: String, tier: String, key: String, rot: int) -> void:
	var player := _sender_player()
	var price := cost(piece_id, tier)
	if player == null or price.is_empty():
		return
	var reason := check_build(piece_id, key, rot, player.global_position)
	if reason != "":
		var inventory := player.get_node(^"Inventory") as Inventory
		for id: String in price:
			inventory.grant(id, int(price[id]))
		_notify.rpc_id(multiplayer.get_remote_sender_id(), "%s (material devolvido)" % reason)
		return
	_spawn_piece(piece_id, tier, key, rot)


## O que desmontar devolve: metade do custo, proporcional à vida que sobra.
func demolish_refund(piece: BuildPiece) -> Dictionary:
	var condition := piece.health.current / maxf(piece.health.max_health, 1.0)
	var price := cost(piece.piece_id, piece.tier)
	var out := {}
	for id: String in price:
		var amount := floori(float(price[id]) * DEMOLISH_REFUND * condition)
		if amount > 0:
			out[id] = amount
	return out


func demolish(piece: BuildPiece, player: Node3D) -> void:
	if piece == null:
		return
	if multiplayer.is_server():
		_demolish(piece, player)
	elif Network.is_online():
		_request_demolish.rpc_id(1, piece.slot_key)


@rpc("any_peer", "call_remote", "reliable")
func _request_demolish(key: String) -> void:
	var player := _sender_player()
	var piece := piece_at(key)
	if player and piece:
		_demolish(piece, player)


func _demolish(piece: BuildPiece, player: Node3D) -> void:
	if piece.is_queued_for_deletion() or player.global_position.distance_to(piece.global_position + Vector3.UP) > MAX_BUILD_DISTANCE:
		return
	var inventory := player.get_node(^"Inventory") as Inventory
	var refund := demolish_refund(piece)
	for id: String in refund:
		inventory.grant(id, int(refund[id]))
	_remove(piece)


## Servidor: a peça perdeu toda a vida (zumbis).
func piece_destroyed(piece: BuildPiece) -> void:
	_remove(piece)


## check_integrity: false ao trocar a peça por outra no mesmo lugar (melhoria).
func _remove(piece: BuildPiece, check_integrity := true) -> void:
	unregister_piece(piece)
	piece.queue_free()
	if check_integrity:
		_collapse_unsupported()
	layout_changed.emit()


# --- Martelo: consertar e melhorar ----------------------------------------------------

## Quanto uma martelada recupera agora (0 = vida cheia).
func repair_amount(piece: BuildPiece) -> float:
	var h := piece.health
	return minf(h.max_health - h.current, h.max_health * REPAIR_STEP)


## Material de uma martelada ({} = não precisa).
func repair_cost(piece: BuildPiece) -> Dictionary:
	var amount := repair_amount(piece)
	if amount <= 0.0:
		return {}
	var fraction := amount / piece.health.max_health
	var price := cost(piece.piece_id, piece.tier)
	var out := {}
	for id: String in price:
		var n := roundi(float(price[id]) * REPAIR_COST * fraction)
		if n > 0:
			out[id] = n
	if out.is_empty() and not price.is_empty():
		out[price.keys()[0]] = 1
	return out


## Próximo material ("" = já é o melhor).
func next_tier(piece: BuildPiece) -> String:
	var index := TIERS.find(piece.tier)
	if index < 0 or index + 1 >= TIERS.size():
		return ""
	var next: String = TIERS[index + 1]
	return next if not cost(piece.piece_id, next).is_empty() else ""


## Quem chama já tirou `paid` do inventário; se o servidor recusar, devolve.
func repair(piece: BuildPiece, player: Node3D, paid: Dictionary) -> void:
	if multiplayer.is_server():
		_repair(piece, player, paid)
	elif Network.is_online():
		_request_repair.rpc_id(1, piece.slot_key, paid)


func upgrade(piece: BuildPiece, player: Node3D, paid: Dictionary) -> void:
	if multiplayer.is_server():
		_upgrade(piece, player, paid)
	elif Network.is_online():
		_request_upgrade.rpc_id(1, piece.slot_key, paid)


@rpc("any_peer", "call_remote", "reliable")
func _request_repair(key: String, paid: Dictionary) -> void:
	var player := _sender_player()
	if player:
		_repair(piece_at(key), player, paid)


@rpc("any_peer", "call_remote", "reliable")
func _request_upgrade(key: String, paid: Dictionary) -> void:
	var player := _sender_player()
	if player:
		_upgrade(piece_at(key), player, paid)


func _repair(piece: BuildPiece, player: Node3D, paid: Dictionary) -> void:
	if piece == null or not _in_reach(piece, player) or repair_amount(piece) <= 0.0:
		_refund(player, paid, "Não deu para consertar")
		return
	piece.health.heal(repair_amount(piece))


## Melhorar troca a peça por uma nova do próximo material, com vida cheia.
func _upgrade(piece: BuildPiece, player: Node3D, paid: Dictionary) -> void:
	var next := next_tier(piece) if piece else ""
	if next == "" or not _in_reach(piece, player):
		_refund(player, paid, "Não deu para melhorar")
		return
	var key := piece.slot_key
	var rot := piece.rot
	var id := piece.piece_id
	_remove(piece, false)
	_spawn_piece(id, next, key, rot)


func _in_reach(piece: BuildPiece, player: Node3D) -> bool:
	return is_instance_valid(piece) and not piece.is_queued_for_deletion() \
		and player.global_position.distance_to(piece.nearest_point(player.global_position)) <= MAX_BUILD_DISTANCE


func _refund(player: Node3D, paid: Dictionary, text: String) -> void:
	var inventory := player.get_node(^"Inventory") as Inventory
	for id in paid:
		inventory.grant(str(id), int(paid[id]))
	if player.is_multiplayer_authority():
		player.notify(text + " (material devolvido)")
	else:
		_notify.rpc_id(player.get_multiplayer_authority(), text + " (material devolvido)")


# --- Rede ------------------------------------------------------------------------------

func _sender_player() -> Node3D:
	var sender := multiplayer.get_remote_sender_id()
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			return p
	return null


@rpc("authority", "call_remote", "reliable")
func _notify(text: String) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			p.notify(text)


## Quem entra depois recebe as peças pelo spawner; vida e portas abertas vão aqui.
func _on_peer_connected(peer: int) -> void:
	await get_tree().create_timer(1.5, false).timeout
	if not peer in multiplayer.get_peers():
		return
	for piece in pieces():
		piece.send_state_to(peer)


func _create(data: Dictionary) -> Node:
	if data.get("kind", "station") == "piece":
		var piece: BuildPiece = PIECE_SCRIPT.new()
		piece.piece_id = data.id
		piece.tier = data.tier
		piece.slot_key = data.slot
		piece.rot = data.rot
		piece.transform = BuildPiece.slot_transform(data.slot, data.rot)
		return piece
	if GameData.get_item(data.id).get("type", "") == "trap":
		var trap: Trap = TRAP_SCRIPT.new()
		trap.item_id = data.id
		trap.uses = float(data.get("dur", -1.0))
		trap.position = data.pos
		trap.rotation.y = data.rot
		return trap
	var node: StaticBody3D = STATION_SCRIPT.new()
	node.item_id = data.id
	node.position = data.pos
	node.rotation.y = data.rot
	return node

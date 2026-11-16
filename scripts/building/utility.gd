class_name BaseUtility
extends CraftingStation
## Utilidades da base (GDD 9.3), colocadas como as estações:
## - Baú ("chest"): guarda até MAX_STACKS pilhas, compartilhado (o servidor manda).
## - Cama ("bed"): E define o seu ponto de renascimento (vale nesta partida e no save).
## - Coletor de água ("collector"): junta água limpa com o tempo (bem mais na chuva);
##   E enche as garrafas vazias com ela.

const MAX_STACKS := 30
const COLLECTOR_MAX := 10
## Segundos por garrafa: tempo normal e com chuva/tempestade.
const COLLECT_DRY := 90.0
const COLLECT_RAIN := 20.0

## Baú: lista de pilhas {id, count, ...extras}.
var contents: Array = []
## Coletor: garrafas de água prontas.
var water := 0

var _collect_timer := 0.0


func _ready() -> void:
	super()
	if station == "collector":
		set_process(true)


func get_prompt() -> String:
	match station:
		"chest": return "[E] Abrir baú (%d/%d)" % [contents.size(), MAX_STACKS]
		"bed": return "[E] Dormir aqui (renascer nesta cama)"
		"collector": return "[E] Encher garrafas (%d de água limpa)" % water
	return super()


func interact(player: Node3D) -> void:
	match station:
		"chest":
			EventBus.chest_opened.emit(self, player)
			if not multiplayer.is_server() and Network.is_online():
				_request_contents.rpc_id(1)
		"bed":
			player.set_respawn_point(global_position + Vector3.UP * 0.3)
		"collector":
			_collect(player)
		_:
			super(player)


func _process(delta: float) -> void:
	super(delta)
	if station != "collector" or not multiplayer.is_server() or water >= COLLECTOR_MAX:
		return
	var w := Weather.find(get_tree())
	var rainy := w != null and w.state in ["rain", "storm"]
	_collect_timer += delta
	if _collect_timer >= (COLLECT_RAIN if rainy else COLLECT_DRY):
		_collect_timer = 0.0
		_set_water(water + 1)


# --- Coletor -----------------------------------------------------------------------------

func _collect(player: Node3D) -> void:
	var inv := player.get_node(^"Inventory") as Inventory
	var want := mini(inv.count_of("empty_bottle"), water)
	if want <= 0:
		player.notify("Precisa de garrafas vazias" if water > 0 else "O coletor ainda está vazio")
		return
	inv.remove_item("empty_bottle", want)
	if multiplayer.is_server():
		_give_water(player, want)
	else:
		_request_water.rpc_id(1, want)


@rpc("any_peer", "call_remote", "reliable")
func _request_water(want: int) -> void:
	var p := _sender()
	if p:
		_give_water(p, clampi(want, 0, COLLECTOR_MAX))


## Servidor: entrega o que tem; o resto das garrafas volta vazio.
func _give_water(player: Node3D, want: int) -> void:
	var inv := player.get_node(^"Inventory") as Inventory
	var got := mini(want, water)
	if got > 0:
		inv.grant("water_bottle", got)
	if want - got > 0:
		inv.grant("empty_bottle", want - got)
	_set_water(water - got)


func _set_water(value: int) -> void:
	water = clampi(value, 0, COLLECTOR_MAX)
	if Network.is_online() and multiplayer.is_server():
		_sync_water.rpc(water)


@rpc("authority", "call_remote", "reliable")
func _sync_water(value: int) -> void:
	water = value


# --- Baú ---------------------------------------------------------------------------------

## Guarda uma pilha (quem chama já tirou do próprio inventário).
func put(stack: Dictionary) -> void:
	if multiplayer.is_server():
		_put(stack, null)
	else:
		_request_put.rpc_id(1, stack)


## Pega a pilha `index` do baú.
func take(index: int) -> void:
	if multiplayer.is_server():
		_take(index, _local_player())
	else:
		_request_take.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _request_put(stack: Dictionary) -> void:
	_put(stack, _sender())


@rpc("any_peer", "call_remote", "reliable")
func _request_take(index: int) -> void:
	_take(index, _sender())


@rpc("any_peer", "call_remote", "reliable")
func _request_contents() -> void:
	_sync_contents.rpc_id(multiplayer.get_remote_sender_id(), contents)


func _put(stack: Dictionary, from: Node3D) -> void:
	if GameData.get_item(str(stack.get("id", ""))).is_empty() or int(stack.get("count", 0)) <= 0:
		return
	var id := str(stack.id)
	var count := int(stack.count)
	var max_stack := GameData.max_stack(id)
	var extra := Inventory.extra_of(stack)
	# Junta com pilhas iguais (sem extras), depois ocupa uma nova.
	if extra.is_empty():
		for s: Dictionary in contents:
			if s.id == id and Inventory.extra_of(s).is_empty() and int(s.count) < max_stack:
				var add := mini(max_stack - int(s.count), count)
				s.count = int(s.count) + add
				count -= add
				if count == 0:
					break
	while count > 0 and contents.size() < MAX_STACKS:
		var n := mini(count, max_stack)
		var s := {"id": id, "count": n}
		s.merge(extra)
		contents.append(s)
		count -= n
	if count > 0:
		# Baú cheio: devolve o que sobrou.
		var who := from if from else _local_player()
		if who:
			(who.get_node(^"Inventory") as Inventory).grant(id, count, extra)
			who.notify("Baú cheio")
	_contents_changed()


func _take(index: int, to: Node3D) -> void:
	if to == null or index < 0 or index >= contents.size():
		return
	if to.global_position.distance_to(global_position) > USE_RANGE + 1.5:
		return
	var s: Dictionary = contents[index]
	contents.remove_at(index)
	(to.get_node(^"Inventory") as Inventory).grant(str(s.id), int(s.count), Inventory.extra_of(s))
	_contents_changed()


func _contents_changed() -> void:
	if Network.is_online():
		_sync_contents.rpc(contents)
	EventBus.chest_changed.emit(self)


@rpc("authority", "call_remote", "reliable")
func _sync_contents(list: Array) -> void:
	contents = list
	EventBus.chest_changed.emit(self)


func _sender() -> Node3D:
	var sender := multiplayer.get_remote_sender_id()
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			return p
	return null


func _local_player() -> Node3D:
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null


# --- Visual ------------------------------------------------------------------------------

func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	match station:
		"chest":
			add_child(Weapon.box(Vector3(1.0, 0.55, 0.6), Color(0.45, 0.3, 0.17), Vector3(0, 0.28, 0)))
			add_child(Weapon.box(Vector3(1.04, 0.12, 0.64), Color(0.35, 0.23, 0.13), Vector3(0, 0.6, 0)))
			add_child(Weapon.box(Vector3(0.12, 0.14, 0.04), Color(0.7, 0.62, 0.3), Vector3(0, 0.45, 0.31)))
			box.size = Vector3(1.0, 0.7, 0.6)
			shape.position.y = 0.35
		"bed":
			add_child(Weapon.box(Vector3(1.0, 0.35, 2.0), Color(0.42, 0.29, 0.17), Vector3(0, 0.18, 0)))
			add_child(Weapon.box(Vector3(0.9, 0.12, 1.85), Color(0.55, 0.2, 0.18), Vector3(0, 0.41, 0)))
			add_child(Weapon.box(Vector3(0.7, 0.12, 0.35), Color(0.85, 0.85, 0.8), Vector3(0, 0.5, -0.7)))
			box.size = Vector3(1.0, 0.5, 2.0)
			shape.position.y = 0.25
		_:  # coletor
			add_child(Weapon.cylinder(0.45, 0.8, Color(0.4, 0.3, 0.2), Vector3(0, 0.4, 0)))
			var cloth := Weapon.box(Vector3(1.4, 0.04, 1.4), Color(0.75, 0.75, 0.7), Vector3(0, 1.1, 0))
			add_child(cloth)
			for x in [-0.65, 0.65]:
				for z in [-0.65, 0.65]:
					add_child(Weapon.box(Vector3(0.05, 1.1, 0.05), Color(0.4, 0.28, 0.16), Vector3(x, 0.55, z)))
			box.size = Vector3(1.0, 0.9, 1.0)
			shape.position.y = 0.45
	shape.shape = box
	add_child(shape)
	for m: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

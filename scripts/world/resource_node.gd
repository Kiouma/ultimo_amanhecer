class_name ResourceNode
extends StaticBody3D
## Recurso coletável do mundo (GDD 8.1): árvore, rocha, arbusto, ninho, galhos.
## Dados em data/nodes/nodes.json (lidos pelo node_id).
## - Árvore/rocha (etapa 7): precisa da ferramenta certa no slot (machado para árvores,
##   picareta para rochas e cristais). E começa a coleta, que leva "gather_time"
##   segundos ÷ velocidade da ferramenta (ver Gathering); no fim, dá tudo de uma vez
##   (madeira/pedra × rendimento da ferramenta) e o recurso some.
## - Arbusto/ninho/galhos ("by_hand"): E colhe tudo de uma vez e some.
## Visual: modelos do Nature MegaKit (NatureKit) quando os dados têm "models".
## Some e volta depois de "respawn" segundos (ver Arena).
##
## Rede: só o servidor muda o recurso. Quem coleta pede (request_gather/request_harvest);
## o servidor confere a distância (e a ferramenta), entrega com Inventory.grant e remove
## o nó (o MultiplayerSpawner da arena replica sumir/voltar para todos).

## Emitido no servidor quando esgota: (tipo, posição, rotação y) para a arena agendar a volta.
signal depleted(node_id: String, position: Vector3, rotation_y: float)

## Quanto da "vida" do recurso equivale a uma porção de "per_hit" (árvore 100 → 4 porções).
const HIT_POWER := 25.0
const MAX_REACH := 4.5
## Tempo base de coleta (s) com ferramenta de velocidade 1.
const GATHER_TIME := {"tree": 4.0, "rock": 3.0}

var node_id := "tree"
var data: Dictionary = {}
var hp := 100.0

var _visual: Node3D


func _ready() -> void:
	data = GameData.get_entry("nodes", node_id)
	hp = float(data.get("health", 100.0))
	# "solid": false (ex.: galhos caídos) = sem corpo físico: não bloqueia ninguém,
	# só pode ser usado com E (camada de interagíveis).
	collision_layer = (1 if data.get("solid", true) else 0) | 32
	collision_mask = 0
	if data.get("obstacle", false):
		add_to_group("navmesh_source")
	_build()


## "tree" ou "rock" (o que se coleta com ferramenta); "" = colhe à mão.
func gather_kind() -> String:
	if data.get("by_hand", false):
		return ""
	return str(data.get("gather_as", data.get("kind", "")))


## Slot da ferramenta que coleta este recurso ("axe", "pickaxe").
func tool_slot() -> String:
	return "axe" if gather_kind() == "tree" else "pickaxe"


## Segundos de coleta com ferramenta de velocidade 1.
func base_gather_time() -> float:
	return float(data.get("gather_time", GATHER_TIME.get(gather_kind(), 3.0)))


## Aviso de interação: colher, ou cortar/minerar com o tempo (ou o que falta).
func get_prompt() -> String:
	if data.get("by_hand", false):
		return "[E] %s %s" % [data.get("verb", tr("Coletar")), str(data.get("name", node_id)).to_lower()]
	var player := _local_player()
	var verb := tr("Cortar") if gather_kind() == "tree" else tr("Minerar")
	if player == null or player.gathering == null:
		return ""
	if player.equipment.tool_item(tool_slot()).is_empty():
		return tr("%s: precisa de %s no slot de ferramenta (V)") % [str(data.get("name", node_id)), tr("um machado") if tool_slot() == "axe" else tr("uma picareta")]
	return tr("[E] %s %s (%.1f s)") % [verb, str(data.get("name", node_id)).to_lower(), player.gathering.gather_time(self)]


func interact(player: Node3D) -> void:
	if data.get("by_hand", false):
		request_gather(player, {})
	elif player is Player and player.gathering:
		player.gathering.start_gather(self)


## Usado pelo Player: todos os recursos têm aviso (com ferramenta, árvores e rochas).
func has_prompt() -> bool:
	return true


func _local_player() -> Player:
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Player and p.is_local():
			return p
	return null


## Colheita à mão (arbusto, ninho, galhos). tool_data é ignorado (compatibilidade).
func request_gather(player: Node3D, _tool_data: Dictionary, quality := 1.0) -> void:
	_shake()
	var prog := Progression.of(player)
	if prog:
		prog.gain("survival", 1.0)
		quality *= prog.mult("gather_yield")
	if multiplayer.is_server():
		_gather(player, quality)
	elif Network.is_online():
		_request_gather.rpc_id(1, quality)


@rpc("any_peer", "call_remote", "reliable")
func _request_gather(quality: float) -> void:
	var p := _sender_player()
	if p:
		_gather(p, clampf(quality, 1.0, 3.0))


## Fim da coleta com ferramenta: pede ao servidor tudo o que o recurso dá.
## yield_mult: rendimento da ferramenta × qualidade/refino × proficiência.
func request_harvest(player: Node3D, tool_id: String, yield_mult: float) -> void:
	_shake()
	if multiplayer.is_server():
		_harvest(player, tool_id, yield_mult)
	elif Network.is_online():
		_request_harvest.rpc_id(1, tool_id, yield_mult)


@rpc("any_peer", "call_remote", "reliable")
func _request_harvest(tool_id: String, yield_mult: float) -> void:
	var p := _sender_player()
	if p:
		_harvest(p, tool_id, clampf(yield_mult, 0.5, 12.0))


func _sender_player() -> Node3D:
	var sender := multiplayer.get_remote_sender_id()
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			return p
	return null


# --- Servidor ---------------------------------------------------------------------

func _gather(player: Node3D, quality := 1.0) -> void:
	if is_queued_for_deletion() or player.global_position.distance_to(global_position) > MAX_REACH \
			or not data.get("by_hand", false):
		return
	var inventory := player.get_node_or_null(^"Inventory") as Inventory
	if inventory == null:
		return
	for id: String in data.get("yield", {}):
		var span: Array = data.yield[id]
		var amount := roundi(randi_range(int(span[0]), int(span[1])) * quality)
		if amount > 0:
			inventory.grant(id, amount)
	_deplete()


## Coleta completa com ferramenta: porções de "per_hit" (vida ÷ HIT_POWER), chances de
## "per_hit_chance" a cada porção e o bônus "on_depleted", tudo × rendimento.
func _harvest(player: Node3D, tool_id: String, yield_mult: float) -> void:
	if is_queued_for_deletion() or player.global_position.distance_to(global_position) > MAX_REACH:
		return
	if str(GameData.get_item(tool_id).get("tool", "")) != tool_slot():
		return
	var inventory := player.get_node_or_null(^"Inventory") as Inventory
	if inventory == null:
		return
	var portions := maxf(hp / HIT_POWER, 1.0)
	for id: String in data.get("per_hit", {}):
		_grant_fraction(inventory, id, float(data.per_hit[id]) * portions * yield_mult)
	for id: String in data.get("per_hit_chance", {}):
		for i in ceili(portions):
			if randf() < float(data.per_hit_chance[id]) * yield_mult:
				inventory.grant(id, 1)
	for id: String in data.get("on_depleted", {}):
		_grant_fraction(inventory, id, float(data.on_depleted[id]) * yield_mult)
	_deplete()


## 0,35 madeira = 0 ou 1 (35% de chance); 1,4 = 1 ou 2.
func _grant_fraction(inventory: Inventory, id: String, amount: float) -> void:
	var whole := int(amount)
	if randf() < amount - whole:
		whole += 1
	if whole > 0:
		inventory.grant(id, whole)


func _deplete() -> void:
	depleted.emit(node_id, global_position, rotation.y)
	queue_free()


# --- Visual ------------------------------------------------------------------------
# Com "models" nos dados: um modelo do Nature MegaKit (NatureKit), escolhido pela posição
# (igual em todas as máquinas) e escalado para uma altura em "height" [mín, máx].
# Sem "models": formas simples (reserva).

func _shake() -> void:
	if _visual == null:
		return
	var tw := create_tween()
	tw.tween_property(_visual, "rotation:z", 0.06, 0.05)
	tw.tween_property(_visual, "rotation:z", -0.04, 0.07)
	tw.tween_property(_visual, "rotation:z", 0.0, 0.08)


## Põe o modelo do kit em _visual. Devolve a caixa dele já escalada (vazia = sem modelo).
func _add_model() -> AABB:
	var models: Array = data.get("models", [])
	if models.is_empty():
		return AABB()
	var h := NatureKit.position_hash(position)
	var model := str(models[h % models.size()])
	var span: Array = data.get("height", [0.0, 0.0])
	var target := lerpf(float(span[0]), float(span[1]), float((h / 7) % 1000) / 999.0)
	var node := NatureKit.instance(model, target)
	if node == null:
		return AABB()
	_visual.add_child(node)
	var box := NatureKit.mesh(model).get_aabb()
	return AABB(box.position * node.scale, box.size * node.scale)


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var box := _add_model()
	var has_model := box.size != Vector3.ZERO
	var shape := CollisionShape3D.new()
	match str(data.get("kind", "")):
		"tree":
			if not has_model:
				_build_tree_shapes(str(data.get("look", "")) == "pine")
			var cyl := CylinderShape3D.new()
			cyl.radius = float(data.get("radius", 0.3))
			cyl.height = 3.2
			shape.shape = cyl
			shape.position.y = 1.6
		"rock":
			if not has_model:
				var rock := Weapon.sphere(0.8, Color(0.45, 0.45, 0.47), Vector3(0, 0.45, 0))
				rock.scale = Vector3(1.3, 0.75, 1.0)
				_visual.add_child(rock)
				box = AABB(Vector3(-0.95, 0.0, -0.75), Vector3(1.9, 1.1, 1.5))
			var rock_box := BoxShape3D.new()
			rock_box.size = Vector3(box.size.x * 0.8, maxf(box.end.y, 0.4), box.size.z * 0.8)
			shape.shape = rock_box
			shape.position = Vector3(box.get_center().x, rock_box.size.y * 0.5, box.get_center().z)
		"bush":
			# Folhagem como elipsoide (raio horizontal rx, vertical ry, centro cy).
			var rx := 0.72
			var ry := 0.51
			var cy := 0.5
			if has_model:
				rx = maxf(box.size.x, box.size.z) * 0.36
				ry = box.end.y * 0.4
				cy = box.end.y * 0.5
			else:
				var bush := Weapon.sphere(0.6, Color(0.18, 0.4, 0.2), Vector3(0, 0.5, 0))
				bush.scale = Vector3(1.2, 0.85, 1.2)
				_visual.add_child(bush)
			# Frutinhas na superfície da folhagem.
			for i in 16:
				var a := TAU * i / 16.0 + (0.3 if i % 2 else 0.0)
				var v := -0.3 + 0.6 * float(i % 3) / 2.0
				var r := rx * sqrt(maxf(1.0 - v * v, 0.2))
				_visual.add_child(Weapon.sphere(0.07, Color(0.75, 0.1, 0.2), Vector3(cos(a) * r, cy + v * ry, sin(a) * r)))
			var sphere := SphereShape3D.new()
			sphere.radius = 0.6
			shape.shape = sphere
			shape.position.y = 0.5
		"nest":
			var nest := Weapon.cylinder(0.3, 0.15, Color(0.45, 0.33, 0.2), Vector3(0, 0.08, 0))
			_visual.add_child(nest)
			for i in 3:
				var feather := Weapon.box(Vector3(0.04, 0.01, 0.22), Color(0.95, 0.95, 0.92), Vector3(-0.1 + i * 0.1, 0.18, 0))
				feather.rotation.y = 0.5 * i
				_visual.add_child(feather)
			var nest_box := BoxShape3D.new()
			nest_box.size = Vector3(0.6, 0.3, 0.6)
			shape.shape = nest_box
			shape.position.y = 0.15
		"herb":
			var top := 0.38
			if has_model:
				top = box.end.y * 0.85
			else:
				for i in 7:
					var leaf := Weapon.box(Vector3(0.05, 0.35, 0.12), Color(0.3, 0.55, 0.25), Vector3(cos(i * 0.9) * 0.15, 0.17, sin(i * 0.9) * 0.15))
					leaf.rotation = Vector3(0.3 * cos(i * 0.9), i * 0.9, 0.3 * sin(i * 0.9))
					_visual.add_child(leaf)
			# Flores amarelas que brilham: dá para achar a erva no meio do mato.
			for i in 3:
				_visual.add_child(Weapon.sphere(0.05, Color(0.85, 0.85, 0.4), Vector3(cos(i * 2.1) * 0.12, top, sin(i * 2.1) * 0.12), true))
			var herb_box := BoxShape3D.new()
			herb_box.size = Vector3(0.6, 0.4, 0.6)
			shape.shape = herb_box
			shape.position.y = 0.2
		"crystal":
			if not has_model:
				_visual.add_child(Weapon.sphere(0.7, Color(0.35, 0.33, 0.38), Vector3(0, 0.3, 0)))
			for i in 5:
				var shard := Weapon.box(Vector3(0.18, 0.9 - i * 0.1, 0.18), Color(0.6, 0.35, 0.95), Vector3(cos(i * 1.3) * 0.3, 0.7, sin(i * 1.3) * 0.3), true)
				shard.rotation = Vector3(0.35 * cos(i * 1.3), i, 0.35 * sin(i * 1.3))
				_visual.add_child(shard)
			var light := OmniLight3D.new()
			light.light_color = Color(0.7, 0.4, 1.0)
			light.light_energy = 0.8
			light.omni_range = 4.0
			light.position.y = 1.0
			_visual.add_child(light)
			var crystal_box := BoxShape3D.new()
			crystal_box.size = Vector3(1.4, 1.4, 1.4)
			shape.shape = crystal_box
			shape.position.y = 0.6
		"pebble":  # pedrinhas soltas no chão (E pega pedra)
			if not has_model:
				_visual.add_child(Weapon.sphere(0.12, Color(0.5, 0.5, 0.52), Vector3(0, 0.06, 0)))
			var pebble_box := BoxShape3D.new()
			pebble_box.size = Vector3(0.6, 0.3, 0.6)
			shape.shape = pebble_box
			shape.position.y = 0.15
		_:  # galhos caídos
			for i in 4:
				var branch := Weapon.box(Vector3(0.05, 0.05, 0.7), Color(0.4, 0.28, 0.16), Vector3(0, 0.05, 0))
				branch.rotation.y = 0.8 * i
				_visual.add_child(branch)
			var branch_box := BoxShape3D.new()
			branch_box.size = Vector3(0.8, 0.2, 0.8)
			shape.shape = branch_box
			shape.position.y = 0.1
	# Desempenho: some de longe (a névoa já esconde). Árvores e rochas se veem de mais longe.
	var view_range: float = {"tree": 140.0, "rock": 110.0, "crystal": 110.0}.get(str(data.get("kind", "")), 45.0)
	for m: GeometryInstance3D in _visual.find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m.visibility_range_end = view_range
		m.visibility_range_end_margin = 8.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(shape)


## Árvore de formas simples (sem modelo): copa redonda ou pinheiro de cones.
func _build_tree_shapes(pine: bool) -> void:
	if pine:
		_visual.add_child(Weapon.cylinder(0.18, 2.4, Color(0.32, 0.22, 0.14), Vector3(0, 1.2, 0)))
		for k in 3:
			var cone := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.0
			mesh.bottom_radius = 1.5 - k * 0.38
			mesh.height = 1.8
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.16, 0.3, 0.22).lerp(Color(0.85, 0.88, 0.92), 0.25 if k == 2 else 0.1)
			mesh.material = mat
			cone.mesh = mesh
			cone.position.y = 2.0 + k * 1.0
			_visual.add_child(cone)
		return
	_visual.add_child(Weapon.cylinder(0.22, 3.2, Color(0.36, 0.25, 0.15), Vector3(0, 1.6, 0)))
	_visual.add_child(Weapon.sphere(1.4, Color(0.2, 0.42, 0.18), Vector3(0, 3.6, 0)))
	_visual.add_child(Weapon.sphere(1.0, Color(0.24, 0.48, 0.2), Vector3(0.6, 4.4, 0.3)))

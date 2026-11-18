class_name ResourceNode
extends StaticBody3D
## Recurso coletável do mundo (GDD 8.1): árvore, rocha, arbusto, ninho, galhos.
## Dados em data/nodes/nodes.json (lidos pelo node_id).
## - Árvore/rocha: golpes de arma melee (ou soco). Cada golpe dá itens conforme o
##   fator de coleta da ferramenta ("gather" do item: machado bom em árvore,
##   picareta em rocha). Ao esgotar, dá um bônus e some.
## - Arbusto/ninho/galhos ("by_hand"): E colhe tudo de uma vez e some.
## Visual: modelos do Nature MegaKit (NatureKit) quando os dados têm "models".
## Some e volta depois de "respawn" segundos (ver Arena).
##
## Rede: só o servidor muda o recurso. Quem coleta pede (request_gather); o
## servidor confere a distância, entrega com Inventory.grant e remove o nó (o
## MultiplayerSpawner da arena replica sumir/voltar para todos).

## Emitido no servidor quando esgota: (tipo, posição, rotação y) para a arena agendar a volta.
signal depleted(node_id: String, position: Vector3, rotation_y: float)

## Dano de coleta por golpe com fator 1.0 (vida da árvore = 100 → 4 golpes de machado).
const HIT_POWER := 25.0
const MAX_REACH := 4.5

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


## Nome mostrado e aviso de interação (só recursos colhidos à mão).
func get_prompt() -> String:
	if data.get("by_hand", false):
		return "[E] %s %s" % [data.get("verb", "Coletar"), str(data.get("name", node_id)).to_lower()]
	return ""


func interact(player: Node3D) -> void:
	if data.get("by_hand", false):
		request_gather(player, {})


## Usado pelo Player para só mostrar aviso em recursos colhidos à mão.
func has_prompt() -> bool:
	return data.get("by_hand", false)


## Golpe ou colheita. tool_data = dados do item usado ({} = mãos/colheita).
## quality: multiplicador da ferramenta (qualidade × refino, 1,0 a ~2,37).
func request_gather(player: Node3D, tool_data: Dictionary, quality := 1.0) -> void:
	_shake()
	var prog := Progression.of(player)
	if prog:
		prog.gain("survival", 1.0)
		if data.get("by_hand", false):
			quality *= prog.mult("gather_yield")
	var tool_id := str(tool_data.get("id", ""))
	if multiplayer.is_server():
		_gather(player, tool_id, quality)
	elif Network.is_online():
		_request_gather.rpc_id(1, tool_id, quality)


@rpc("any_peer", "call_remote", "reliable")
func _request_gather(tool_id: String, quality: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	# Qualidade × refino máximos × rendimento máximo da Sobrevivência e habilidades.
	var max_quality := (1.0 + Inventory.QUALITY_STEP * (Inventory.MAX_QUALITY - 1)) \
		* (1.0 + Inventory.REFINE_STEP * Inventory.MAX_REFINE) * 2.0
	for p in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			_gather(p, tool_id, clampf(quality, 1.0, max_quality))
			return


# --- Servidor ---------------------------------------------------------------------

func _gather(player: Node3D, tool_id: String, quality := 1.0) -> void:
	if is_queued_for_deletion() or player.global_position.distance_to(global_position) > MAX_REACH:
		return
	var inventory := player.get_node_or_null(^"Inventory") as Inventory
	if inventory == null:
		return
	if data.get("by_hand", false):
		for id: String in data.get("yield", {}):
			var span: Array = data.yield[id]
			var amount := roundi(randi_range(int(span[0]), int(span[1])) * quality)
			if amount > 0:
				inventory.grant(id, amount)
		_deplete()
		return

	var factor := _tool_factor(tool_id)
	if factor <= 0.0:
		return
	factor *= quality
	for id: String in data.get("per_hit", {}):
		_grant_fraction(inventory, id, float(data.per_hit[id]) * factor)
	for id: String in data.get("per_hit_chance", {}):
		if randf() < float(data.per_hit_chance[id]) * factor:
			inventory.grant(id, 1)
	hp -= HIT_POWER * factor
	if hp <= 0.0:
		for id: String in data.get("on_depleted", {}):
			inventory.grant(id, int(data.on_depleted[id]))
		_deplete()


## Fator de coleta da ferramenta para este tipo de recurso. Sem ferramenta = soco.
func _tool_factor(tool_id: String) -> float:
	var gather: Dictionary = GameData.get_item(tool_id).get("gather", {}) if tool_id != "" \
		else WeaponHolder.FISTS.get("gather", {})
	return float(gather.get(str(data.get("gather_as", data.get("kind", ""))), 0.0))


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

class_name ResourceNode
extends StaticBody3D
## Recurso coletável do mundo (GDD 8.1): árvore, rocha, arbusto, ninho, galhos.
## Dados em data/nodes/nodes.json (lidos pelo node_id).
## - Árvore/rocha: golpes de arma melee (ou soco). Cada golpe dá itens conforme o
##   fator de coleta da ferramenta ("gather" do item: machado bom em árvore,
##   picareta em rocha). Ao esgotar, dá um bônus e some.
## - Arbusto/ninho/galhos ("by_hand"): E colhe tudo de uma vez e some.
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
	var tool_id := str(tool_data.get("id", ""))
	if multiplayer.is_server():
		_gather(player, tool_id, quality)
	elif Network.is_online():
		_request_gather.rpc_id(1, tool_id, quality)


@rpc("any_peer", "call_remote", "reliable")
func _request_gather(tool_id: String, quality: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var max_quality := (1.0 + Inventory.QUALITY_STEP * (Inventory.MAX_QUALITY - 1)) \
		* (1.0 + Inventory.REFINE_STEP * Inventory.MAX_REFINE)
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
			var amount := randi_range(int(span[0]), int(span[1]))
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
	return float(gather.get(str(data.get("kind", "")), 0.0))


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


# --- Visual (provisório: formas simples) -------------------------------------------

func _shake() -> void:
	if _visual == null:
		return
	var tw := create_tween()
	tw.tween_property(_visual, "rotation:z", 0.06, 0.05)
	tw.tween_property(_visual, "rotation:z", -0.04, 0.07)
	tw.tween_property(_visual, "rotation:z", 0.0, 0.08)


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var shape := CollisionShape3D.new()
	match str(data.get("kind", "")):
		"tree":
			var trunk := Weapon.cylinder(0.22, 3.2, Color(0.36, 0.25, 0.15), Vector3(0, 1.6, 0))
			_visual.add_child(trunk)
			_visual.add_child(Weapon.sphere(1.4, Color(0.2, 0.42, 0.18), Vector3(0, 3.6, 0)))
			_visual.add_child(Weapon.sphere(1.0, Color(0.24, 0.48, 0.2), Vector3(0.6, 4.4, 0.3)))
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.3
			cyl.height = 3.2
			shape.shape = cyl
			shape.position.y = 1.6
		"rock":
			var rock := Weapon.sphere(0.8, Color(0.45, 0.45, 0.47), Vector3(0, 0.45, 0))
			rock.scale = Vector3(1.3, 0.75, 1.0)
			_visual.add_child(rock)
			var box := BoxShape3D.new()
			box.size = Vector3(1.9, 1.1, 1.5)
			shape.shape = box
			shape.position.y = 0.5
		"bush":
			var bush := Weapon.sphere(0.6, Color(0.18, 0.4, 0.2), Vector3(0, 0.5, 0))
			bush.scale = Vector3(1.2, 0.85, 1.2)
			_visual.add_child(bush)
			# Frutinhas na superfície da folhagem (elipsoide 0,72 × 0,51).
			for i in 14:
				var a := TAU * i / 14.0 + (0.3 if i % 2 else 0.0)
				var h := -0.15 + 0.5 * float(i % 3) / 2.0
				var r := 0.74 * sqrt(maxf(1.0 - h * h / 0.26, 0.2))
				_visual.add_child(Weapon.sphere(0.07, Color(0.75, 0.1, 0.2), Vector3(cos(a) * r, 0.5 + h, sin(a) * r)))
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
			var box := BoxShape3D.new()
			box.size = Vector3(0.6, 0.3, 0.6)
			shape.shape = box
			shape.position.y = 0.15
		_:  # galhos caídos
			for i in 4:
				var branch := Weapon.box(Vector3(0.05, 0.05, 0.7), Color(0.4, 0.28, 0.16), Vector3(0, 0.05, 0))
				branch.rotation.y = 0.8 * i
				_visual.add_child(branch)
			var box := BoxShape3D.new()
			box.size = Vector3(0.8, 0.2, 0.8)
			shape.shape = box
			shape.position.y = 0.1
	for m: GeometryInstance3D in _visual.find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(shape)

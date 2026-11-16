class_name BuildMode
extends Node3D
## Modo construção (GDD 9.1), só no jogador local. B liga/desliga.
## Mostra uma prévia da peça encaixada na grade: verde = dá para construir,
## vermelha = não dá (o HUD diz o motivo). Construir gasta o material do inventário.
## Controles: roda = peça, T = material, R = girar/virar, clique = construir,
## botão direito = desmontar a peça na mira (devolve parte do material).

signal changed

const TIERS := ["wood", "stone"]
## Alcance da mira para escolher onde construir.
const REACH := 7.0
## Barulho de construir (zumbis ouvem as marteladas).
const BUILD_NOISE := 9.0

var active := false
var piece_index := 0
var tier_index := 0
## Quartos de volta extras (R): vira portas e escadas.
var turn := 0
var user: Player

var _ghost: Node3D
var _ghost_id := ""
var _slot_key := ""
var _rot := 0
var _reason := ""
var _aimed: BuildPiece
var _status := ""
var _cooldown := 0.0
var _mat_ok: StandardMaterial3D
var _mat_bad: StandardMaterial3D


func setup(player: Player) -> void:
	user = player
	top_level = true
	_mat_ok = _ghost_material(Color(0.3, 1.0, 0.4, 0.38))
	_mat_bad = _ghost_material(Color(1.0, 0.25, 0.2, 0.38))


func piece_ids() -> Array:
	return GameData.get_all("buildings").keys()


func piece_id() -> String:
	return str(piece_ids()[piece_index])


func tier() -> String:
	return TIERS[tier_index]


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not active:
		_clear_ghost()
		_aimed = null
	user.weapons.visible = not active and user.first_person
	_status = ""
	changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if user == null or not user.is_local() or user.health.is_dead \
			or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("build_mode"):
		set_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	var handled := true
	if event.is_action_pressed("weapon_next"):
		piece_index = wrapi(piece_index + 1, 0, piece_ids().size())
	elif event.is_action_pressed("weapon_prev"):
		piece_index = wrapi(piece_index - 1, 0, piece_ids().size())
	elif event.is_action_pressed("build_material"):
		tier_index = wrapi(tier_index + 1, 0, TIERS.size())
	elif event.is_action_pressed("reload"):
		turn = wrapi(turn + 1, 0, 4)
	elif event.is_action_pressed("attack"):
		place()
	elif event.is_action_pressed("aim"):
		demolish()
	else:
		handled = false
		for i in Inventory.HOTBAR_SIZE:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				set_active(false)  # escolher item da hotbar sai do modo construção
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not active:
		return
	if user.health.is_dead:
		set_active(false)
		return
	_update_target()
	var status := status_text()
	if status != _status:
		_status = status
		changed.emit()


## Constrói a peça da prévia (se der). Retorna true se construiu.
func place() -> bool:
	if _cooldown > 0.0 or _slot_key == "":
		return false
	if _reason != "":
		user.notify(_reason)
		return false
	var price := Structures.cost(piece_id(), tier())
	for id: String in price:
		user.inventory.remove_item(id, int(price[id]))
	Structures.build(piece_id(), tier(), _slot_key, _rot)
	Network.emit_noise(BuildPiece.slot_transform(_slot_key, _rot).origin, BUILD_NOISE, user)
	_cooldown = 0.25
	return true


## Desmonta a peça na mira.
func demolish() -> void:
	if _aimed == null:
		user.notify("Mire numa peça para desmontar")
		return
	Structures.demolish(_aimed, user)
	_aimed = null
	_cooldown = 0.25


func can_afford() -> bool:
	var price := Structures.cost(piece_id(), tier())
	for id: String in price:
		if user.inventory.count_of(id) < int(price[id]):
			return false
	return true


## Texto do painel do HUD.
func status_text() -> String:
	if not active:
		return ""
	var data := GameData.get_entry("buildings", piece_id())
	var lines: PackedStringArray = []
	lines.append("CONSTRUÇÃO · %s de %s" % [data.get("name", piece_id()), BuildPiece.TIER_NAMES.get(tier(), tier())])
	var price := Structures.cost(piece_id(), tier())
	var parts: PackedStringArray = []
	for id: String in price:
		parts.append("%s %d/%d" % [GameData.get_item(id).get("name", id), user.inventory.count_of(id), int(price[id])])
	lines.append("Custo: " + " · ".join(parts))
	if _reason != "":
		lines.append("Não dá: " + _reason)
	if _aimed:
		lines.append("Na mira: %s %d/%d · [Botão direito] desmontar (devolve %s)" % [_aimed.display_name(),
			ceili(_aimed.health.current), int(_aimed.health.max_health), Repair.describe(Structures.demolish_refund(_aimed))])
	lines.append("[Roda] peça  [T] material  [R] girar  [Clique] construir  [B] sair")
	return "\n".join(lines)


# --- Mira e encaixe -------------------------------------------------------------------

func _update_target() -> void:
	var cam := user.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var reach := REACH + user.spring_arm.get_hit_length()
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1 | 8 | BuildPiece.DOOR_LAYER)
	query.exclude = [user.get_rid()]
	var hit := user.get_world_3d().direct_space_state.intersect_ray(query)
	var point := from + dir * minf(reach, 5.0)
	var normal := Vector3.ZERO
	_aimed = null
	if not hit.is_empty():
		point = hit.position
		normal = hit.normal
		var collider: Object = hit.collider
		if collider is BuildPiece:
			_aimed = collider
		elif collider is BuildPiece.DoorPanel:
			_aimed = collider.piece
	_pick_slot(point, normal)
	_reason = Structures.check_build(piece_id(), _slot_key, _rot, user.global_position)
	if _reason == "" and not can_afford():
		_reason = "Falta material"
	_update_ghost()


## Escolhe o encaixe a partir do ponto mirado.
func _pick_slot(point: Vector3, normal: Vector3) -> void:
	var id := piece_id()
	var slot := str(GameData.get_entry("buildings", id).get("slot", "edge"))
	var my_level := maxi(roundi(user.global_position.y / BuildPiece.HEIGHT), 0)
	# Mirando a lateral de algo: puxa o ponto para o lado de quem constrói.
	var q := point + (normal * 0.05 if absf(normal.y) < 0.7 else Vector3.ZERO)
	var i := floori(q.x / BuildPiece.CELL)
	var j := floori(q.z / BuildPiece.CELL)
	var level := my_level
	var aimed_kind := _aimed.slot_key.left(1) if _aimed else ""
	if _aimed:
		level = _aimed.level()
	match slot:
		"center":
			if int(GameData.get_entry("buildings", id).get("max_level", BuildPiece.MAX_LEVEL)) == 0:
				level = 0
			elif aimed_kind in ["x", "z", "r"]:
				level += 1  # mirando parede/escada: o teto em cima dela
			elif _aimed == null:
				level = maxi(my_level, 1)  # do chão: teto acima; de um piso: estende o piso
			else:
				level = maxi(level, 1)
			_slot_key = "c:%d:%d:%d" % [i, j, level]
			_rot = 0
		"ramp":
			if aimed_kind in ["x", "z"]:
				level = _aimed.level()
			_slot_key = "r:%d:%d:%d" % [i, j, level]
			# Sobe para a frente de quem constrói; R gira.
			_rot = wrapi(roundi(user.rotation.y / (PI * 0.5)) + turn, 0, 4)
		_:
			if _aimed and normal.y < -0.7:
				level -= 1  # olhando a parte de baixo de um teto: parede embaixo dele
			var fx := q.x / BuildPiece.CELL - i
			var fz := q.z / BuildPiece.CELL - j
			var d := [fx, 1.0 - fx, fz, 1.0 - fz]
			var side := d.find(d.min())
			match side:
				0: _slot_key = "x:%d:%d:%d" % [i, j, level]
				1: _slot_key = "x:%d:%d:%d" % [i + 1, j, level]
				2: _slot_key = "z:%d:%d:%d" % [i, j, level]
				_: _slot_key = "z:%d:%d:%d" % [i, j + 1, level]
			_rot = (1 if side < 2 else 0) + (2 if turn % 2 == 1 else 0)


func _update_ghost() -> void:
	var key := piece_id() + "/" + tier()
	if key != _ghost_id:
		_clear_ghost()
		_ghost = Node3D.new()
		add_child(_ghost)
		BuildPiece.build_visual(piece_id(), tier(), _ghost, true)
		_ghost_id = key
		for m: GeometryInstance3D in _ghost.find_children("*", "GeometryInstance3D", true, false):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.global_transform = BuildPiece.slot_transform(_slot_key, _rot)
	var mat := _mat_ok if _reason == "" else _mat_bad
	for m: GeometryInstance3D in _ghost.find_children("*", "GeometryInstance3D", true, false):
		m.material_override = mat


func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
	_ghost = null
	_ghost_id = ""


func _ghost_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat

class_name BuildPiece
extends StaticBody3D
## Peça de construção (GDD 9.1): fundação, parede, porta, piso/teto, escada.
## Dados em data/buildings/pieces.json; cada peça tem níveis de material ("tiers":
## madeira, pedra) com custo e vida próprios.
##
## Grade fixa no mundo: células de CELL × CELL metros e andares de HEIGHT metros.
## Cada peça ocupa um "encaixe" identificado por uma chave de texto:
## - "c:i:j:n" centro da célula (i, j) no andar n (fundação no 0, piso/teto do 1 em diante);
## - "r:i:j:n" escada na célula, subindo do andar n para o n+1;
## - "x:i:j:n" borda em x = i·CELL (parede/porta ao longo de z), ao lado da célula (i, j);
## - "z:i:j:n" borda em z = j·CELL (parede/porta ao longo de x).
## A posição sai só da chave + rotação, igual em todas as máquinas.
##
## Rede: o servidor cria e remove (Structures). Vida pelo componente Health (só o
## servidor muda); jogadores não danificam construções, só os inimigos.

const CELL := 3.0
const HEIGHT := 2.5
const THICKNESS := 0.2
const DOOR_WIDTH := 1.3
const DOOR_HEIGHT := 2.1
## Camada só da folha da porta: fica fora da malha de navegação, então os zumbis
## traçam caminho pela porta e, fechada, batem nela (ver zombie.gd).
const DOOR_LAYER := 64
const MAX_LEVEL := 3

const TIER_NAMES := {"wood": "madeira", "stone": "pedra", "earth": "terra"}
## Modelos do Medieval Village por material (terra = muro mágico, continua liso).
const TIER_MODELS := {
	"wood": {"wall": "Wall_Plaster_Straight", "floor": "Floor_WoodDark", "door": "Door_1_Flat"},
	"stone": {"wall": "Wall_UnevenBrick_Straight", "floor": "Floor_UnevenBrick", "door": "Door_2_Flat"},
}
const TIER_COLORS := {"wood": Color(0.56, 0.39, 0.23), "stone": Color(0.56, 0.56, 0.54), "earth": Color(0.4, 0.31, 0.22)}

var piece_id := "wall"
var tier := "wood"
var slot_key := "x:0:0:0"
var rot := 0
var data: Dictionary = {}
var health: Health
## Porta aberta (só peças com "door").
var open := false

var _hinge: Node3D


func _ready() -> void:
	data = GameData.get_entry("buildings", piece_id)
	collision_layer = 8  # construções
	collision_mask = 0
	add_to_group("navmesh_source")
	add_to_group("build_pieces")
	health = Health.new()
	health.name = "Health"
	health.ignore_group = &"player"
	add_child(health)
	health.configure(max_health())
	health.died.connect(_on_died)
	_build()
	Structures.register_piece(self)


func _exit_tree() -> void:
	Structures.unregister_piece(self)


func max_health() -> float:
	return float(data.get("tiers", {}).get(tier, {}).get("health", 300.0))


func level() -> int:
	return int(slot_key.split(":")[3])


func is_door() -> bool:
	return data.get("door", false)


## Bloqueia a passagem (parede, porta): o que os zumbis atacam quando ficam presos.
func is_blocking() -> bool:
	return data.get("blocking", false) and not (is_door() and open)


func display_name() -> String:
	return tr("%s de %s") % [data.get("name", piece_id), tr(TIER_NAMES.get(tier, tier))]


## Ponto da peça mais perto de `from` (para o zumbi chegar perto e bater). Em
## parede/porta fica longe das pontas (não bate pela quina); na porta, na folha.
func nearest_point(from: Vector3) -> Vector3:
	var center := Vector3(0, HEIGHT * 0.5, 0)
	var half := Vector3(CELL * 0.5 - 0.5, HEIGHT * 0.5, THICKNESS * 0.5)
	if is_door():
		half.x = DOOR_WIDTH * 0.5 - 0.2
	if str(data.get("slot", "edge")) != "edge":
		center = Vector3(0, -0.1, 0)
		half = Vector3(CELL * 0.5, 0.15, CELL * 0.5)
	var local := global_transform.affine_inverse() * from
	local = (local - center).clamp(-half, half) + center
	return global_transform * local


# --- Porta ----------------------------------------------------------------------------

func has_prompt() -> bool:
	return is_door()


func get_prompt() -> String:
	return tr("[E] %s porta") % (tr("Fechar") if open else tr("Abrir")) if is_door() else ""


func interact(player: Node3D) -> void:
	if not is_door():
		return
	if multiplayer.is_server():
		_toggle(player)
	elif Network.is_online():
		_request_toggle.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_toggle() -> void:
	var sender := multiplayer.get_remote_sender_id()
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			_toggle(p)


func _toggle(player: Node3D) -> void:
	if player.global_position.distance_to(global_position) > 4.5:
		return
	_set_open(not open)
	if Network.is_online():
		_sync_open.rpc(open)


@rpc("authority", "call_remote", "reliable")
func _sync_open(value: bool) -> void:
	_set_open(value)


func _set_open(value: bool) -> void:
	if value != open:
		Sfx.play("door", global_position + Vector3.UP, -4.0)
	open = value
	if _hinge:
		var tw := create_tween()
		tw.tween_property(_hinge, "rotation:y", -PI * 0.48 if open else 0.0, 0.35) \
			.set_trans(Tween.TRANS_SINE)


## Servidor: manda vida e porta a quem acabou de entrar na partida.
func send_state_to(peer: int) -> void:
	if health.current < health.max_health:
		health._sync_state.rpc_id(peer, health.current, health.is_dead, health.max_health, 0.0, NodePath())
	if open:
		_sync_open.rpc_id(peer, true)


func _on_died(_source: Node) -> void:
	if multiplayer.is_server():
		Structures.piece_destroyed(self)


# --- Geometria (compartilhada com a prévia do modo construção) ------------------------

## Posição/rotação de um encaixe. rot = quartos de volta (0-3).
## Altura do chão da célula (i, j) (o mundo informa; arena = 0). O andar n de uma peça
## fica em base + n · HEIGHT: a grade acompanha o relevo, célula por célula.
static var base_height_func: Callable


static func cell_base(i: int, j: int) -> float:
	return float(base_height_func.call(i, j)) if base_height_func.is_valid() else 0.0


## Base de um encaixe: célula (c, r) ou a mais alta das duas células de uma borda (x, z).
static func slot_base(kind: String, i: int, j: int) -> float:
	match kind:
		"x": return maxf(cell_base(i - 1, j), cell_base(i, j))
		"z": return maxf(cell_base(i, j - 1), cell_base(i, j))
	return cell_base(i, j)


## Andar em que fica a altura y na célula (i, j).
static func level_at(i: int, j: int, y: float) -> int:
	return maxi(roundi((y - cell_base(i, j)) / HEIGHT), 0)


static func slot_transform(key: String, rot_steps: int) -> Transform3D:
	var p := key.split(":")
	var i := int(p[1])
	var j := int(p[2])
	var y := slot_base(p[0], i, j) + int(p[3]) * HEIGHT
	var pos := Vector3((i + 0.5) * CELL, y, (j + 0.5) * CELL)
	match p[0]:
		"x": pos = Vector3(i * CELL, y, (j + 0.5) * CELL)
		"z": pos = Vector3((i + 0.5) * CELL, y, j * CELL)
	return Transform3D(Basis(Vector3.UP, rot_steps * PI * 0.5), pos)


## Partes sólidas da peça (sem a folha da porta): [tamanho, posição, inclinação em x].
static func parts(id: String) -> Array:
	id = str(GameData.get_entry("buildings", id).get("shape", id))
	match id:
		"foundation":
			return [[Vector3(CELL, 2.6, CELL), Vector3(0, -1.25, 0), 0.0]]  # topo a 5 cm do chão; desce até o chão em ladeira
		"floor":
			return [[Vector3(CELL, 0.2, CELL), Vector3(0, -0.1, 0), 0.0]]
		"doorway":
			var side := (CELL - DOOR_WIDTH) * 0.5
			return [
				[Vector3(side, HEIGHT, THICKNESS), Vector3(-(DOOR_WIDTH + side) * 0.5, HEIGHT * 0.5, 0), 0.0],
				[Vector3(side, HEIGHT, THICKNESS), Vector3((DOOR_WIDTH + side) * 0.5, HEIGHT * 0.5, 0), 0.0],
				[Vector3(DOOR_WIDTH, HEIGHT - DOOR_HEIGHT, THICKNESS), Vector3(0, (HEIGHT + DOOR_HEIGHT) * 0.5, 0), 0.0],
			]
		"stairs":
			# Rampa subindo para -z local (frente de quem constrói), 2,5 m em 3 m (~40°).
			var tilt := atan2(HEIGHT, CELL)
			var normal := Vector3(0, cos(tilt), sin(tilt))
			return [[Vector3(CELL - 0.2, 0.2, sqrt(CELL * CELL + HEIGHT * HEIGHT)),
				Vector3(0, HEIGHT * 0.5, 0) - normal * 0.1, tilt]]
		_:  # parede
			return [[Vector3(CELL, HEIGHT, THICKNESS), Vector3(0, HEIGHT * 0.5, 0), 0.0]]


static func part_transform(part: Array) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, float(part[2])), part[1])


## Monta o visual da peça em `parent` (peça real ou prévia). with_door: inclui a
## folha da porta fechada (a prévia usa; a peça real cria a folha móvel à parte).
static func build_visual(id: String, tier_id: String, parent: Node3D, with_door := false) -> void:
	var color: Color = TIER_COLORS.get(tier_id, Color.GRAY)
	var dark := color.darkened(0.3)
	id = str(GameData.get_entry("buildings", id).get("shape", id))
	if id == "stairs":
		var steps := 8
		for k in steps:
			var h := HEIGHT * (k + 1) / steps
			var depth := CELL / steps
			parent.add_child(Weapon.box(Vector3(CELL - 0.2, h, depth), color if k % 2 == 0 else color.darkened(0.08),
				Vector3(0, h * 0.5, CELL * 0.5 - depth * (k + 0.5))))
		return
	var models: Dictionary = TIER_MODELS.get(tier_id, {})
	var is_edge := str(GameData.get_entry("buildings", id).get("slot", "")) == "edge"
	if is_edge and models.has("wall"):
		# Parede/portal: cada bloco sólido vira um pedaço de parede do Medieval Village
		# esticado para a mesma caixa (o visual bate com a colisão, inclusive o vão da porta).
		for part: Array in parts(id):
			var wall := ModelKit.fit_box(ModelKit.VILLAGE + str(models.wall) + ".gltf", part[0], Vector3.ZERO)
			if wall:
				wall.transform = part_transform(part) * wall.transform
				parent.add_child(wall)
		if with_door and id == "doorway":
			parent.add_child(door_mesh(tier_id, Vector3(0, DOOR_HEIGHT * 0.5, 0)))
		return
	for part: Array in parts(id):
		var mesh := Weapon.box(part[0], color)
		mesh.transform = part_transform(part)
		parent.add_child(mesh)
	if models.has("floor") and id in ["foundation", "floor"]:
		# Piso da vila por cima (tábuas na madeira, pedras na pedra).
		var top := 0.05 if id == "foundation" else 0.0
		var floor_model := ModelKit.fit_box(ModelKit.VILLAGE + str(models.floor) + ".gltf", Vector3(CELL, 0.02, CELL), Vector3(0, top + 0.012, 0))
		if floor_model:
			parent.add_child(floor_model)
		return
	if is_edge:
		# Pilares nas pontas (madeira) ou cinta no topo (pedra): dá para ler a grade.
		for x in [-CELL * 0.5 + 0.08, CELL * 0.5 - 0.08]:
			parent.add_child(Weapon.box(Vector3(0.16, HEIGHT, THICKNESS + 0.04), dark, Vector3(x, HEIGHT * 0.5, 0)))
		parent.add_child(Weapon.box(Vector3(CELL, 0.12, THICKNESS + 0.04), dark, Vector3(0, HEIGHT - 0.06, 0)))
	elif id == "foundation":
		parent.add_child(Weapon.box(Vector3(CELL - 0.3, 0.02, CELL - 0.3), color.lightened(0.08), Vector3(0, 0.055, 0)))
	if with_door and id == "doorway":
		parent.add_child(door_mesh(tier_id, Vector3(0, DOOR_HEIGHT * 0.5, 0)))


static func door_mesh(tier_id: String, pos: Vector3) -> MeshInstance3D:
	var color: Color = TIER_COLORS.get(tier_id, Color.GRAY)
	var models: Dictionary = TIER_MODELS.get(tier_id, {})
	if models.has("door"):
		# Folha da porta do Medieval Village (com a mesma caixa da porta de antes).
		var holder := MeshInstance3D.new()
		holder.position = pos
		var door := ModelKit.fit_box(ModelKit.VILLAGE + str(models.door) + ".gltf", Vector3(DOOR_WIDTH - 0.04, DOOR_HEIGHT - 0.02, 0.1), Vector3.ZERO)
		if door:
			holder.add_child(door)
			return holder
		holder.free()
	var mesh := Weapon.box(Vector3(DOOR_WIDTH - 0.04, DOOR_HEIGHT - 0.02, 0.08), color.darkened(0.45), pos)
	mesh.add_child(Weapon.box(Vector3(0.06, 0.06, 0.16), Color(0.7, 0.65, 0.4), Vector3(DOOR_WIDTH * 0.5 - 0.18, 0, 0)))
	return mesh


func _build() -> void:
	build_visual(piece_id, tier, self)
	# Parede do térreo em chão inclinado: rodapé até o chão do lado mais baixo.
	if slot_key.left(1) in ["x", "z"] and level() == 0 and tier in TIER_COLORS:
		var plinth := Weapon.box(Vector3(CELL, 1.0, THICKNESS + 0.06), TIER_COLORS[tier].darkened(0.35), Vector3(0, -0.5, 0))
		add_child(plinth)
	for part: Array in parts(piece_id):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = part[0]
		shape.shape = box
		shape.transform = part_transform(part)
		add_child(shape)
	if is_door():
		_hinge = Node3D.new()
		_hinge.position = Vector3(-DOOR_WIDTH * 0.5, 0, 0)
		add_child(_hinge)
		var panel := DoorPanel.new()
		panel.piece = self
		panel.collision_layer = DOOR_LAYER
		panel.collision_mask = 0
		panel.position = Vector3(DOOR_WIDTH * 0.5, DOOR_HEIGHT * 0.5, 0)
		_hinge.add_child(panel)
		panel.add_child(door_mesh(tier, Vector3.ZERO))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(DOOR_WIDTH - 0.04, DOOR_HEIGHT - 0.02, 0.08)
		shape.shape = box
		panel.add_child(shape)
	for m: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		m.visibility_range_end = 170.0


## Folha da porta: repassa E e o aviso para a peça.
class DoorPanel extends StaticBody3D:
	var piece: BuildPiece

	func has_prompt() -> bool:
		return true

	func get_prompt() -> String:
		return piece.get_prompt()

	func interact(player: Node3D) -> void:
		piece.interact(player)

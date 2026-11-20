class_name NatureDecor
extends Node3D
## Vegetação decorativa de um bloco do mundo (grama, arbustos, pedrinhas), com os
## modelos do KayKit Forest Nature Pack (NatureKit). Só visual: sem colisão, sem rede.
##
## compute() roda numa thread (só usa o ruído do mundo e a lista de lugares) e devolve,
## por modelo, as transformações; build() monta um MultiMeshInstance3D por modelo (um
## desenho para todas as cópias). Construir em cima apaga os enfeites daquele pedaço.

const STEP := 2.0

## Modelo: [escala mín, escala máx, distância de visão] (KayKit Forest Nature Pack). As
## escalas saem da altura-alvo de cada família (grama 0,3-0,55 m, arbustos 0,4-0,8 m,
## pedrinhas 0,1-0,25 m) dividida pela altura real do modelo: as variantes do kit têm
## tamanhos bem diferentes.
const MODELS := {
	"Grass_1_A_Color1": [0.56, 0.83, 45.0], "Grass_1_B_Color1": [0.62, 0.94, 45.0], "Grass_1_C_Color1": [0.55, 0.82, 45.0],
	"Grass_1_D_Color1": [0.55, 0.82, 45.0], "Grass_2_A_Color1": [0.39, 0.62, 50.0], "Grass_2_B_Color1": [0.39, 0.62, 50.0],
	"Grass_2_C_Color1": [0.39, 0.62, 50.0], "Grass_2_D_Color1": [0.39, 0.62, 50.0], "Bush_1_A_Color1": [1.79, 3.13, 60.0],
	"Bush_1_B_Color1": [0.85, 1.48, 60.0], "Bush_1_C_Color1": [0.50, 0.88, 60.0], "Bush_1_D_Color1": [0.41, 0.72, 60.0],
	"Bush_1_E_Color1": [0.50, 0.88, 60.0], "Bush_1_F_Color1": [0.41, 0.72, 60.0], "Bush_1_G_Color1": [0.41, 0.72, 60.0],
	"Bush_2_A_Color1": [0.85, 1.52, 60.0], "Bush_2_B_Color1": [0.52, 0.93, 60.0], "Bush_2_C_Color1": [0.34, 0.61, 60.0],
	"Bush_2_D_Color1": [0.52, 0.93, 60.0], "Bush_2_E_Color1": [0.34, 0.60, 60.0], "Bush_2_F_Color1": [0.25, 0.45, 60.0],
	"Bush_3_A_Color1": [0.87, 1.52, 60.0], "Bush_3_B_Color1": [0.51, 0.90, 60.0], "Bush_3_C_Color1": [0.36, 0.62, 60.0],
	"Bush_4_A_Color1": [0.92, 1.73, 60.0], "Bush_4_B_Color1": [0.54, 1.01, 60.0], "Bush_4_C_Color1": [0.31, 0.58, 60.0],
	"Bush_4_D_Color1": [0.54, 1.01, 60.0], "Bush_4_E_Color1": [0.31, 0.58, 60.0], "Bush_4_F_Color1": [0.31, 0.58, 60.0],
	"Rock_1_A_Color1": [0.19, 0.46, 30.0], "Rock_1_B_Color1": [0.19, 0.46, 30.0], "Rock_1_C_Color1": [0.19, 0.46, 30.0],
	"Rock_1_D_Color1": [0.09, 0.22, 30.0], "Rock_1_E_Color1": [0.09, 0.22, 30.0], "Rock_1_F_Color1": [0.09, 0.22, 30.0],
	"Rock_1_G_Color1": [0.05, 0.13, 30.0], "Rock_1_H_Color1": [0.05, 0.13, 30.0],
}

## Por bioma: chance de cada enfeite em cada ponto. Nomes terminados em "*" sorteiam
## entre os modelos que começam assim (Grass_1_* = Grass_1_A..D).
const DECOR := {
	"plains": {"Grass_1_*": 0.3, "Grass_2_*": 0.08, "Bush_1_*": 0.015, "Rock_1_*": 0.008},
	"forest": {"Grass_1_*": 0.14, "Grass_2_*": 0.08, "Bush_2_*": 0.05, "Bush_3_*": 0.03, "Rock_1_*": 0.01},
	"swamp": {"Grass_2_*": 0.25, "Bush_4_*": 0.05, "Grass_1_*": 0.05},
	"lakeside": {"Grass_2_*": 0.15, "Grass_1_*": 0.1, "Rock_1_*": 0.02},
	"mountain": {"Rock_1_*": 0.05, "Grass_1_*": 0.04},
	"tundra": {"Grass_1_*": 0.02, "Rock_1_*": 0.01},
	"contaminated": {"Grass_2_*": 0.05, "Bush_4_*": 0.03},
}

## modelo → [MultiMeshInstance3D, PackedVector3Array posições locais]
var _batches := {}


## Thread: enfeites do bloco c (posições locais ao canto do bloco).
static func compute(world: Node, c: Vector2i, near_pois: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(world.world_seed), c.x, c.y, 31])
	var variants := {}  # "Grass_1_*" -> [Grass_1_A_Color1, ...]
	for table: Dictionary in DECOR.values():
		for key: String in table:
			if key.ends_with("*") and not variants.has(key):
				var prefix := key.trim_suffix("*")
				variants[key] = MODELS.keys().filter(func(m: String) -> bool: return m.begins_with(prefix))
	var chunk_size: float = world.CHUNK
	var ox := c.x * chunk_size
	var oz := c.y * chunk_size
	var cells := int(chunk_size / STEP)
	var out := {}
	for cj in cells:
		for ci in cells:
			var lx := (ci + rng.randf()) * STEP
			var lz := (cj + rng.randf()) * STEP
			var roll := rng.randf()
			var pick := rng.randi()
			var spin := rng.randf() * TAU
			var size_t := rng.randf()
			var x := ox + lx
			var z := oz + lz
			var h: float = world._height_with(x, z, near_pois)
			var table: Dictionary = DECOR.get(world._biome_raw(x, z, world._raw_height(x, z)), {})
			if table.is_empty():
				continue
			var model := ""
			for key: String in table:
				roll -= float(table[key])
				if roll < 0.0:
					model = key
					break
			if model == "" or world._in_poi_list(x, z, near_pois):
				continue
			if variants.has(model):
				var list: Array = variants[model]
				model = list[pick % list.size()]
			var span: Array = MODELS[model]
			var s := lerpf(float(span[0]), float(span[1]), size_t)
			if not out.has(model):
				out[model] = []
			out[model].append(Transform3D(Basis(Vector3.UP, spin).scaled(Vector3.ONE * s), Vector3(lx, h - 0.03, lz)))
	return out


## Monta os enfeites calculados (thread principal).
static func build(batches: Dictionary) -> NatureDecor:
	var node := NatureDecor.new()
	node.name = "Decor"
	for model: String in batches:
		var mesh := NatureKit.mesh(model)
		if mesh == null:
			continue
		var transforms: Array = batches[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		var points := PackedVector3Array()
		for k in transforms.size():
			mm.set_instance_transform(k, transforms[k])
			points.append(transforms[k].origin)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = float(MODELS[model][2])
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		node.add_child(mmi)
		node._batches[model] = [mmi, points]
	return node


func _ready() -> void:
	var structures := get_tree().get_first_node_in_group("world").get_node_or_null(^"Structures") if get_tree().get_first_node_in_group("world") else null
	if structures:
		structures.child_entered_tree.connect(func(piece: Node) -> void: _clear_under.call_deferred(piece))
		for piece in structures.get_children():
			_clear_under(piece)


## Peça construída no chão: some com os enfeites embaixo dela (grama não atravessa o piso).
func _clear_under(piece: Node) -> void:
	if not is_instance_valid(piece) or not piece is Node3D or not is_inside_tree():
		return
	var p: Vector3 = (piece as Node3D).global_position - global_position
	var reach := BuildPiece.CELL * 0.5 + 0.3
	if p.x < -reach or p.z < -reach or p.x > 64.0 + reach or p.z > 64.0 + reach:
		return
	for model: String in _batches:
		var mm: MultiMesh = _batches[model][0].multimesh
		var points: PackedVector3Array = _batches[model][1]
		for k in points.size():
			if absf(points[k].x - p.x) < reach and absf(points[k].z - p.z) < reach and absf(points[k].y - p.y) < 2.0:
				mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), points[k]))

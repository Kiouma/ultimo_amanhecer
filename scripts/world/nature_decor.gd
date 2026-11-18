class_name NatureDecor
extends Node3D
## Vegetação decorativa do mundo (grama, flores, samambaias, cogumelos, pedrinhas), com
## os modelos do Stylized Nature MegaKit (NatureKit). Só visual: sem colisão, sem rede.
##
## Gerada a partir da semente do mundo: todas as máquinas montam a mesma coisa sozinhas.
## O mapa é dividido em blocos de CHUNK metros; em cada bloco, cada modelo vira um
## MultiMeshInstance3D (um desenho para todas as cópias) que some de longe.
## Pontos de STEP em STEP metros (com sorteio dentro da célula) escolhem um enfeite
## conforme o bioma (DECOR). Construir em cima apaga os enfeites daquele pedaço.

const World := preload("res://scripts/world/world.gd")
const CHUNK := 20.0
const STEP := 2.0

## Modelo: [escala mín, escala máx, distância de visão].
const MODELS := {
	"Grass_Common_Short": [0.35, 0.55, 45.0], "Grass_Common_Tall": [0.35, 0.5, 50.0],
	"Grass_Wispy_Short": [0.4, 0.6, 45.0], "Grass_Wispy_Tall": [0.4, 0.6, 50.0],
	"Flower_3_Group": [0.28, 0.38, 50.0], "Flower_4_Group": [0.25, 0.35, 50.0],
	"Flower_3_Single": [0.28, 0.38, 40.0], "Flower_4_Single": [0.25, 0.35, 40.0],
	"Petal_1": [0.7, 1.0, 30.0], "Petal_2": [0.7, 1.0, 30.0], "Petal_3": [0.7, 1.0, 30.0],
	"Petal_4": [0.8, 1.1, 30.0], "Petal_5": [0.6, 0.9, 30.0],
	"Clover_1": [0.3, 0.42, 40.0], "Clover_2": [0.3, 0.42, 40.0],
	"Fern_1": [0.16, 0.24, 60.0], "Plant_1": [0.4, 0.6, 50.0], "Plant_1_Big": [0.3, 0.42, 70.0],
	"Plant_7": [0.6, 0.9, 40.0], "Plant_7_Big": [0.6, 0.9, 40.0],
	"Mushroom_Common": [0.6, 1.0, 35.0], "Mushroom_Laetiporus": [0.5, 0.8, 35.0],
	"Pebble_Round_1": [0.8, 1.5, 30.0], "Pebble_Round_2": [0.8, 1.5, 30.0], "Pebble_Round_3": [0.8, 1.5, 30.0],
	"Pebble_Round_4": [0.8, 1.5, 30.0], "Pebble_Round_5": [0.8, 1.5, 30.0],
	"Pebble_Square_1": [0.9, 1.6, 30.0], "Pebble_Square_2": [0.9, 1.6, 30.0], "Pebble_Square_3": [0.9, 1.6, 30.0],
	"Pebble_Square_4": [0.9, 1.6, 30.0], "Pebble_Square_5": [0.9, 1.6, 30.0], "Pebble_Square_6": [0.9, 1.6, 30.0],
	"RockPath_Square_Small_1": [0.8, 1.2, 50.0], "RockPath_Square_Small_2": [0.8, 1.2, 50.0],
	"RockPath_Round_Small_1": [0.8, 1.2, 50.0], "RockPath_Round_Small_2": [0.8, 1.2, 50.0],
}

## Por bioma: chance de cada enfeite em cada ponto. Nomes terminados em "*" sorteiam
## entre as variantes (Pebble_Round_* = Pebble_Round_1..5).
const DECOR := {
	"plains": {"Grass_Common_Short": 0.3, "Grass_Common_Tall": 0.06, "Grass_Wispy_Short": 0.08,
		"Flower_3_Group": 0.025, "Flower_4_Group": 0.025, "Flower_3_Single": 0.02, "Flower_4_Single": 0.02,
		"Petal_*": 0.03, "Clover_*": 0.03},
	"forest": {"Grass_Common_Short": 0.14, "Grass_Wispy_Short": 0.08, "Fern_1": 0.08, "Plant_1": 0.04,
		"Plant_7": 0.04, "Plant_1_Big": 0.01, "Mushroom_Common": 0.03, "Clover_*": 0.05},
	"swamp": {"Grass_Wispy_Tall": 0.2, "Grass_Common_Tall": 0.1, "Fern_1": 0.06, "Plant_7_Big": 0.04,
		"Mushroom_Laetiporus": 0.02, "Mushroom_Common": 0.03},
	"lakeside": {"Grass_Wispy_Tall": 0.12, "Grass_Common_Short": 0.12,
		"Plant_7": 0.03, "Flower_3_Single": 0.02},
	"mountain": {"RockPath_Square_Small_*": 0.04, "Grass_Wispy_Short": 0.05},
	"tundra": {"Grass_Wispy_Short": 0.025},
	"contaminated": {"Mushroom_Laetiporus": 0.03, "Mushroom_Common": 0.05,
		"Grass_Wispy_Short": 0.05},
}

## Bloco (Vector2i) -> {modelo: [MultiMeshInstance3D, PackedVector3Array posições]}.
var _chunks := {}
var _world: Node


func _init(world: Node) -> void:
	_world = world
	name = "NatureDecor"


func _ready() -> void:
	_generate(int(_world.world_seed))
	var structures := _world.get_node_or_null(^"Structures")
	if structures:
		structures.child_entered_tree.connect(func(piece: Node) -> void: _clear_under.call_deferred(piece))


func _generate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 31
	var variants := {}  # "Pebble_Round_*" -> [Pebble_Round_1, ...]
	for key: String in MODELS:
		var base := key.rstrip("0123456789")
		if base != key and base.ends_with("_"):
			if not variants.has(base + "*"):
				variants[base + "*"] = []
			variants[base + "*"].append(key)
	# Pontos agrupados por bloco e modelo: {Vector2i: {modelo: [Transform3D...]}}
	var placed := {}
	var half := World.HALF
	var cells := int(World.SIZE / STEP)
	for cj in cells:
		for ci in cells:
			var x := -half + (ci + rng.randf()) * STEP
			var z := -half + (cj + rng.randf()) * STEP
			var roll := rng.randf()
			var pick := rng.randi()
			var spin := rng.randf() * TAU
			var size_t := rng.randf()
			var table: Dictionary = DECOR.get(_world.biome_at(x, z), {})
			if table.is_empty():
				continue
			var model := ""
			for key: String in table:
				roll -= float(table[key])
				if roll < 0.0:
					model = key
					break
			if model == "" or _world._in_poi(x, z):
				continue
			if variants.has(model):
				var list: Array = variants[model]
				model = list[pick % list.size()]
			var span: Array = MODELS[model]
			var s := lerpf(float(span[0]), float(span[1]), size_t)
			var basis := Basis(Vector3.UP, spin).scaled(Vector3.ONE * s)
			var chunk := Vector2i(floori((x + half) / CHUNK), floori((z + half) / CHUNK))
			if not placed.has(chunk):
				placed[chunk] = {}
			if not placed[chunk].has(model):
				placed[chunk][model] = []
			placed[chunk][model].append(Transform3D(basis, Vector3(x, _world.ground_height(x, z) - 0.03, z)))
	for chunk: Vector2i in placed:
		_chunks[chunk] = {}
		for model: String in placed[chunk]:
			_build_batch(chunk, model, placed[chunk][model])


func _build_batch(chunk: Vector2i, model: String, transforms: Array) -> void:
	var mesh := NatureKit.mesh(model)
	if mesh == null:
		return
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
	add_child(mmi)
	_chunks[chunk][model] = [mmi, points]


## Peça construída no chão: some com os enfeites embaixo dela (grama não atravessa o piso).
func _clear_under(piece: Node) -> void:
	if not is_instance_valid(piece) or not piece is Node3D:
		return
	var p: Vector3 = (piece as Node3D).global_position
	if p.y > 1.5:
		return  # andar de cima
	var reach := BuildPiece.CELL * 0.5 + 0.3
	var half := World.HALF
	var c0 := Vector2i(floori((p.x - reach + half) / CHUNK), floori((p.z - reach + half) / CHUNK))
	var c1 := Vector2i(floori((p.x + reach + half) / CHUNK), floori((p.z + reach + half) / CHUNK))
	for cj in range(c0.y, c1.y + 1):
		for ci in range(c0.x, c1.x + 1):
			var batches: Dictionary = _chunks.get(Vector2i(ci, cj), {})
			for model: String in batches:
				var mm: MultiMesh = batches[model][0].multimesh
				var points: PackedVector3Array = batches[model][1]
				for k in points.size():
					if absf(points[k].x - p.x) < reach and absf(points[k].z - p.z) < reach:
						mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ZERO), points[k]))

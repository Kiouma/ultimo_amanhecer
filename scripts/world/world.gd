extends "res://scripts/world/arena.gd"
## Mundo aberto (GDD 10), gerado a partir de uma semente (world_seed).
## O host sorteia a semente; ela chega aos clientes junto com a cena (SeedSync) e
## todos geram o mesmo terreno. Recursos, saque e zumbis são criados pelo servidor
## e replicados pelos spawners da arena.
##
## Biomas: planície (centro, onde se nasce), floresta, pântano, lagos (com margem),
## montanhas (borda do mapa, relevo) e uma zona contaminada (cristais arcanos, mais
## perigo). O chão de planície/floresta/pântano/margem fica em y = 0 (dá para construir);
## relevo só nas montanhas e no fundo dos lagos.
##
## Malha de navegação em blocos de TILE metros: construir ou derrubar algo refaz só o
## bloco daquele lugar.

const SIZE := 320.0
const HALF := SIZE * 0.5
## Distância entre vértices do terreno.
const STEP := 2.0
const MOUNTAIN_BAND := 22.0
const MOUNTAIN_HEIGHT := 16.0
const SPAWN_SAFE := 22.0
const WATER_LEVEL := -0.55
const TILE := 64.0

const BIOME_COLORS := {
	"plains": Color(0.36, 0.45, 0.27), "forest": Color(0.22, 0.34, 0.19),
	"swamp": Color(0.27, 0.3, 0.2), "lake": Color(0.3, 0.28, 0.2), "lakeside": Color(0.5, 0.47, 0.33),
	"mountain": Color(0.42, 0.41, 0.4), "contaminated": Color(0.33, 0.27, 0.36),
}
const BIOME_NAMES := {
	"plains": "Planície", "forest": "Floresta", "swamp": "Pântano", "lake": "Lago",
	"lakeside": "Margem do lago", "mountain": "Montanhas", "contaminated": "Zona contaminada",
}
## Chance por célula de 8 m de cada recurso, por bioma.
const DENSITY := {
	"forest": {"tree": 0.55, "berry_bush": 0.05, "branches": 0.08, "nest": 0.05, "rock": 0.03},
	"plains": {"tree": 0.05, "berry_bush": 0.07, "branches": 0.03, "rock": 0.03, "nest": 0.01},
	"swamp": {"tree": 0.1, "herb_patch": 0.14, "branches": 0.06},
	"lakeside": {"tree": 0.07, "berry_bush": 0.05, "rock": 0.03, "nest": 0.03},
	"mountain": {"rock": 0.15, "tree": 0.04},
	"contaminated": {"crystal": 0.2, "rock": 0.05, "tree": 0.02},
}
const CELL_SIZE := 8.0

## Semente do mundo (vem do host pela SeedSync antes do _ready).
@export var world_seed := 0

var lakes: Array = []  # [Vector2 centro, raio]
var contaminated_center := Vector2.ZERO
var contaminated_radius := 36.0

var _forest_noise := FastNoiseLite.new()
var _swamp_noise := FastNoiseLite.new()
var _hill_noise := FastNoiseLite.new()
var _tiles: Array[NavigationRegion3D] = []
var _dirty_tiles := {}


func _setup_level() -> void:
	if world_seed == 0:
		world_seed = randi_range(1, 2147483646)  # host (ou solo) sorteia
	add_to_group("world")
	_plan()
	_build_terrain()
	_build_water()


static func find(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group("world")


# --- Geração (determinística a partir da semente) ------------------------------------

func _plan() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	for n: FastNoiseLite in [_forest_noise, _swamp_noise, _hill_noise]:
		n.seed = rng.randi()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest_noise.frequency = 0.012
	_swamp_noise.frequency = 0.009
	_hill_noise.frequency = 0.04
	var angle := rng.randf() * TAU
	contaminated_center = Vector2(cos(angle), sin(angle)) * rng.randf_range(90.0, 105.0)
	lakes.clear()
	var tries := 0
	while lakes.size() < 5 and tries < 200:
		tries += 1
		var c := Vector2(rng.randf_range(-HALF + 50, HALF - 50), rng.randf_range(-HALF + 50, HALF - 50))
		var r := rng.randf_range(9.0, 17.0)
		if c.length() < SPAWN_SAFE + r + 12 or c.distance_to(contaminated_center) < contaminated_radius + r + 10:
			continue
		var ok := true
		for lake: Array in lakes:
			if c.distance_to(lake[0]) < r + float(lake[1]) + 25.0:
				ok = false
		if ok:
			lakes.append([c, r])


func biome_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	if maxf(absf(x), absf(z)) > HALF - MOUNTAIN_BAND:
		return "mountain"
	if p.length() < SPAWN_SAFE:
		return "plains"
	if p.distance_to(contaminated_center) < contaminated_radius:
		return "contaminated"
	for lake: Array in lakes:
		var d := p.distance_to(lake[0])
		if d < float(lake[1]):
			return "lake"
		if d < float(lake[1]) + 12.0:
			return "lakeside"
	if _swamp_noise.get_noise_2d(x, z) > 0.32:
		return "swamp"
	if _forest_noise.get_noise_2d(x, z) > -0.05:
		return "forest"
	return "plains"


## Altura do terreno. Plano (0) fora das montanhas e do fundo dos lagos.
func ground_height(x: float, z: float) -> float:
	var edge := maxf(absf(x), absf(z)) - (HALF - MOUNTAIN_BAND)
	if edge > 0.0:
		var t := smoothstep(0.0, MOUNTAIN_BAND, edge)
		return t * MOUNTAIN_HEIGHT + t * (_hill_noise.get_noise_2d(x, z) + 1.0) * 3.0
	var p := Vector2(x, z)
	for lake: Array in lakes:
		var d := p.distance_to(lake[0])
		var r := float(lake[1])
		if d < r:
			return -1.6 * smoothstep(r, r * 0.6, d)
	return 0.0


# --- Terreno ----------------------------------------------------------------------------

func _build_terrain() -> void:
	var n := int(SIZE / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var x := -HALF + i * STEP
			var z := -HALF + j * STEP
			var h := ground_height(x, z)
			heights[j * n + i] = h
	for j in n - 1:
		for i in n - 1:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			for v: Array in quad:
				var x := -HALF + int(v[0]) * STEP
				var z := -HALF + int(v[1]) * STEP
				var color: Color = BIOME_COLORS.get(biome_at(x, z), Color.GREEN)
				color = color.lightened(_hill_noise.get_noise_2d(x * 3.0, z * 3.0) * 0.06)
				st.set_color(color)
				st.add_vertex(Vector3(x, heights[int(v[1]) * n + int(v[0])], z))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.collision_layer = 1
	terrain.collision_mask = 0
	terrain.add_to_group("navmesh_source")
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = mat
	terrain.add_child(view)
	# Colisão: mapa de alturas com escala 2 (uniforme): alturas guardadas pela metade.
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	var half_heights := PackedFloat32Array()
	half_heights.resize(heights.size())
	for k in heights.size():
		half_heights[k] = heights[k] / STEP
	shape.map_data = half_heights
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3.ONE * STEP
	terrain.add_child(col)
	add_child(terrain)


func _build_water() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.3, 0.38, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.08
	for k in lakes.size():
		var lake: Array = lakes[k]
		var c: Vector2 = lake[0]
		var r := float(lake[1])
		var water := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = r
		disc.bottom_radius = r
		disc.height = 0.02
		disc.radial_segments = 48
		water.mesh = disc
		water.material_override = mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water.position = Vector3(c.x, WATER_LEVEL, c.y)
		add_child(water)
		var source := WaterSource.new()
		source.name = "Lake%d" % k
		source.show_visual = false
		source.radius = r * 0.9
		source.position = Vector3(c.x, WATER_LEVEL - 0.05, c.y)
		add_child(source)


# --- Navegação em blocos ------------------------------------------------------------------

func _bake_navigation() -> void:
	var base: NavigationMesh = nav_region.navigation_mesh
	var count := int(SIZE / TILE)
	for tj in count:
		for ti in count:
			var region := NavigationRegion3D.new()
			var nm: NavigationMesh = base.duplicate()
			var origin := Vector3(-HALF + ti * TILE, -10.0, -HALF + tj * TILE)
			nm.filter_baking_aabb = AABB(origin, Vector3(TILE, 50.0, TILE))
			nm.border_size = 1.0
			region.navigation_mesh = nm
			add_child(region)
			_tiles.append(region)
	if not multiplayer.is_server():
		return  # só o servidor anda com zumbis
	for region in _tiles:
		region.bake_navigation_mesh(true)


## Refaz só os blocos perto de `at` (INF = todos).
func _queue_rebake(at := Vector3.INF) -> void:
	for k in _tiles.size():
		var box: AABB = _tiles[k].navigation_mesh.filter_baking_aabb.grow(4.0)
		if at == Vector3.INF or box.has_point(Vector3(at.x, 0.0, at.z)):
			_dirty_tiles[k] = true


func _process(_delta: float) -> void:
	for k: int in _dirty_tiles.keys():
		if not _tiles[k].is_baking():
			_dirty_tiles.erase(k)
			_tiles[k].bake_navigation_mesh(true)


# --- Conteúdo (servidor) ---------------------------------------------------------------

func _scatter_resources() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1
	var cells := int(SIZE / CELL_SIZE)
	for cj in cells:
		for ci in cells:
			var x := -HALF + (ci + rng.randf()) * CELL_SIZE
			var z := -HALF + (cj + rng.randf()) * CELL_SIZE
			if Vector2(x, z).length() < 7.0:
				continue
			var table: Dictionary = DENSITY.get(biome_at(x, z), {})
			var roll := rng.randf()
			for node_id: String in table:
				roll -= float(table[node_id])
				if roll < 0.0:
					resource_spawner.spawn({"id": node_id, "pos": Vector3(x, ground_height(x, z), z), "rot": rng.randf() * TAU})
					break


func _scatter_loot() -> void:
	for entry in loot:
		var angle := randf() * TAU
		var dist := randf_range(3.0, loot_radius)
		var x := cos(angle) * dist
		var z := sin(angle) * dist
		WorldItems.spawn(entry[0], entry[1], Vector3(x, ground_height(x, z) + 0.5, z))


func _spawn_zombies() -> void:
	# Fase 7.3 troca por população por região. Por enquanto: alguns perto do centro.
	super()

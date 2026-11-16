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
	"tundra": Color(0.84, 0.86, 0.9),
}
const BIOME_NAMES := {
	"plains": "Planície", "forest": "Floresta", "swamp": "Pântano", "lake": "Lago",
	"lakeside": "Margem do lago", "mountain": "Montanhas", "contaminated": "Zona contaminada",
	"tundra": "Tundra nevada",
}
## Chance por célula de 8 m de cada recurso, por bioma.
const DENSITY := {
	"forest": {"tree": 0.55, "berry_bush": 0.05, "branches": 0.08, "nest": 0.05, "rock": 0.03},
	"plains": {"tree": 0.05, "berry_bush": 0.07, "branches": 0.03, "rock": 0.03, "nest": 0.01},
	"swamp": {"tree": 0.1, "herb_patch": 0.14, "branches": 0.06},
	"lakeside": {"tree": 0.07, "berry_bush": 0.05, "rock": 0.03, "nest": 0.03},
	"mountain": {"rock": 0.15, "tree": 0.04},
	"contaminated": {"crystal": 0.2, "rock": 0.05, "tree": 0.02},
	"tundra": {"pine": 0.33, "rock": 0.06, "branches": 0.04},
}
const CELL_SIZE := 8.0
## Profundidade da faixa de tundra (a partir das montanhas do norte).
const TUNDRA_DEPTH := 70.0

## População de zumbis por região (GDD 10.2): quantos manter perto de cada jogador e
## de que tipos (peso), conforme o bioma onde ele está.
const POPULATION := {
	"plains": {"target": 5, "types": {"walker": 8, "runner": 1}},
	"forest": {"target": 7, "types": {"walker": 6, "runner": 2}},
	"lakeside": {"target": 6, "types": {"walker": 7, "runner": 1}},
	"lake": {"target": 4, "types": {"walker": 1}},
	"swamp": {"target": 8, "types": {"walker": 5, "spitter": 2, "runner": 1}},
	"mountain": {"target": 5, "types": {"walker": 4, "brute": 1, "runner": 1}},
	"tundra": {"target": 6, "types": {"frozen": 4, "walker": 2}},
	"contaminated": {"target": 11, "types": {"night_infected": 4, "exploder": 2, "spitter": 2, "brute": 1, "walker": 2}},
}
const POP_INTERVAL := 3.0
const POP_SPAWN_MIN := 35.0
const POP_SPAWN_MAX := 60.0
const POP_DESPAWN := 95.0
const POP_CAP := 50
const NIGHT_POP_FACTOR := 1.5

## Semente do mundo (vem do host pela SeedSync antes do _ready).
@export var world_seed := 0
## Carregado de um save: as construções e o saque vêm do arquivo (não gera os lugares).
var from_save := false

var lakes: Array = []  # [Vector2 centro, raio]
## Pontos de interesse: {type, name, cell (Vector2i), size (Vector2i), door, loot, pos}.
var pois: Array = []
var contaminated_center := Vector2.ZERO
var contaminated_radius := 36.0

var _forest_noise := FastNoiseLite.new()
var _swamp_noise := FastNoiseLite.new()
var _hill_noise := FastNoiseLite.new()
var _pop_timer := 2.0
var _necro_night := false
var _tiles: Array[NavigationRegion3D] = []
var _dirty_tiles := {}


func _setup_level() -> void:
	if world_seed == 0:
		world_seed = randi_range(1, 2147483646)  # host (ou solo) sorteia
	add_to_group("world")
	_plan()
	_plan_pois()
	# Desempenho: sombras do sol só até 70 m (a névoa esconde o resto).
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun:
		sun.directional_shadow_max_distance = 70.0
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
	# Faixa norte (fim do mapa em -Z): tundra nevada (expansão).
	if z < -HALF + MOUNTAIN_BAND + TUNDRA_DEPTH:
		return "tundra"
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


# --- Pontos de interesse (GDD 10.1) ------------------------------------------------------
# Feitos com peças de construção: dá para ocupar, consertar e reforçar (GDD 9.3).

const POI_NAMES := {"house": "Casa abandonada", "cabin": "Cabana", "village": "Vilarejo",
	"military": "Posto militar", "ruins": "Ruínas arcanas"}


func _plan_pois() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 7
	pois.clear()
	# Vilarejo: 4 casas em volta de uma praça, a 45-70 m do centro.
	for attempt in 40:
		var a := rng.randf() * TAU
		var center := Vector2(cos(a), sin(a)) * rng.randf_range(45.0, 70.0)
		var cells := [Vector2i(-3, -3), Vector2i(1, -3), Vector2i(-3, 1), Vector2i(1, 1)]
		var ok := true
		for c: Vector2i in cells:
			ok = ok and _poi_fits(_cell_of(center) + c, Vector2i(2, 1))
		if ok:
			for c: Vector2i in cells:
				_add_poi("house", _cell_of(center) + c, Vector2i(2, 1), rng, "house", "Vilarejo")
			break
	# Uma cabana na margem de cada lago.
	for lake: Array in lakes:
		for attempt in 20:
			var a := rng.randf() * TAU
			var p: Vector2 = lake[0] + Vector2(cos(a), sin(a)) * (float(lake[1]) + 7.0)
			if _poi_fits(_cell_of(p), Vector2i.ONE):
				_add_poi("cabin", _cell_of(p), Vector2i.ONE, rng, "house")
				break
	# Cabanas soltas na floresta.
	var placed := 0
	for attempt in 200:
		if placed >= 4:
			break
		var p := Vector2(rng.randf_range(-HALF + 40, HALF - 40), rng.randf_range(-HALF + 40, HALF - 40))
		if biome_at(p.x, p.y) == "forest" and p.length() > 40.0 and _poi_fits(_cell_of(p), Vector2i.ONE):
			_add_poi("cabin", _cell_of(p), Vector2i.ONE, rng, "house")
			placed += 1
	# Posto militar (3 × 3, muro de pedra, sem teto) longe do centro.
	for attempt in 100:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rng.randf_range(80.0, 110.0)
		if _poi_fits(_cell_of(p), Vector2i(3, 3)):
			_add_poi("military", _cell_of(p), Vector2i(3, 3), rng, "military")
			break
	# Ruínas no meio da zona contaminada.
	_add_poi("ruins", _cell_of(contaminated_center) - Vector2i.ONE, Vector2i(2, 2), rng, "ruins")


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BuildPiece.CELL), floori(p.y / BuildPiece.CELL))


## A área (com folga de 1 célula) está em chão construível e longe de outros lugares?
func _poi_fits(cell: Vector2i, size: Vector2i) -> bool:
	for j in range(-1, size.y + 1):
		for i in range(-1, size.x + 1):
			var x := (cell.x + i + 0.5) * BuildPiece.CELL
			var z := (cell.y + j + 0.5) * BuildPiece.CELL
			if biome_at(x, z) in ["lake", "mountain"] or Vector2(x, z).length() < SPAWN_SAFE + 8.0:
				return false
	var center := (Vector2(cell) + Vector2(size) * 0.5) * BuildPiece.CELL
	for poi: Dictionary in pois:
		if center.distance_to(poi.pos) < 14.0:
			return false
	return true


func _add_poi(type: String, cell: Vector2i, size: Vector2i, rng: RandomNumberGenerator, loot_table: String, name_override := "") -> void:
	pois.append({
		"type": type, "name": name_override if name_override != "" else str(POI_NAMES.get(type, type)),
		"cell": cell, "size": size, "door": rng.randi_range(0, 3), "loot": loot_table,
		"pos": (Vector2(cell) + Vector2(size) * 0.5) * BuildPiece.CELL, "seed": rng.randi(),
	})


## Servidor: monta as construções e o saque dos lugares.
func _build_pois() -> void:
	for poi: Dictionary in pois:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(poi.seed)
		var cell: Vector2i = poi.cell
		var size: Vector2i = poi.size
		match str(poi.type):
			"military":
				_ring_walls(cell, size, "stone", int(poi.door), 0.0, rng)
			"ruins":
				for j in size.y:
					for i in size.x:
						if rng.randf() < 0.6:
							Structures._spawn_piece("foundation", "stone", "c:%d:%d:0" % [cell.x + i, cell.y + j], 0)
				_ring_walls(cell, size, "stone", int(poi.door), 0.4, rng)
			_:
				for j in size.y:
					for i in size.x:
						Structures._spawn_piece("foundation", "wood", "c:%d:%d:0" % [cell.x + i, cell.y + j], 0)
				_ring_walls(cell, size, "wood", int(poi.door), 0.12, rng)
				# Telhado, se as paredes seguram (abandonada: às vezes falta um pedaço).
				for j in size.y:
					for i in size.x:
						if rng.randf() < 0.85:
							Structures._spawn_piece("floor", "wood", "c:%d:%d:1" % [cell.x + i, cell.y + j], 0)
		Structures._collapse_unsupported()
		_drop_loot(poi, rng)


## Paredes em volta de um retângulo de células. door: lado da porta (0 norte, 1 sul,
## 2 oeste, 3 leste). missing: chance de faltar uma parede (abandonado/ruína).
func _ring_walls(cell: Vector2i, size: Vector2i, tier: String, door: int, missing: float, rng: RandomNumberGenerator) -> void:
	var edges: Array = []  # [chave, rot, lado]
	for i in size.x:
		edges.append(["z:%d:%d:0" % [cell.x + i, cell.y], 0, 0])
		edges.append(["z:%d:%d:0" % [cell.x + i, cell.y + size.y], 0, 1])
	for j in size.y:
		edges.append(["x:%d:%d:0" % [cell.x, cell.y + j], 1, 2])
		edges.append(["x:%d:%d:0" % [cell.x + size.x, cell.y + j], 1, 3])
	var door_edges := edges.filter(func(e: Array) -> bool: return int(e[2]) == door)
	var door_key: String = door_edges[rng.randi_range(0, door_edges.size() - 1)][0]
	for e: Array in edges:
		if e[0] == door_key:
			Structures._spawn_piece("doorway", tier, e[0], int(e[1]))
		elif rng.randf() >= missing:
			Structures._spawn_piece("wall", tier, e[0], int(e[1]))


func _drop_loot(poi: Dictionary, rng: RandomNumberGenerator) -> void:
	var table := GameData.get_entry("loot", str(poi.loot))
	var items: Array = table.get("items", [])
	var total := 0.0
	for entry: Array in items:
		total += float(entry[3])
	var cell: Vector2i = poi.cell
	var size: Vector2i = poi.size
	for k in int(table.get("rolls", 3)):
		var roll := rng.randf() * total
		for entry: Array in items:
			roll -= float(entry[3])
			if roll <= 0.0:
				var x := (cell.x + rng.randf_range(0.2, size.x - 0.2)) * BuildPiece.CELL
				var z := (cell.y + rng.randf_range(0.2, size.y - 0.2)) * BuildPiece.CELL
				WorldItems.spawn(str(entry[0]), rng.randi_range(int(entry[1]), int(entry[2])), Vector3(x, 1.0, z))
				break


## Algum lugar (com folga) cobre este ponto? Recursos não nascem dentro.
func _in_poi(x: float, z: float) -> bool:
	for poi: Dictionary in pois:
		var min_corner := Vector2(poi.cell) * BuildPiece.CELL - Vector2.ONE * 4.0
		var max_corner := Vector2(poi.cell + poi.size) * BuildPiece.CELL + Vector2.ONE * 4.0
		if x > min_corner.x and x < max_corner.x and z > min_corner.y and z < max_corner.y:
			return true
	return false


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


func _process(delta: float) -> void:
	if multiplayer.is_server():
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			_pop_timer = POP_INTERVAL
			_update_population()
	for k: int in _dirty_tiles.keys():
		if not _tiles[k].is_baking():
			_dirty_tiles.erase(k)
			_tiles[k].bake_navigation_mesh(true)


# --- Conteúdo (servidor) ---------------------------------------------------------------

func _scatter_resources() -> void:
	if not from_save:
		_build_pois()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 1
	var cells := int(SIZE / CELL_SIZE)
	for cj in cells:
		for ci in cells:
			var x := -HALF + (ci + rng.randf()) * CELL_SIZE
			var z := -HALF + (cj + rng.randf()) * CELL_SIZE
			if Vector2(x, z).length() < 7.0 or _in_poi(x, z):
				continue
			var table: Dictionary = DENSITY.get(biome_at(x, z), {})
			var roll := rng.randf()
			for node_id: String in table:
				roll -= float(table[node_id])
				if roll < 0.0:
					resource_spawner.spawn({"id": node_id, "pos": Vector3(x, ground_height(x, z), z), "rot": rng.randf() * TAU})
					break


func _scatter_loot() -> void:
	if from_save:
		return
	for entry in loot:
		var angle := randf() * TAU
		var dist := randf_range(3.0, loot_radius)
		var x := cos(angle) * dist
		var z := sin(angle) * dist
		WorldItems.spawn(entry[0], entry[1], Vector3(x, ground_height(x, z) + 0.5, z))


## Sem zumbis fixos: a população em volta dos jogadores cuida disso.
func _spawn_zombies() -> void:
	pass


# --- População (servidor) ----------------------------------------------------------------

func _update_population() -> void:
	var players: Array = []
	for p: Node3D in players_root.get_children():
		players.append(p)
	if players.is_empty():
		return
	var free_zombies: Array = []
	for z: Zombie in zombies_root.get_children():
		if z.horde or z.is_dead() or z.is_in_group("boss"):
			continue
		free_zombies.append(z)
		# Longe de todos e sem caçar ninguém: some.
		var nearest := INF
		for p: Node3D in players:
			nearest = minf(nearest, p.global_position.distance_to(z.global_position))
		if nearest > POP_DESPAWN and z.state in [Zombie.State.WANDER, Zombie.State.INVESTIGATE]:
			z.queue_free()
	if free_zombies.size() >= POP_CAP:
		return
	var night := DayNight.find(get_tree()) != null and DayNight.find(get_tree()).is_night()
	_maybe_necromancer(players, night)
	var spawned := 0
	for p: Node3D in players:
		if spawned >= 2:
			break
		var biome := biome_at(p.global_position.x, p.global_position.z)
		var rule: Dictionary = POPULATION.get(biome, POPULATION.plains)
		var target := int(round(float(rule.target) * (NIGHT_POP_FACTOR if night else 1.0)))
		var around := 0
		for z: Zombie in free_zombies:
			if z.global_position.distance_to(p.global_position) < POP_DESPAWN:
				around += 1
		if around >= target:
			continue
		var pos := _spawn_spot_near(p.global_position)
		if pos == Vector3.INF:
			continue
		# Os tipos seguem a região do jogador; se o zumbi nasce na zona contaminada, vale ela.
		var spawn_rule := rule
		if biome_at(pos.x, pos.z) == "contaminated":
			spawn_rule = POPULATION.contaminated
		var z := spawn_zombie(_pick_weighted(spawn_rule.types), pos)
		free_zombies.append(z)
		spawned += 1


## Uma vez por noite, se alguém está na zona contaminada, o Necromante surge nas ruínas.
func _maybe_necromancer(players: Array, night: bool) -> void:
	if not night:
		_necro_night = false
		return
	if _necro_night:
		return
	for p: Node3D in players:
		if biome_at(p.global_position.x, p.global_position.z) == "contaminated":
			_necro_night = true
			for poi: Dictionary in pois:
				if poi.type == "ruins":
					spawn_zombie("necromancer", Vector3(poi.pos.x, 0.0, poi.pos.y + 4.0))
			return


func _spawn_spot_near(center: Vector3) -> Vector3:
	for attempt in 12:
		var a := randf() * TAU
		var d := randf_range(POP_SPAWN_MIN, POP_SPAWN_MAX)
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		if maxf(absf(x), absf(z)) > HALF - 4.0 or biome_at(x, z) == "lake" or _in_poi(x, z):
			continue
		return Vector3(x, 0.0, z)
	return Vector3.INF


static func _pick_weighted(weights: Dictionary) -> String:
	var total := 0.0
	for id: String in weights:
		total += float(weights[id])
	var roll := randf() * total
	for id: String in weights:
		roll -= float(weights[id])
		if roll <= 0.0:
			return id
	return weights.keys()[0]

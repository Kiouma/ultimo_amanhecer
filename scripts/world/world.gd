extends "res://scripts/world/arena.gd"
## Mundo aberto infinito (GDD 10), gerado a partir de uma semente (world_seed) enquanto
## os jogadores andam. O host sorteia a semente; ela chega aos clientes junto com a cena
## (SeedSync) e todos geram o mesmo terreno.
##
## Blocos (CHUNK metros): em volta de cada jogador, cada máquina monta o terreno (malha
## + colisão, calculados numa thread), a água e a decoração. O servidor também cria os
## recursos coletáveis e a malha de navegação dos monstros nos blocos perto dos jogadores
## e tira tudo dos blocos que ficaram longe. Recursos colhidos lembram quando voltam.
##
## Relevo: colinas suaves, montanhas (ruído) e lagos (vales abaixo do nível da água).
## Biomas por ruído: planície, floresta, pântano, lago/margem, montanha, tundra e zonas
## contaminadas (longe do começo). Onde se nasce e o chão dos lugares são aplainados.
##
## Lugares (casas, cabanas, vilarejos, fortes, ruínas): no máximo um por região de
## REGION metros, com chance baixa. O servidor monta as construções na primeira vez que
## alguém chega perto e guarda no save quais regiões já foram montadas.
##
## Construção: cada célula da grade tem a altura do chão (BuildPiece.base_height_func).

const CHUNK := 64.0
## Distância entre vértices do terreno.
const STEP := 2.0
const VERTS := 33  # CHUNK / STEP + 1
## Raio (em blocos) em volta de cada jogador: terreno, recursos/navegação (servidor), decoração.
const TERRAIN_RADIUS := 3
const CONTENT_RADIUS := 2
const DECOR_RADIUS := 1
const REGION := 256.0
const POI_CHANCE := 0.28
const WATER_LEVEL := 0.0
const SPAWN_FLAT := 28.0
const SPAWN_BLEND := 50.0
const MOUNTAIN_HEIGHT := 20.0

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
	# Coletáveis raros (frutas, ninhos, ervas, cristais); madeira caída e pedras (pedrinhas) fartas.
	"forest": {"tree": 0.42, "rock": 0.04, "pebbles": 0.06, "branches": 0.12, "berry_bush": 0.025, "nest": 0.02},
	"plains": {"tree": 0.04, "rock": 0.04, "pebbles": 0.07, "branches": 0.06, "berry_bush": 0.035, "nest": 0.005},
	"swamp": {"twisted_tree": 0.03, "dead_tree": 0.03, "tree": 0.02, "pebbles": 0.03, "branches": 0.1, "herb_patch": 0.07},
	"lakeside": {"tree": 0.05, "rock": 0.04, "pebbles": 0.1, "branches": 0.05, "berry_bush": 0.025, "nest": 0.015},
	"mountain": {"rock": 0.18, "pine": 0.03, "pebbles": 0.1},
	"contaminated": {"crystal": 0.1, "rock": 0.05, "dead_tree": 0.02, "pebbles": 0.04},
	"tundra": {"pine": 0.26, "rock": 0.07, "pebbles": 0.06, "branches": 0.07},
}
const CELL_SIZE := 8.0

## População de monstros por região (GDD 10.2): quantos manter perto de cada jogador e
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
## Carregado de um save (compatibilidade; o que importa são as regiões já montadas).
var from_save := false
## Regiões cujos lugares o servidor já montou ("rx:rz"). Vem do save antes do _ready.
var built_regions := {}

## Lugares já planejados (regiões perto de onde alguém passou):
## {type, name, cell, size, door, loot, pos, seed, base, region, group}.
var pois: Array = []

var _noise := {}
var _regions := {}  # Vector2i → Array de lugares (planejada)
var _spawn_height := 0.0
var _pop_timer := 2.0
var _necro_night := false
var _troll_night := false
var _base_cache := {}

# Blocos carregados: Vector2i → {node, body, nav, resources, decor}
var _chunks := {}
var _pending := {}  # Vector2i → "terrain"/"decor" (tarefa na thread)
var _results: Array = []
var _results_mutex := Mutex.new()
var _tasks := {}  # id da tarefa na thread → true (espera ao sair)
var _stream_timer := 0.0
var _depleted := {}  # "x:z" (posição ×10) → hora (ms) em que o recurso volta
var _dirty_nav := {}
## Navegação: blocos calculando na thread, prontos para aplicar ([bloco, malha]).
var _nav_baking := {}
var _nav_done: Array = []
var _nav_mutex := Mutex.new()
## Recursos a criar ([bloco, dados]) e a liberar: aos poucos, em lotes por quadro.
var _spawn_queue: Array = []
var _free_queue: Array = []
## Tela de carregamento: tudo mais rápido (sem se preocupar com engasgos).
var preloading := false
var _terrain_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D


func _setup_level() -> void:
	if world_seed == 0:
		world_seed = randi_range(1, 2147483646)  # host (ou solo) sorteia
	add_to_group("world")
	_setup_noise()
	BuildPiece.base_height_func = cell_base
	var sun := get_node_or_null(^"Sun") as DirectionalLight3D
	if sun:
		sun.directional_shadow_max_distance = 70.0  # a névoa esconde o resto
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.roughness = 0.95
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.16, 0.3, 0.38, 0.85)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.metallic = 0.3
	_water_mat.roughness = 0.08
	# Começo: o chão em volta de onde se nasce já pronto (ninguém cai).
	for cz in range(-1, 1):
		for cx in range(-1, 1):
			_load_terrain_now(Vector2i(cx, cz))


func _exit_tree() -> void:
	# Tarefas de terreno ainda rodando usam este nó: espera terminarem antes de liberar.
	for id: int in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	MapTiles.wait_all()  # imagens do mapa sendo feitas a partir deste mundo
	if BuildPiece.base_height_func == cell_base:
		BuildPiece.base_height_func = Callable()


static func find(tree: SceneTree) -> Node:
	return tree.get_first_node_in_group("world")


# --- Ruído, relevo e biomas (determinístico; funções "raw" servem para a thread) ---------

func _setup_noise() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var specs := {"hills": 0.0045, "rolling": 0.016, "detail": 0.03, "mountain": 0.0022, "temp": 0.0011, "lake": 0.008,
		"corrupt": 0.0032, "forest": 0.012, "swamp": 0.009, "shade": 0.12}
	for key: String in specs:
		var n := FastNoiseLite.new()
		n.seed = rng.randi()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = specs[key]
		if key in ["hills", "mountain"]:
			n.fractal_type = FastNoiseLite.FRACTAL_FBM
			n.fractal_octaves = 3
		_noise[key] = n
	_spawn_height = snappedf(_natural_height(0.0, 0.0), 0.25)


func _n(key: String, x: float, z: float) -> float:
	return (_noise[key] as FastNoiseLite).get_noise_2d(x, z)


## 0 a 1: quanto o ponto é montanha (nunca perto de onde se nasce).
func _mountain_factor(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	return smoothstep(0.32, 0.62, _n("mountain", x, z)) * smoothstep(90.0, 180.0, d)


## Altura natural (sem o começo nem os lugares aplainados).
func _natural_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var m := _mountain_factor(x, z)
	var h := 1.2 + (_n("hills", x, z) + 1.0) * 5.5 + _n("rolling", x, z) * 2.2 + _n("detail", x, z) * 0.5
	h += m * (MOUNTAIN_HEIGHT + _n("detail", x * 2.0, z * 2.0) * 4.0)
	var lake := smoothstep(0.4, 0.62, _n("lake", x, z)) * (1.0 - m) * smoothstep(SPAWN_BLEND, SPAWN_BLEND + 30.0, d)
	return lerpf(h, WATER_LEVEL - 1.8, lake)


## Altura do terreno sem lugares aplainados (seguro para a thread).
func _raw_height(x: float, z: float) -> float:
	var h := _natural_height(x, z)
	var d := Vector2(x, z).length()
	if d < SPAWN_BLEND:
		h = lerpf(_spawn_height, h, smoothstep(SPAWN_FLAT, SPAWN_BLEND, d))
	return h


## Altura considerando o chão aplainado dos lugares da lista.
func _height_with(x: float, z: float, near_pois: Array) -> float:
	var h := _raw_height(x, z)
	for poi: Dictionary in near_pois:
		var lo := Vector2(poi.cell) * BuildPiece.CELL
		var hi := Vector2(poi.cell + poi.size) * BuildPiece.CELL
		var dx := maxf(maxf(lo.x - x, x - hi.x), 0.0)
		var dz := maxf(maxf(lo.y - z, z - hi.y), 0.0)
		var dist := Vector2(dx, dz).length()
		if dist < 8.0:
			h = lerpf(float(poi.base), h, smoothstep(1.0, 8.0, dist))
	return h


func ground_height(x: float, z: float) -> float:
	return _height_with(x, z, _pois_near(x, z))


## Bioma a partir da altura bruta (seguro para a thread).
func _biome_raw(x: float, z: float, h: float) -> String:
	if h < WATER_LEVEL:
		return "lake"
	if h < WATER_LEVEL + 0.7:
		return "lakeside"
	if _mountain_factor(x, z) > 0.45:
		return "mountain"
	var d := Vector2(x, z).length()
	if d < SPAWN_BLEND:
		return "plains"
	if d > 160.0 and _n("corrupt", x, z) > 0.55:
		return "contaminated"
	if _n("temp", x, z) < -0.38:
		return "tundra"
	if _n("swamp", x, z) > 0.32:
		return "swamp"
	if _n("forest", x, z) > -0.05:
		return "forest"
	return "plains"


func biome_at(x: float, z: float) -> String:
	return _biome_raw(x, z, _raw_height(x, z))


## Altura do chão da célula de construção (i, j), em degraus de 25 cm. Dentro de um
## lugar, a altura aplainada dele (todas as células iguais).
func cell_base(i: int, j: int) -> float:
	var key := Vector2i(i, j)
	if not _base_cache.has(key):
		if _base_cache.size() > 20000:
			_base_cache.clear()
		_base_cache[key] = snappedf(ground_height((i + 0.5) * BuildPiece.CELL, (j + 0.5) * BuildPiece.CELL), 0.25)
	return _base_cache[key]


static func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


# --- Lugares (GDD 10.1), por região ----------------------------------------------------------
# Feitos com peças de construção: dá para ocupar, consertar e reforçar (GDD 9.3).

## Tamanho dos lugares em células de construção (3 m).
const HOUSE_SIZE := Vector2i(3, 2)
const CABIN_SIZE := Vector2i(2, 2)
const FORT_SIZE := Vector2i(4, 4)
const RUINS_SIZE := Vector2i(3, 3)
const POI_WEIGHTS := {"cabin": 45, "house": 20, "village": 10, "military": 12, "ruins": 13}

const POI_NAMES := {"house": "Casa abandonada", "cabin": "Cabana", "village": "Vilarejo",
	"military": "Forte abandonado", "ruins": "Ruínas arcanas"}


func region_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / REGION), floori(z / REGION))


## Lugares das regiões em volta do ponto (planeja as que faltam).
func _pois_near(x: float, z: float) -> Array:
	var r := region_of(x, z)
	var out: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			out.append_array(_region_pois(r + Vector2i(dx, dz)))
	return out


func _region_pois(r: Vector2i) -> Array:
	if not _regions.has(r):
		_regions[r] = _plan_region(r)
		pois.append_array(_regions[r])
	return _regions[r]


func _plan_region(r: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, r.x, r.y, 77])
	var out: Array = []
	if rng.randf() > POI_CHANCE:
		return out
	var type := _pick_weighted_rng(POI_WEIGHTS, rng)
	for attempt in 8:
		var p := (Vector2(r) + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))) * REGION
		if p.length() < 70.0:
			continue
		var biome := _biome_raw(p.x, p.y, _raw_height(p.x, p.y))
		if biome in ["lake", "lakeside", "mountain"]:
			continue
		if biome == "contaminated":
			type = "ruins"  # zona contaminada: ruínas arcanas (lá surge o Necromante)
		var center := _cell_of(p)
		var group := "%d:%d" % [r.x, r.y]
		match type:
			"village":
				for c: Vector2i in [Vector2i(-4, -4), Vector2i(1, -4), Vector2i(-4, 1), Vector2i(1, 1)]:
					out.append(_make_poi("house", center + c, HOUSE_SIZE, rng, "house", "Vilarejo", group))
				out.append({"type": "square", "name": "", "cell": center, "size": Vector2i.ZERO, "pos": p, "seed": rng.randi(),
					"base": snappedf(_raw_height(p.x, p.y), 0.25), "region": r, "group": group})
			"house":
				out.append(_make_poi("house", center, HOUSE_SIZE, rng, "house", "", group))
			"cabin":
				out.append(_make_poi("cabin", center, CABIN_SIZE, rng, "house", "", group))
			"military":
				out.append(_make_poi("military", center, FORT_SIZE, rng, "military", "", group))
			_:
				out.append(_make_poi("ruins", center, RUINS_SIZE, rng, "ruins", "", group))
		# Todos os lugares do grupo no mesmo chão (o do centro).
		var base := snappedf(_raw_height(p.x, p.y), 0.25)
		for poi: Dictionary in out:
			poi.base = base
			poi.region = r
		return out
	return out


func _make_poi(type: String, cell: Vector2i, size: Vector2i, rng: RandomNumberGenerator, loot_table: String, name_override: String, group: String) -> Dictionary:
	return {
		"type": type, "name": name_override if name_override != "" else str(POI_NAMES.get(type, type)),
		"cell": cell, "size": size, "door": rng.randi_range(0, 3), "loot": loot_table,
		"pos": (Vector2(cell) + Vector2(size) * 0.5) * BuildPiece.CELL, "seed": rng.randi(), "group": group,
	}


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BuildPiece.CELL), floori(p.y / BuildPiece.CELL))


## Servidor: monta as construções e o saque dos lugares de uma região (uma vez por mundo).
func _build_region(r: Vector2i) -> void:
	var key := "%d:%d" % [r.x, r.y]
	if built_regions.has(key):
		return
	built_regions[key] = true
	for poi: Dictionary in _region_pois(r):
		if str(poi.type) == "square":
			continue
		# As peças entram na fila de montagem (aos poucos: um vilarejo tem ~90 peças); as
		# decisões (paredes faltando, telhado) são sorteadas agora, iguais a antes.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(poi.seed)
		var cell: Vector2i = poi.cell
		var size: Vector2i = poi.size
		var jobs: Array = []
		match str(poi.type):
			"military":
				_ring_walls(cell, size, "stone", int(poi.door), 0.0, rng, jobs)
			"ruins":
				for j in size.y:
					for i in size.x:
						if rng.randf() < 0.6:
							jobs.append(Structures._spawn_piece.bind("foundation", "stone", "c:%d:%d:0" % [cell.x + i, cell.y + j], 0))
				_ring_walls(cell, size, "stone", int(poi.door), 0.4, rng, jobs)
			_:
				for j in size.y:
					for i in size.x:
						jobs.append(Structures._spawn_piece.bind("foundation", "wood", "c:%d:%d:0" % [cell.x + i, cell.y + j], 0))
				_ring_walls(cell, size, "wood", int(poi.door), 0.12, rng, jobs)
				# Telhado, se as paredes seguram (abandonada: às vezes falta um pedaço).
				for j in size.y:
					for i in size.x:
						if rng.randf() < 0.85:
							jobs.append(Structures._spawn_piece.bind("floor", "wood", "c:%d:%d:1" % [cell.x + i, cell.y + j], 0))
		jobs.append(Structures._collapse_unsupported)
		jobs.append(_drop_loot.bind(poi, rng))
		_build_queue.append_array(jobs)


## Paredes em volta de um retângulo de células (entram em jobs). door: lado da porta
## (0 norte, 1 sul, 2 oeste, 3 leste). missing: chance de faltar uma parede (abandonado/ruína).
func _ring_walls(cell: Vector2i, size: Vector2i, tier: String, door: int, missing: float, rng: RandomNumberGenerator, jobs: Array) -> void:
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
			jobs.append(Structures._spawn_piece.bind("doorway", tier, e[0], int(e[1])))
		elif rng.randf() >= missing:
			jobs.append(Structures._spawn_piece.bind("wall", tier, e[0], int(e[1])))


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
				WorldItems.spawn(str(entry[0]), rng.randi_range(int(entry[1]), int(entry[2])), Vector3(x, float(poi.base) + 1.0, z))
				break


## Algum lugar (com folga) cobre este ponto? Recursos não nascem dentro.
func _in_poi(x: float, z: float) -> bool:
	return _in_poi_list(x, z, _pois_near(x, z))


static func _in_poi_list(x: float, z: float, list: Array) -> bool:
	for poi: Dictionary in list:
		if str(poi.type) == "square":
			if Vector2(x, z).distance_to(poi.pos) < 4.0:
				return true
			continue
		var min_corner := Vector2(poi.cell) * BuildPiece.CELL - Vector2.ONE * 4.0
		var max_corner := Vector2(poi.cell + poi.size) * BuildPiece.CELL + Vector2.ONE * 4.0
		if x > min_corner.x and x < max_corner.x and z > min_corner.y and z < max_corner.y:
			return true
	return false


# --- Blocos: carregar e descarregar ----------------------------------------------------------

func _process(delta: float) -> void:
	if multiplayer.is_server() and not preloading:
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			_pop_timer = POP_INTERVAL
			_update_population()
	_apply_results()
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.0 if preloading else 0.3
		_stream()
	_process_build_queue()
	_process_spawn_queue()
	_process_free_queue()
	_process_navigation()


## Cria recursos aos poucos (cada árvore/pedra custa ~1-2 ms: todos de uma vez travava ao
## cruzar um bloco): para quando gasta FRAME_BUDGET_MS no quadro.
const FRAME_BUDGET_MS := 2.5
const FREES_PER_FRAME := 25


func _budget_left(start_usec: int) -> bool:
	return preloading or Time.get_ticks_usec() - start_usec < FRAME_BUDGET_MS * 1000.0


func _process_spawn_queue() -> void:
	var start := Time.get_ticks_usec()
	while _budget_left(start) and not _spawn_queue.is_empty():
		var item: Array = _spawn_queue.pop_front()
		var c: Vector2i = item[0]
		var chunk: Dictionary = _chunks.get(c, {})
		if not chunk.get("content", false):
			continue
		chunk.pending_spawns = int(chunk.get("pending_spawns", 1)) - 1
		var node := resource_spawner.spawn(item[1])
		if node:
			(chunk.resources as Array).append(node)


## Peças dos lugares (casas, fortes...): montadas aos poucos também (um vilarejo tem ~90).
var _build_queue: Array = []  # Callables


func _process_build_queue() -> void:
	var start := Time.get_ticks_usec()
	while _budget_left(start) and not _build_queue.is_empty():
		(_build_queue.pop_front() as Callable).call()


func _process_free_queue() -> void:
	var budget := 100000 if preloading else FREES_PER_FRAME
	while budget > 0 and not _free_queue.is_empty():
		var node: Node = _free_queue.pop_back()
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
		budget -= 1


## Posições que puxam blocos: todos os jogadores (ou o começo, antes de existirem).
func _anchors() -> Array:
	var out: Array = []
	for p: Node3D in players_root.get_children():
		out.append(p.global_position)
	if out.is_empty():
		out.append(Vector3.ZERO)
	return out


func _local_anchor() -> Vector3:
	for p: Node3D in players_root.get_children():
		if p.is_multiplayer_authority():
			return p.global_position
	return Vector3.ZERO


func _stream() -> void:
	var anchors := _anchors()
	var want := {}
	for a: Vector3 in anchors:
		var c := chunk_of(a.x, a.z)
		# O bloco debaixo de um jogador desta máquina não pode faltar: faz na hora.
		for p: Node3D in players_root.get_children():
			if p.is_multiplayer_authority() and chunk_of(p.global_position.x, p.global_position.z) == c and not _chunks.has(c):
				_load_terrain_now(c)
		for dz in range(-TERRAIN_RADIUS, TERRAIN_RADIUS + 1):
			for dx in range(-TERRAIN_RADIUS, TERRAIN_RADIUS + 1):
				var k := c + Vector2i(dx, dz)
				var d := maxi(absi(dx), absi(dz))
				want[k] = mini(int(want.get(k, 99)), d)
	# Pedir à thread os que faltam (os mais perto primeiro, poucos por vez).
	var missing: Array = []
	for k: Vector2i in want:
		if not _chunks.has(k) and not _pending.has(k):
			missing.append(k)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return int(want[a]) < int(want[b]))
	for i in mini(missing.size(), 16 if preloading else 3):
		_start_terrain_task(missing[i])
	# Conteúdo (servidor), decoração (jogador local) e descarga.
	var local := chunk_of(_local_anchor().x, _local_anchor().z)
	for k: Vector2i in _chunks.keys():
		var dist := int(want.get(k, 99))
		var chunk: Dictionary = _chunks[k]
		if dist > TERRAIN_RADIUS + 1:
			_unload(k)
			continue
		if multiplayer.is_server():
			if dist <= CONTENT_RADIUS and not chunk.get("content", false):
				_load_content(k)
			elif dist > CONTENT_RADIUS + 1 and chunk.get("content", false):
				_unload_content(k)
		if DisplayServer.get_name() != "headless":
			var local_dist := maxi(absi(k.x - local.x), absi(k.y - local.y))
			if local_dist <= DECOR_RADIUS and chunk.get("decor") == null and not _pending.has(k):
				_start_decor_task(k)
			elif local_dist > DECOR_RADIUS + 1 and chunk.get("decor") != null:
				(chunk.decor as Node).queue_free()
				chunk.erase("decor")


## Tela de carregamento: de 0 a 1, quanto do entorno de `at` já está pronto (terreno;
## no servidor, recursos e navegação; no cliente, a decoração perto).
func loading_progress(at: Vector3) -> float:
	var c0 := chunk_of(at.x, at.z)
	var total := 0
	var ok := 0
	for dz in range(-TERRAIN_RADIUS, TERRAIN_RADIUS + 1):
		for dx in range(-TERRAIN_RADIUS, TERRAIN_RADIUS + 1):
			total += 1
			if _chunks.has(c0 + Vector2i(dx, dz)):
				ok += 1
	var terrain := float(ok) / total
	var inner := 0
	var inner_ok := 0
	var radius := CONTENT_RADIUS if multiplayer.is_server() else DECOR_RADIUS
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var k := c0 + Vector2i(dx, dz)
			inner += 1
			var chunk: Dictionary = _chunks.get(k, {})
			if chunk.is_empty():
				continue
			if multiplayer.is_server():
				var nav_ready: bool = chunk.get("nav") != null and not _dirty_nav.has(k) and not _nav_baking.has(k)
				if chunk.get("content", false) and int(chunk.get("pending_spawns", 0)) == 0 and nav_ready:
					inner_ok += 1
			elif chunk.get("decor") != null or DisplayServer.get_name() == "headless":
				inner_ok += 1
	return terrain * 0.55 + float(inner_ok) / inner * 0.45


func is_chunk_ready(x: float, z: float) -> bool:
	return _chunks.has(chunk_of(x, z))


func _start_terrain_task(c: Vector2i) -> void:
	_pending[c] = "terrain"
	var near := _pois_for_chunk(c)
	var with_spawns := multiplayer.is_server()
	var id := WorkerThreadPool.add_task(func() -> void:
		var data := _compute_terrain(c, near, with_spawns)
		_results_mutex.lock()
		_results.append(data)
		_results_mutex.unlock())
	_tasks[id] = true


func _start_decor_task(c: Vector2i) -> void:
	_pending[c] = "decor"
	var near := _pois_for_chunk(c)
	var id := WorkerThreadPool.add_task(func() -> void:
		var data := {"kind": "decor", "chunk": c, "batches": NatureDecor.compute(self, c, near)}
		_results_mutex.lock()
		_results.append(data)
		_results_mutex.unlock())
	_tasks[id] = true


## Lugares que podem tocar o bloco (planejados aqui, na thread principal).
func _pois_for_chunk(c: Vector2i) -> Array:
	var center := (Vector2(c) + Vector2(0.5, 0.5)) * CHUNK
	return _pois_near(center.x, center.y).duplicate()


func _load_terrain_now(c: Vector2i) -> void:
	_build_terrain_chunk(_compute_terrain(c, _pois_for_chunk(c), multiplayer.is_server()))


func _apply_results() -> void:
	# Tarefas prontas: o Godot pede um wait para liberar cada uma.
	for id: int in _tasks.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.erase(id)
	_results_mutex.lock()
	var batch := _results.duplicate()
	_results.clear()
	_results_mutex.unlock()
	for data: Dictionary in batch:
		var c: Vector2i = data.chunk
		_pending.erase(c)
		if data.kind == "terrain":
			if not _chunks.has(c):
				_build_terrain_chunk(data)
		elif _chunks.has(c) and _chunks[c].get("decor") == null:
			var node := NatureDecor.build(data.batches)
			_chunks[c].node.add_child(node)
			_chunks[c].decor = node


## Thread: alturas, cores e malha de um bloco (com uma borda para as normais).
## with_spawns (servidor): também sorteia os recursos do bloco (sai da thread principal).
func _compute_terrain(c: Vector2i, near: Array, with_spawns := false) -> Dictionary:
	var ox := c.x * CHUNK
	var oz := c.y * CHUNK
	var n := VERTS + 2  # borda de 1 vértice em volta
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			h[j * n + i] = _height_with(ox + (i - 1) * STEP, oz + (j - 1) * STEP, near)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var heights := PackedFloat32Array()
	var lowest := INF
	for j in VERTS:
		for i in VERTS:
			var x := ox + i * STEP
			var z := oz + j * STEP
			var y := h[(j + 1) * n + (i + 1)]
			heights.append(y)
			lowest = minf(lowest, y)
			verts.append(Vector3(i * STEP, y, j * STEP))
			var dx := h[(j + 1) * n + (i + 2)] - h[(j + 1) * n + i]
			var dz := h[(j + 2) * n + (i + 1)] - h[j * n + (i + 1)]
			normals.append(Vector3(-dx, 2.0 * STEP, -dz).normalized())
			var color: Color = BIOME_COLORS.get(_biome_raw(x, z, _raw_height(x, z)), Color.GREEN)
			var slope := 1.0 - normals[normals.size() - 1].y
			color = color.lerp(Color(0.42, 0.4, 0.37), clampf(slope * 3.0, 0.0, 0.6))
			color = color.lightened(_n("shade", x, z) * 0.06)
			colors.append(color)
	var indices := PackedInt32Array()
	var nav_faces := PackedVector3Array()
	for j in VERTS - 1:
		for i in VERTS - 1:
			var a := j * VERTS + i
			indices.append_array([a, a + 1, a + VERTS + 1, a, a + VERTS + 1, a + VERTS])
			if with_spawns:  # servidor: triângulos para a navegação dos monstros
				nav_faces.append_array([verts[a], verts[a + 1], verts[a + VERTS + 1], verts[a], verts[a + VERTS + 1], verts[a + VERTS]])
	# Pontos de água a cada 8 m onde o chão está abaixo da água (para a pesca, depois).
	var water_spots := PackedVector2Array()
	for j in range(2, VERTS, 4):
		for i in range(2, VERTS, 4):
			if heights[j * VERTS + i] < WATER_LEVEL - 0.3:
				water_spots.append(Vector2(ox + i * STEP, oz + j * STEP))
	return {"kind": "terrain", "chunk": c, "verts": verts, "normals": normals, "colors": colors, "indices": indices,
		"heights": heights, "lowest": lowest, "water": water_spots,
		"spawns": _resource_spawns(c, near) if with_spawns else [], "nav_faces": nav_faces}


func _build_terrain_chunk(data: Dictionary) -> void:
	var c: Vector2i = data.chunk
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [c.x, c.y]
	node.position = Vector3(c.x * CHUNK, 0.0, c.y * CHUNK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.verts
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("navmesh_source")
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _terrain_mat
	body.add_child(view)
	# Colisão: mapa de alturas com escala STEP (uniforme): alturas guardadas divididas.
	var shape := HeightMapShape3D.new()
	shape.map_width = VERTS
	shape.map_depth = VERTS
	var scaled := PackedFloat32Array()
	for v: float in data.heights:
		scaled.append(v / STEP)
	shape.map_data = scaled
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3.ONE * STEP
	col.position = Vector3(CHUNK * 0.5, 0.0, CHUNK * 0.5)
	body.add_child(col)
	node.add_child(body)
	if float(data.lowest) < WATER_LEVEL:
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(CHUNK, CHUNK)
		water.mesh = plane
		water.material_override = _water_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water.position = Vector3(CHUNK * 0.5, WATER_LEVEL - 0.05, CHUNK * 0.5)
		node.add_child(water)
	add_child(node)
	body.set_meta(&"terrain", true)
	_chunks[c] = {"node": node, "body": body, "heights": data.heights, "spawns": data.spawns, "nav_faces": data.nav_faces}
	# Móveis dos lugares cujo centro cai neste bloco (todas as máquinas).
	if DisplayServer.get_name() != "headless":
		for poi: Dictionary in _pois_for_chunk(c):
			if chunk_of(poi.pos.x, poi.pos.y) == c:
				node.add_child(PoiDecor.for_poi(self, poi))


func _unload(c: Vector2i) -> void:
	if multiplayer.is_server():
		_unload_content(c)
	var chunk: Dictionary = _chunks[c]
	(chunk.node as Node).queue_free()
	_chunks.erase(c)


# --- Conteúdo do bloco (servidor): recursos, navegação, lugares --------------------------------

func _load_content(c: Vector2i) -> void:
	var chunk: Dictionary = _chunks[c]
	chunk.content = true
	var center := (Vector2(c) + Vector2(0.5, 0.5)) * CHUNK
	_build_region(region_of(center.x, center.y))
	# Navegação deste bloco (calculada quando os recursos dele terminarem de aparecer).
	var nav := NavigationRegion3D.new()
	add_child(nav)
	chunk.nav = nav
	# Recursos (sorteados na thread junto com o terreno; colhidos voltam depois do tempo).
	var now := Time.get_ticks_msec()
	var queued := 0
	for spawn: Dictionary in chunk.get("spawns", []):
		var key := "%d:%d" % [roundi(spawn.pos.x * 10.0), roundi(spawn.pos.z * 10.0)]
		if int(_depleted.get(key, 0)) > now:
			continue
		_depleted.erase(key)
		_spawn_queue.append([c, spawn])
		queued += 1
	chunk.resources = []
	chunk.pending_spawns = queued
	_dirty_nav[c] = true


func _unload_content(c: Vector2i) -> void:
	var chunk: Dictionary = _chunks.get(c, {})
	if not chunk.get("content", false):
		return
	chunk.content = false
	_free_queue.append_array(chunk.get("resources", []))  # some aos poucos
	chunk.erase("resources")
	chunk.pending_spawns = 0
	if chunk.get("nav"):
		(chunk.nav as Node).queue_free()
		chunk.erase("nav")
	_dirty_nav.erase(c)
	_nav_baking.erase(c)


# --- Navegação por bloco ---------------------------------------------------------------------
# Cada bloco monta a própria geometria (o terreno que já tem + obstáculos perto dele) e o
# NavigationServer calcula na thread: antes, cada cálculo relia o mundo inteiro na
# thread principal (~25 ms por bloco, vários blocos de uma vez).

## Blocos a recalcular por quadro (o resto espera o próximo).
const NAV_BAKES_PER_FRAME := 1


func _process_navigation() -> void:
	# Prontos: aplica a malha nova na região do bloco.
	_nav_mutex.lock()
	var done := _nav_done.duplicate()
	_nav_done.clear()
	_nav_mutex.unlock()
	for item: Array in done:
		var c: Vector2i = item[0]
		_nav_baking.erase(c)
		var chunk: Dictionary = _chunks.get(c, {})
		var nav: NavigationRegion3D = chunk.get("nav")
		if nav and is_instance_valid(nav):
			nav.navigation_mesh = item[1]
	var started := 0
	for c: Vector2i in _dirty_nav.keys():
		if started >= (64 if preloading else NAV_BAKES_PER_FRAME):
			break
		var chunk: Dictionary = _chunks.get(c, {})
		if chunk.get("nav") == null:
			_dirty_nav.erase(c)
			continue
		if int(chunk.get("pending_spawns", 0)) > 0 or _nav_baking.has(c):
			continue  # espera os recursos aparecerem / o cálculo anterior terminar
		_dirty_nav.erase(c)
		_bake_chunk_nav(c)
		started += 1


func _bake_chunk_nav(c: Vector2i) -> void:
	var chunk: Dictionary = _chunks[c]
	var nm: NavigationMesh = nav_region.navigation_mesh.duplicate()
	nm.filter_baking_aabb = AABB(Vector3(c.x * CHUNK, -60.0, c.y * CHUNK), Vector3(CHUNK, 200.0, CHUNK))
	nm.border_size = 1.0
	var src := NavigationMeshSourceGeometryData3D.new()
	# Terreno: os triângulos do próprio bloco (montados na thread, com a malha).
	src.add_faces(chunk.nav_faces, Transform3D(Basis(), (chunk.node as Node3D).position))
	# Obstáculos perto do bloco (árvores, rochas, construções, estações): pelas colisões.
	var area := AABB(Vector3(c.x * CHUNK - 4.0, -100.0, c.y * CHUNK - 4.0), Vector3(CHUNK + 8.0, 300.0, CHUNK + 8.0))
	for n: Node in get_tree().get_nodes_in_group("navmesh_source"):
		if not n is CollisionObject3D or n.has_meta(&"terrain") or not area.has_point((n as Node3D).global_position):
			continue
		for shape_node: Node in n.get_children():
			var cs := shape_node as CollisionShape3D
			if cs == null or cs.disabled or cs.shape == null:
				continue
			var mesh := _shape_mesh(cs.shape)
			if mesh:
				src.add_mesh(mesh, cs.global_transform)
	_nav_baking[c] = true
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void:
		_nav_mutex.lock()
		_nav_done.append([c, nm])
		_nav_mutex.unlock())


static var _shape_meshes := {}


## Malha equivalente à forma de colisão (para a navegação), guardada por forma.
static func _shape_mesh(shape: Shape3D) -> Mesh:
	var key := shape.get_instance_id()
	if _shape_meshes.has(key):
		return _shape_meshes[key]
	var mesh: PrimitiveMesh = null
	if shape is BoxShape3D:
		mesh = BoxMesh.new()
		(mesh as BoxMesh).size = (shape as BoxShape3D).size
	elif shape is CylinderShape3D:
		mesh = CylinderMesh.new()
		(mesh as CylinderMesh).top_radius = (shape as CylinderShape3D).radius
		(mesh as CylinderMesh).bottom_radius = (shape as CylinderShape3D).radius
		(mesh as CylinderMesh).height = (shape as CylinderShape3D).height
		(mesh as CylinderMesh).radial_segments = 8
	elif shape is SphereShape3D:
		mesh = SphereMesh.new()
		(mesh as SphereMesh).radius = (shape as SphereShape3D).radius
		(mesh as SphereMesh).height = (shape as SphereShape3D).radius * 2.0
		(mesh as SphereMesh).radial_segments = 8
		(mesh as SphereMesh).rings = 4
	if _shape_meshes.size() > 4000:
		_shape_meshes.clear()
	_shape_meshes[key] = mesh
	return mesh


## Recursos do bloco: um sorteio por célula de 8 m, mais pedras e galhos extras perto de
## onde se nasce (o kit inicial não tem ferramentas).
func _resource_spawns(c: Vector2i, near: Array) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, c.x, c.y, 1])
	var cells := int(CHUNK / CELL_SIZE)
	for cj in cells:
		for ci in cells:
			var x := c.x * CHUNK + (ci + rng.randf()) * CELL_SIZE
			var z := c.y * CHUNK + (cj + rng.randf()) * CELL_SIZE
			var roll := rng.randf()
			var rot := rng.randf() * TAU
			if Vector2(x, z).length() < 7.0 or _in_poi_list(x, z, near):
				continue
			var table: Dictionary = DENSITY.get(biome_at(x, z), {})
			for node_id: String in table:
				roll -= float(table[node_id])
				if roll < 0.0:
					out.append({"id": node_id, "pos": Vector3(x, _height_with(x, z, near), z), "rot": rot})
					break
	if c in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var start := RandomNumberGenerator.new()
		start.seed = hash([world_seed, c.x, c.y, 5])
		for k in START_PEBBLES + START_BRANCHES:
			var node_id := "pebbles" if k < START_PEBBLES else "branches"
			var x := c.x * CHUNK + start.randf() * CHUNK
			var z := c.y * CHUNK + start.randf() * CHUNK
			var d := Vector2(x, z).length()
			if d < 4.0 or d > 26.0:
				# Puxa para perto do começo (4 a 26 m).
				var dir := Vector2(x, z).normalized() if d > 0.1 else Vector2.RIGHT
				var p := dir * start.randf_range(4.0, 26.0)
				x = p.x
				z = p.y
			if _in_poi_list(x, z, near) or chunk_of(x, z) != c:
				continue
			out.append({"id": node_id, "pos": Vector3(x, _height_with(x, z, near), z), "rot": start.randf() * TAU})
	return out


## Por bloco em volta do começo (4 blocos): pedras soltas e galhos extras.
const START_PEBBLES := 8
const START_BRANCHES := 6


## Recurso colhido: volta depois do tempo, se o bloco estiver carregado (senão, ao recarregar).
func _on_resource_depleted(node_id: String, pos: Vector3, rot: float) -> void:
	var data := GameData.get_entry("nodes", node_id)
	var wait := float(data.get("respawn", 300.0))
	var key := "%d:%d" % [roundi(pos.x * 10.0), roundi(pos.z * 10.0)]
	_depleted[key] = Time.get_ticks_msec() + int(wait * 1000.0)
	if data.get("obstacle", false):
		_queue_rebake.call_deferred(pos)
	await get_tree().create_timer(wait, false).timeout
	if not is_inside_tree():
		return
	var c := chunk_of(pos.x, pos.z)
	var chunk: Dictionary = _chunks.get(c, {})
	if not chunk.get("content", false):
		return
	_depleted.erase(key)
	var node := resource_spawner.spawn({"id": node_id, "pos": pos, "rot": rot})
	if node:
		(chunk.resources as Array).append(node)
	if data.get("obstacle", false):
		_queue_rebake(pos)


## Refaz a navegação só do bloco do ponto (INF = todos os carregados).
func _queue_rebake(at := Vector3.INF) -> void:
	for c: Vector2i in _chunks:
		if not _chunks[c].get("nav"):
			continue
		# O obstáculo pode encostar no bloco vizinho: refaz os dois.
		var near_edge := false
		for off: Vector2 in [Vector2.ZERO, Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			near_edge = near_edge or c == chunk_of(at.x + off.x, at.z + off.y)
		if at == Vector3.INF or near_edge:
			_dirty_nav[c] = true


func _bake_navigation() -> void:
	pass  # cada bloco faz a sua (ver _load_content)


func _scatter_resources() -> void:
	pass  # por bloco (ver _load_content)


func _scatter_loot() -> void:
	pass  # o saque fica nos lugares


func _spawn_zombies() -> void:
	pass  # a população em volta dos jogadores cuida disso


## Jogadores nascem perto do começo, em cima do chão.
func _add_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var index := players_root.get_child_count()
	var x := (index - 2) * player_spacing
	player_spawner.spawn({"id": id, "pos": Vector3(x, ground_height(x, 0.0) + 0.3, 0.0)})


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
	_maybe_troll(players, night)
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
		# Os tipos seguem a região do jogador; se o monstro nasce na zona contaminada, vale ela.
		var spawn_rule := rule
		if biome_at(pos.x, pos.z) == "contaminated":
			spawn_rule = POPULATION.contaminated
		var z := spawn_zombie(_pick_weighted(spawn_rule.types), pos)
		free_zombies.append(z)
		spawned += 1


## Uma vez por noite, se alguém está numa zona contaminada, o Necromante surge nas ruínas
## mais perto dele.
func _maybe_necromancer(players: Array, night: bool) -> void:
	if not night:
		_necro_night = false
		return
	if _necro_night:
		return
	for p: Node3D in players:
		var at := Vector2(p.global_position.x, p.global_position.z)
		if biome_at(at.x, at.y) != "contaminated":
			continue
		var best: Dictionary = {}
		for poi: Dictionary in _pois_near(at.x, at.y):
			if poi.type == "ruins" and (best.is_empty() or at.distance_to(poi.pos) < at.distance_to(best.pos)):
				best = poi
		if best.is_empty() or at.distance_to(best.pos) > 200.0 or not is_chunk_ready(best.pos.x, best.pos.y):
			continue
		_necro_night = true
		spawn_zombie("necromancer", Vector3(best.pos.x, 0.0, best.pos.y + 4.0))
		return


## Uma vez por noite, se alguém está nas montanhas, o Troll ancião desce perto dele.
func _maybe_troll(players: Array, night: bool) -> void:
	if not night:
		_troll_night = false
		return
	if _troll_night:
		return
	for p: Node3D in players:
		if biome_at(p.global_position.x, p.global_position.z) == "mountain":
			var pos := _spawn_spot_near(p.global_position)
			if pos == Vector3.INF:
				return
			_troll_night = true
			spawn_zombie("colossus", pos)
			return


func _spawn_spot_near(center: Vector3) -> Vector3:
	for attempt in 12:
		var a := randf() * TAU
		var d := randf_range(POP_SPAWN_MIN, POP_SPAWN_MAX)
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		var c: Dictionary = _chunks.get(chunk_of(x, z), {})
		if not c.get("content", false) or biome_at(x, z) == "lake" or _in_poi(x, z):
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


static func _pick_weighted_rng(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id: String in weights:
		total += float(weights[id])
	var roll := rng.randf() * total
	for id: String in weights:
		roll -= float(weights[id])
		if roll <= 0.0:
			return id
	return weights.keys()[0]

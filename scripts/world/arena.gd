extends Node3D
## Arena de teste: gera a malha de navegação, cria um personagem para cada jogador
## conectado, espalha zumbis, itens e recursos coletáveis (árvores, rochas...).
## Rede: só o servidor cria e remove jogadores e zumbis; os MultiplayerSpawner da
## cena replicam isso para os clientes (inclusive quem entra no meio da partida).
## Tudo que estiver no grupo "navmesh_source" (chão, caixotes, futuras construções)
## entra no cálculo do caminho dos zumbis.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/enemies/zombie.tscn")

## Tipo de zumbi (id em zombies.json) → quantidade.
@export var spawns := {"walker": 4, "runner": 1}
@export var spawn_min_distance := 12.0
@export var spawn_max_distance := 25.0
## Distância entre os jogadores ao nascer.
@export var player_spacing := 1.5
## Itens espalhados para testar a coleta: [id, quantidade]. Saque de verdade: Fase 7.
@export var loot := [
	["berries", 8],
	["arrow", 8], ["medkit_basic", 1],
	["crossbow", 1], ["bolt", 10],
	["cloth", 5], ["herbs", 6], ["scrap_metal", 4],
	["spear_wood", 1], ["torch", 1],
	# Livros de habilidade (só caem de chefes; aqui para testar) e armas secundárias.
	["book_mend", 1], ["book_earth_wall", 1], ["shield_wood", 1], ["quiver_leather", 1], ["dagger", 2], ["boss_essence", 3],
	["axe_stone", 1], ["pickaxe_stone", 1], ["rod_wood", 1], ["bait_herb", 5],
]
@export var loot_radius := 14.0
## Recursos coletáveis (id em data/nodes/nodes.json) → quantidade.
@export var resources := {"tree": 25, "rock": 10, "berry_bush": 8, "nest": 6, "branches": 8}
@export var resource_min_distance := 7.0
@export var resource_max_distance := 45.0

const RESOURCE_SCRIPT := preload("res://scripts/world/resource_node.gd")
## Lago fixo (mesmo lugar em todas as máquinas): fonte de água suja.
const POND_POSITION := Vector3(-18.0, 0.0, 14.0)

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var players_root: Node3D = $Players
@onready var zombies_root: Node3D = $Zombies
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var items_root: Node3D = $Items
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var resources_root: Node3D = $Resources
@onready var resource_spawner: MultiplayerSpawner = $ResourceSpawner
@onready var structures_root: Node3D = $Structures
@onready var structure_spawner: MultiplayerSpawner = $StructureSpawner

var _rebake_queued := false


func _ready() -> void:
	_setup_level()
	_bake_navigation()
	# Todos (servidor e clientes) montam o personagem do mesmo jeito a partir de {id, pos}.
	player_spawner.spawn_function = _create_player
	WorldItems.register(items_root, item_spawner)
	resource_spawner.spawn_function = _create_resource
	Structures.register(structures_root, structure_spawner)
	# Clima (GDD 10.3), mesmo nome em todas as máquinas.
	var weather := Weather.new()
	weather.name = "Weather"
	add_child(weather)
	if not multiplayer.is_server():
		return
	Structures.layout_changed.connect(func() -> void: _queue_rebake(Structures.last_change))
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_add_player(1)
	for id in multiplayer.get_peers():
		_add_player(id)
	_spawn_zombies()
	_scatter_resources()
	_scatter_loot.call_deferred()  # depois da física do chão estar pronta


## Monta o cenário (todas as máquinas). Arena: nada extra. O mundo sobrescreve.
func _setup_level() -> void:
	pass


func _bake_navigation() -> void:
	nav_region.bake_navigation_mesh(false)


## Altura do chão em (x, z). Arena: plana.
func ground_height(_x: float, _z: float) -> float:
	return 0.0


func _add_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var index := players_root.get_child_count()
	player_spawner.spawn({"id": id, "pos": Vector3((index - 2) * player_spacing, 0.1, 0.0)})


## Chamado pelo PlayerSpawner em todas as máquinas. O nome define o dono (Player._enter_tree).
func _create_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(data.id)
	player.position = data.pos
	return player


func _remove_player(id: int) -> void:
	var player := players_root.get_node_or_null(str(id))
	if player:
		player.queue_free()


# --- Recursos coletáveis --------------------------------------------------------------

func _scatter_resources() -> void:
	var taken: Array[Vector3] = []
	for node_id: String in resources:
		for i in int(resources[node_id]):
			var pos := _free_spot(taken)
			taken.append(pos)
			resource_spawner.spawn({"id": node_id, "pos": pos, "rot": randf() * TAU})
	_queue_rebake()


## Ponto longe do centro, das paredes/caixotes e de outros recursos.
func _free_spot(taken: Array[Vector3]) -> Vector3:
	var pos := Vector3.ZERO
	for attempt in 30:
		var angle := randf() * TAU
		var dist := randf_range(resource_min_distance, resource_max_distance)
		pos = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var clear := (absf(pos.x) > 6.0 or absf(pos.z + 6.0) > 8.0) and pos.distance_to(POND_POSITION) > 6.0
		for other in taken:
			if other.distance_to(pos) < 3.0:
				clear = false
				break
		if clear:
			return pos
	return pos


## Todas as máquinas montam o recurso a partir de {id, pos, rot}.
func _create_resource(data: Dictionary) -> Node:
	var node: ResourceNode = RESOURCE_SCRIPT.new()
	node.node_id = data.id
	node.position = data.pos
	node.rotation.y = data.rot
	if multiplayer.is_server():
		node.depleted.connect(_on_resource_depleted)
	return node


## Servidor: o recurso volta depois de "respawn" segundos, no mesmo lugar.
func _on_resource_depleted(node_id: String, pos: Vector3, rot: float) -> void:
	var data := GameData.get_entry("nodes", node_id)
	if data.get("obstacle", false):
		_queue_rebake.call_deferred(pos)
	await get_tree().create_timer(float(data.get("respawn", 300.0)), false).timeout
	if not is_inside_tree():
		return
	resource_spawner.spawn({"id": node_id, "pos": pos, "rot": rot})
	if data.get("obstacle", false):
		_queue_rebake(pos)


## Refaz a malha de navegação dos zumbis (só o servidor usa) quando árvores/rochas mudam.
## at: onde mudou (o mundo usa para refazer só aquele pedaço; a arena refaz tudo).
func _queue_rebake(_at := Vector3.INF) -> void:
	if _rebake_queued:
		return
	_rebake_queued = true
	await get_tree().process_frame
	while nav_region.is_baking():
		await get_tree().process_frame
	_rebake_queued = false
	nav_region.bake_navigation_mesh(true)


# --- Saque e zumbis ---------------------------------------------------------------------

func _scatter_loot() -> void:
	for entry in loot:
		var angle := randf() * TAU
		var dist := randf_range(3.0, loot_radius)
		WorldItems.spawn(entry[0], entry[1], Vector3(cos(angle) * dist, 0.5, sin(angle) * dist))


func _spawn_zombies() -> void:
	for zombie_id: String in spawns:
		for i in int(spawns[zombie_id]):
			var angle := randf() * TAU
			var dist := randf_range(spawn_min_distance, spawn_max_distance)
			spawn_zombie(zombie_id, Vector3(cos(angle) * dist, 0.1, sin(angle) * dist))


## Servidor: cria um zumbi (o spawner replica). Usado também pela horda.
func spawn_zombie(zombie_id: String, pos: Vector3) -> Zombie:
	var z: Zombie = ZOMBIE_SCENE.instantiate()
	z.zombie_id = zombie_id
	z.position = Vector3(pos.x, ground_height(pos.x, pos.z) + 0.1, pos.z)
	z.rotation.y = randf() * TAU
	zombies_root.add_child(z, true)
	return z

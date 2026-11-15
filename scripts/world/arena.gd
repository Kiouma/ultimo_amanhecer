extends Node3D
## Arena de teste da Fase 1: gera a malha de navegação, cria um personagem para cada
## jogador conectado e espalha zumbis.
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
	["arrow", 8], ["feather", 6], ["stick", 10], ["stick", 6], ["bandage", 2], ["medkit_basic", 1],
	# Arma de fogo é achado raro (GDD 5.2): uma pistola vazia e um pouco de munição.
	["pistol_9mm", 1], ["ammo_9mm", 12],
	["wood", 10], ["wood", 10], ["stone", 8], ["cloth", 5], ["herbs", 6], ["scrap_metal", 4],
	["spear_wood", 1], ["torch", 1],
]
@export var loot_radius := 14.0

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var players_root: Node3D = $Players
@onready var zombies_root: Node3D = $Zombies
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var items_root: Node3D = $Items
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner


func _ready() -> void:
	nav_region.bake_navigation_mesh(false)
	# Todos (servidor e clientes) montam o personagem do mesmo jeito a partir de {id, pos}.
	player_spawner.spawn_function = _create_player
	WorldItems.register(items_root, item_spawner)
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_add_player(1)
	for id in multiplayer.get_peers():
		_add_player(id)
	_spawn_zombies()
	_scatter_loot.call_deferred()  # depois da física do chão estar pronta


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


func _scatter_loot() -> void:
	for entry in loot:
		var angle := randf() * TAU
		var dist := randf_range(3.0, loot_radius)
		WorldItems.spawn(entry[0], entry[1], Vector3(cos(angle) * dist, 0.5, sin(angle) * dist))


func _spawn_zombies() -> void:
	for zombie_id: String in spawns:
		for i in int(spawns[zombie_id]):
			var z: Zombie = ZOMBIE_SCENE.instantiate()
			z.zombie_id = zombie_id
			var angle := randf() * TAU
			var dist := randf_range(spawn_min_distance, spawn_max_distance)
			z.position = Vector3(cos(angle) * dist, 0.1, sin(angle) * dist)
			z.rotation.y = randf() * TAU
			zombies_root.add_child(z, true)

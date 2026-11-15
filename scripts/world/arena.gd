extends Node3D
## Arena de teste da Fase 1: gera a malha de navegação ao iniciar e espalha zumbis.
## Tudo que estiver no grupo "navmesh_source" (chão, caixotes, futuras construções)
## entra no cálculo do caminho dos zumbis.

const ZOMBIE_SCENE := preload("res://scenes/enemies/zombie.tscn")

## Tipo de zumbi (id em zombies.json) → quantidade.
@export var spawns := {"walker": 4, "runner": 1}
@export var spawn_min_distance := 12.0
@export var spawn_max_distance := 25.0

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	nav_region.bake_navigation_mesh(false)
	if multiplayer.is_server():
		_spawn_zombies()


func _spawn_zombies() -> void:
	var zombies := Node3D.new()
	zombies.name = "Zombies"
	add_child(zombies)
	for zombie_id: String in spawns:
		for i in int(spawns[zombie_id]):
			var z: Zombie = ZOMBIE_SCENE.instantiate()
			z.zombie_id = zombie_id
			var angle := randf() * TAU
			var dist := randf_range(spawn_min_distance, spawn_max_distance)
			z.position = Vector3(cos(angle) * dist, 0.1, sin(angle) * dist)
			z.rotation.y = randf() * TAU
			zombies.add_child(z, true)

class_name WaterSource
extends StaticBody3D
## Lago/poça (GDD 10: lagos). Com garrafa vazia, E enche com água suja; sem garrafa,
## E bebe direto (pouca água e mais risco de passar mal). Ferver na fogueira
## transforma água suja em água limpa.
## Fonte infinita: roda só na máquina de quem usa (não precisa do servidor).

@export var radius := 3.5
@export var drink_water := 10.0
@export var drink_sick_chance := 0.4
@export var drink_sick_damage := 8.0
## false: só a área de uso (lagos do mundo já têm água desenhada).
@export var show_visual := true


func _ready() -> void:
	collision_layer = 32  # só interagível: dá para pisar na margem/atravessar
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.3
	shape.shape = cyl
	shape.position.y = 0.1
	add_child(shape)
	if not show_visual:
		return

	var water := Weapon.cylinder(radius, 0.04, Color(0.18, 0.32, 0.38), Vector3(0, 0.03, 0))
	var mat := water.mesh.material as StandardMaterial3D
	mat.metallic = 0.3
	mat.roughness = 0.08
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	for i in 10:
		var a := TAU * i / 10.0 + 0.2
		var stone := Weapon.sphere(0.28 + 0.1 * (i % 3), Color(0.42, 0.42, 0.4), Vector3(cos(a) * (radius + 0.2), 0.05, sin(a) * (radius + 0.2)))
		stone.scale.y = 0.5
		add_child(stone)


func get_prompt() -> String:
	var player := _local_player()
	if player and player.inventory.count_of("empty_bottle") > 0:
		return tr("[E] Encher garrafa (água suja)")
	return tr("[E] Beber do lago (arriscado)")


func interact(player: Node3D) -> void:
	var inventory: Inventory = player.inventory
	if inventory.count_of("empty_bottle") > 0:
		inventory.remove_item("empty_bottle", 1)
		Crafting.give_result(inventory, {"result": "dirty_water", "amount": 1}, 1)
		player.notify(tr("Garrafa cheia de água suja: ferva na fogueira"))
		return
	if not player.survival.consume(0.0, drink_water):
		player.notify(tr("Você não está com sede"))
		return
	if randf() < drink_sick_chance:
		player.health.take_damage(drink_sick_damage, player)
		player.notify(tr("Você passou mal (água do lago)"))


func _local_player() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null

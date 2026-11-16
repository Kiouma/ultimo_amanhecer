extends SceneTree

func say(t: String) -> void:
	print("[%s] %s" % ["host" if "--host" in OS.get_cmdline_user_args() else "client", t])

func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	var is_host := "--host" in OS.get_cmdline_user_args()
	for i in 60 * (14 if is_host else 10):
		await physics_frame
	var level = current_scene.find_child("Level", true, false)
	if level.get_child_count() == 0:
		say("no level!")
		quit()
		return
	var world = level.get_child(0)
	var S = root.get_node("Structures")
	var lake0 = world.lakes[0][0] if world.lakes.size() > 0 else null
	say("seed %d lakes %d lake0 %s pois %d resources %d pieces %d items %d zombies %d players %d weather %s" % [world.world_seed, world.lakes.size(), lake0, world.pois.size(), world.get_node("Resources").get_child_count(), S.pieces().size(), world.get_node("Items").get_child_count(), world.get_node("Zombies").get_child_count(), world.get_node("Players").get_child_count(), world.get_node("Weather").state])
	var me = null
	for p in get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			me = p
	say("me %s pos %s floor %s" % [me.name if me else "-", me.global_position.snapped(Vector3.ONE * 0.1) if me else null, me.is_on_floor() if me else false])
	if is_host:
		world.get_node("Weather").set_state("rain")
		for i in 60 * 4:
			await physics_frame
	else:
		for i in 60 * 3:
			await physics_frame
		say("weather after host change: %s" % world.get_node("Weather").state)
	quit()

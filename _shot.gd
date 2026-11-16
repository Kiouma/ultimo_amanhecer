extends SceneTree

func _initialize() -> void:
	var SG = root.get_node("SaveGame")
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	SG.load_world = false
	SG.load_character = false
	current_scene._on_solo()
	for i in 40:
		await physics_frame
	var player = current_scene.find_child("1", true, false)
	var inv = player.inventory
	var prog = player.progression
	var d0: float = prog.mult("ranged.draw_time")
	for id in ["hunter_head", "hunter_chest", "hunter_legs", "hunter_feet", "warrior_ring", "hunter_ring", "arcane_neck"]:
		inv.add_item(id, 1)
	for id in ["hunter_head", "hunter_chest", "hunter_legs", "hunter_feet", "warrior_ring", "hunter_ring", "arcane_neck"]:
		for i in inv.slots.size():
			if inv.get_slot(i).get("id", "") == id:
				player.equipment.equip_from_inventory(i)
				break
	print("[probe] equipped %s" % [player.equipment.items.keys()])
	print("[probe] sets %s armor %.1f damage_taken mult %.3f draw_time %.2f->%.2f headshot %.2f max_mana %s" % [player.equipment.set_counts(), player.equipment.armor_total(), prog.mult("damage_taken"), d0, prog.mult("ranged.draw_time"), prog.mult("headshot_damage"), player.mana.max_value])
	player.equipment.unequip("ring1")
	print("[probe] after unequip ring1: %s, inv has warrior_ring %d" % [player.equipment.items.keys(), inv.count_of("warrior_ring")])
	var hud = current_scene.find_child("DebugHUD", true, false)
	hud.open_panel("character")
	for i in 15:
		await process_frame
	var img = root.get_texture().get_image()
	if img:
		img.save_png("res://_shot1.png")
	quit()

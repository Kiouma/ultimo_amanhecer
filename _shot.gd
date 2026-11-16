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
	var notes := []
	player.notified.connect(func(t): notes.append(t))
	var prog = player.progression
	var inv = player.inventory
	prog.levels["magic"] = 6
	inv.slots[8] = {"id": "grimoire_frost", "count": 1}
	inv.changed.emit()
	player.weapons.select(8)
	await process_frame
	player.weapons.use_selected()
	print("[probe] spells %s last %s note %s slot8 %s" % [prog.spells, prog.last_spell, notes.back(), inv.get_slot(8)])
	var caster = player.weapons.caster_for("frost_nova")
	var m1: float = caster.stat("mana", 0)
	var r1: float = caster.stat("radius", 0)
	inv.slots[8] = {"id": "grimoire_frost", "count": 1}
	inv.changed.emit()
	player.weapons._use_cooldown = 0
	player.weapons.use_selected()
	print("[probe] after 2nd frost grimoire: lvl %d mana %.1f->%.1f radius %.2f->%.2f note %s" % [prog.spell_level("frost_nova"), m1, caster.stat("mana", 0), r1, caster.stat("radius", 0), notes.back()])
	# toque no Q: conjura a última
	var mana0: float = player.mana.current
	player.weapons._q_down = Time.get_ticks_msec()
	await process_frame
	await create_timer(1.0).timeout
	print("[probe] tap Q cast %s: mana %.1f -> %.1f" % [prog.last_spell, mana0, player.mana.current])
	# roda: abre e escolhe firebolt
	var wheel = player.skill_wheel
	wheel.open(prog.spells.keys())
	wheel._aim = Vector2(0, -80)  # para cima = primeiro
	wheel.choice = wheel._pick()
	print("[probe] wheel up -> %s" % wheel.choice)
	player.weapons.select(2)
	await process_frame
	print("[probe] staff hud: %s" % player.weapons.hud_text())
	for i in 20:
		await process_frame
	var img = root.get_texture().get_image()
	if img:
		img.save_png("res://_shot1.png")
	quit()

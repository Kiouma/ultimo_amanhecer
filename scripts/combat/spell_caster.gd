class_name SpellCaster
extends Weapon
## Feitiço equipado na mão (GDD 5.4). Gasta mana, tem tempo de conjuração e recarga.
## Tipos ("kind" em spells.json): projectile (dardo de fogo), nova (gelo em volta:
## dano e lentidão), chain (raio que pula entre zumbis), heal (cura você e aliados
## perto) e wall (muro de terra temporário à frente).

const PROJECTILE := preload("res://scripts/combat/projectile.gd")

var casting := false

var _orb: MeshInstance3D
var _light: OmniLight3D
var _time := 0.0


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	if _orb:
		var pulse := 1.0 + sin(_time * 6.0) * 0.08 + (0.4 if casting else 0.0)
		_orb.scale = Vector3.ONE * pulse
		_light.light_energy = 1.2 * pulse


## Nível da habilidade (grimórios repetidos): mais mana, mais efeito.
func stat(key: String, default: float) -> float:
	var value := super(key, default)
	var up := maxi(spell_level() - 1, 0)
	match key:
		"mana": value *= 1.0 + 0.2 * up
		"damage", "heal": value *= 1.0 + 0.2 * up
		"radius", "range", "chain_range": value *= 1.0 + 0.12 * up
		"duration": value *= 1.0 + 0.15 * up
		"chains": value += floorf(up / 2.0)
	# Canalização (cajado): mais efeito, mesmo custo base.
	if _power > 1.0 and key in ["damage", "heal", "radius", "range", "chain_range", "duration"]:
		value *= _power
	return value


var _power := 1.0


func spell_level() -> int:
	return maxi(user.progression.spell_level(str(data.get("id", ""))), 1) if user and user.progression else 1


func handle_attack(_held: bool, just_pressed: bool) -> void:
	if just_pressed:
		cast()


## Também usado pelo atalho Q (feitiço rápido), mesmo com outra arma na mão.
func cast(power := 1.0) -> bool:
	if casting or cooldown > 0.0:
		return false
	_power = power
	var block := _cast_block_reason()
	if block != "":
		user.notify(block)
		return false
	var mana: StatPool = user.get(&"mana")
	if mana and not mana.spend(stat("mana", 15.0)):
		return false
	casting = true
	cooldown = stat("cooldown", 1.0) + stat("cast_time", 0.4)
	play_body_anim(&"Spell_Simple_Shoot")
	hud_changed.emit()
	await get_tree().create_timer(stat("cast_time", 0.4)).timeout
	casting = false
	if not is_instance_valid(user):
		return false
	_launch()
	_power = 1.0
	hud_changed.emit()
	return true


## Checagem antes de gastar mana ("" = pode).
func _cast_block_reason() -> String:
	if str(data.get("kind", "")) == "wall":
		var slot := Structures.wall_slot_in_front(user)
		var reason := Structures.check_build("earth_wall", slot[0], slot[1], user.global_position)
		if reason != "":
			return "Sem espaço para o muro: " + reason.to_lower()
	return ""


func _launch() -> void:
	match str(data.get("kind", "projectile")):
		"nova": _cast_nova()
		"chain": _cast_chain()
		"heal": _cast_heal()
		"wall": _cast_wall()
		_: _cast_projectile()
	make_noise(stat("noise", 0.6))
	Sfx.play("spell", user.global_position + Vector3.UP * 1.4, -3.0)
	count_use()
	user.progression.gain("magic", 1.5)
	kick(Vector3(0, 0, 0.08), Vector3(0.3, 0, 0), 0.2)


func _cast_nova() -> void:
	var radius := stat("radius", 5.0)
	for z: Node3D in get_tree().get_nodes_in_group("zombies"):
		if z.is_dead() or z.global_position.distance_to(user.global_position) > radius:
			continue
		deal_damage(z, stat("damage", 10.0))
		z.request_slow(stat("slow", 0.35), stat("slow_time", 4.0))
	_ring_fx(user, user.global_position, radius, _school_color())
	user.broadcast_fx(&"ring", user.global_position, user.global_position + Vector3.RIGHT * radius, _school_color())


func _cast_chain() -> void:
	var hit := aim_ray(stat("range", 30.0), 0.0)
	var first: Node3D = hit.get("collider") as Node3D
	var from := head.global_position + (-head.global_basis.z) * 0.6
	if not first is Zombie or first.is_dead():
		# Errou: o raio some no ponto mirado.
		spawn_tracer(user, from, hit.position)
		user.broadcast_fx(&"tracer", from, hit.position)
		return
	var damage := stat("damage", 25.0) * Weather.lightning_factor(get_tree())
	var hit_list: Array = []
	var current: Node3D = first
	for i in int(stat("chains", 3)) + 1:
		var to := current.global_position + Vector3.UP * 1.2
		spawn_tracer(user, from, to)
		user.broadcast_fx(&"tracer", from, to)
		deal_damage(current, damage)
		hit_list.append(current)
		damage *= 0.8
		from = to
		var next: Node3D = null
		for z: Node3D in get_tree().get_nodes_in_group("zombies"):
			if z in hit_list or z.is_dead():
				continue
			var d := z.global_position.distance_to(current.global_position)
			if d <= stat("chain_range", 6.0) and (next == null or d < next.global_position.distance_to(current.global_position)):
				next = z
		if next == null:
			break
		current = next


## Cura você e quem estiver perto (Curandeiro no co-op).
func _cast_heal() -> void:
	var amount := stat("heal", 30.0) * user.progression.mult("heal") * user.progression.mult("magic.damage")
	var radius := stat("radius", 5.0)
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.global_position.distance_to(user.global_position) <= radius:
			var h := Health.find_in(p)
			if h and not h.is_dead:
				h.heal_by(amount, user)
	_ring_fx(user, user.global_position, radius, _school_color())
	user.broadcast_fx(&"ring", user.global_position, user.global_position + Vector3.RIGHT * radius, _school_color())


func _cast_wall() -> void:
	Structures.cast_earth_wall(user, stat("duration", 20.0))


## Anel que cresce no chão (nova, cura).
static func _ring_fx(where: Node3D, center: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.85
	mesh.outer_radius = 1.0
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.7)
	mat.emission_enabled = true
	mat.emission = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	where.get_tree().current_scene.add_child(ring)
	ring.global_position = center + Vector3.UP * 0.2
	ring.scale = Vector3(0.3, 1.0, 0.3)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.35)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(ring.queue_free)


func _cast_projectile() -> void:
	var from := head.global_position + (-head.global_basis.z) * 0.7 + head.global_basis.x * 0.15
	var aim_point: Vector3 = aim_ray(stat("range", 80.0)).position
	var bolt: Area3D = PROJECTILE.new()
	bolt.damage = stat("damage", 30.0) * user.death_penalty.damage_factor()
	bolt.speed = stat("speed", 22.0)
	bolt.caster = user
	bolt.color = _school_color()
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.direction = (aim_point - from).normalized()
	user.broadcast_fx(&"bolt", from, aim_point, bolt.color)


func hud_text() -> String:
	var cost := int(stat("mana", 15.0))
	if casting:
		return "conjurando..."
	if cooldown > 0.0:
		return "recarga %.1fs · %d mana" % [cooldown, cost]
	return "%d mana" % cost


func _school_color() -> Color:
	match str(data.get("school", "")):
		"fire": return Color(1.0, 0.45, 0.1)
		"ice": return Color(0.5, 0.8, 1.0)
		"lightning": return Color(0.8, 0.8, 1.0)
		"life": return Color(0.4, 1.0, 0.5)
		"earth": return Color(0.75, 0.55, 0.3)
		_: return Color(0.9, 0.6, 1.0)


func _build_viewmodel() -> void:
	var color := _school_color()
	_orb = sphere(0.035, color, Vector3.ZERO, true)
	add_child(_orb)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 3.0
	_light.light_energy = 1.2
	add_child(_light)

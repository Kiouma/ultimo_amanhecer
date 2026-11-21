class_name SkillCaster
extends Weapon
## Executa uma habilidade (data/skills) para o dono. Um objeto por habilidade (guarda a
## recarga), criado pelo nó Skills. Tipos ("kind"):
## - strike: golpe à frente (um ou vários: "hits"); "grab" puxa o inimigo mais perto;
## - dash: avanço ("to_target" até o alvo, "through" acerta no caminho, "teleport",
##   "invuln" = invulnerável por um instante);
## - nova: área em volta do personagem; ground: área no círculo do chão ("leap" salta
##   até lá, "delay" demora para cair, "duration" acerta várias vezes);
## - projectile: flechas/dardos ("count" em leque, "pierce", "pull", "self_push");
## - chain: raio que salta; link: Elo Arcano; buff: efeito em si mesmo;
## - channel: segurar a tecla (Redemoinho); heal e wall: habilidades dos livros.
## Efeitos no acerto: "push", "pull", "stun", "slow", "effect" (poison, burn, bleed,
## vulnerable) — pedidos ao servidor (Zombie.request_status).
## Dano: habilidades de arma usam o dano da arma na mão × "damage_mult"; magias usam
## "damage" × dano mágico. Cada nível: +6% de dano/cura/efeito e +2% de área/duração.

const PROJECTILE := preload("res://scripts/combat/projectile.gd")
const ARROW := preload("res://scripts/combat/arrow.gd")

var skills: Skills
var casting := false
var _channel_timer := 0.0
var _channeling := false


func level() -> int:
	return maxi(skills.level_of(str(data.get("id", ""))), 1) if skills else 1


## Valor do dado com os bônus dos marcos já alcançados (5, 10, 15, 20).
func base(key: String, default: float) -> float:
	var value := float(data.get(key, default))
	var marks: Dictionary = data.get("milestones", {})
	for m: int in Skills.MILESTONES:
		if level() >= m:
			value += float(marks.get(str(m), {}).get(key, 0.0))
	return value


func stat(key: String, default: float) -> float:
	var value := base(key, default)
	var up := level() - 1
	var prog := user.progression if user else null
	match key:
		"damage", "damage_mult", "heal", "effect_power", "amount":
			value *= 1.0 + 0.06 * up
		"radius", "duration", "effect_time":
			value *= 1.0 + 0.02 * up
		"cooldown":
			value *= 1.0 - Progression.cooldown_reduction(user)
			if is_spell() and prog:
				value = prog.apply("magic.cooldown", value)
			value = maxf(value, 0.2)
		"cost":
			if prog:
				value = prog.apply("magic.mana" if cost_type() == "mana" else category() + ".stamina_cost", value)
	return value


func is_spell() -> bool:
	return weapon_type() == "spell"


func cost_type() -> String:
	return str(data.get("cost_type", "mana"))


func kind() -> String:
	return str(data.get("kind", ""))


func pool() -> StatPool:
	return user.mana if cost_type() == "mana" else user.stamina


func color() -> Color:
	match str(data.get("school", "")):
		"fire": return Color(1.0, 0.45, 0.1)
		"ice": return Color(0.5, 0.8, 1.0)
		"lightning": return Color(0.8, 0.8, 1.0)
		"life": return Color(0.4, 1.0, 0.5)
		"earth": return Color(0.75, 0.55, 0.3)
		"arcane": return Color(0.75, 0.5, 1.0)
		"blood": return Color(0.85, 0.15, 0.25)
	return Color(1.0, 0.85, 0.45)


## Dano de um acerto: arma na mão × multiplicador, ou dano da magia × dano mágico.
func base_damage() -> float:
	if is_spell():
		return stat("damage", 20.0) * user.progression.mult("magic.damage")
	var w: Weapon = user.weapons.current()
	var weapon_damage := w.stat("damage", 10.0) if w and not w is SkillCaster else 10.0
	return weapon_damage * stat("damage_mult", 1.0)


## Por que não dá para usar agora ("" = dá).
func block_reason() -> String:
	var name_text := tr(str(data.get("name", "")))
	if casting:
		return ""
	if cooldown > 0.0:
		return tr("%s: recarga %.1f s") % [name_text, cooldown]
	if str(data.get("requires", "")) == "bow":
		var w: Weapon = user.weapons.current()
		if w == null or w.weapon_type() != "bow":
			return tr("%s precisa de um arco na mão") % name_text
		if data.get("ammo", false) and user.inventory.count_of(_ammo_id()) <= 0:
			return tr("Sem munição")
	var p := pool()
	if p and not p.has(stat("cost", 10.0)):
		return tr("Mana insuficiente") if cost_type() == "mana" else tr("Stamina insuficiente")
	match kind():
		"strike":
			if data.get("grab", false) and _grab_target() == null:
				return tr("Nenhum inimigo ao alcance")
		"link":
			if not user.has_target() and not user.has_ally_target(stat("range", 20.0)) and _nearest_ally() == null:
				return tr("Selecione um inimigo (Tab) ou fique perto de um aliado")
		"wall":
			var slot := Structures.wall_slot_in_front(user)
			var reason := Structures.check_build("earth_wall", slot[0], slot[1], user.global_position)
			if reason != "":
				return tr("Sem espaço para o muro: ") + reason.to_lower()
	return ""


func _ammo_id() -> String:
	var w: Weapon = user.weapons.current()
	return str(w.data.get("ammo", "arrow")) if w else "arrow"


## Paga o custo e começa a recarga. false se não deu.
func _pay() -> bool:
	var p := pool()
	if p and not p.spend(stat("cost", 10.0)):
		return false
	if p:
		p.mark_action()
	if data.get("ammo", false):
		user.inventory.remove_item(_ammo_id(), 1)
	cooldown = stat("cooldown", 1.0)
	return true


## Usa a habilidade. point: centro da área (habilidades "ground").
func cast(point := Vector3.INF) -> bool:
	if casting or block_reason() != "" or not _pay():
		return false
	casting = true
	var cast_time := stat("cast_time", 0.4)
	var anim := StringName(str(data.get("anim", "Spell_Simple_Shoot")))
	match kind():
		"dash":
			user.play_action_synced(anim, maxf(cast_time, 0.3))
		"ground":
			user.face_point(point)
			user.play_action_synced(anim, maxf(cast_time, 0.3), true)
		"projectile", "chain", "link":
			play_body_anim(anim, maxf(cast_time, 0.3), true)
		_:
			play_body_anim(anim, maxf(cast_time, 0.3))
	if kind() != "dash":
		await get_tree().create_timer(cast_time * 0.5).timeout
	if not is_instance_valid(user) or user.health.is_dead:
		casting = false
		return false
	match kind():
		"strike": await _strike()
		"dash": await _dash()
		"nova": _nova(user.global_position)
		"ground": await _ground(point)
		"projectile": _projectile()
		"chain": _chain()
		"link": _link()
		"buff": user.effects.apply(str(data.get("effect", "")), stat("effect_time", 8.0), stat("effect_power", 1.0))
		"heal": _heal()
		"wall": Structures.cast_earth_wall(user, stat("duration", 20.0))
	casting = false
	count_use()
	make_noise(0.4)
	Sfx.play("spell" if is_spell() else "swing", user.global_position + Vector3.UP * 1.4, -3.0)
	if is_spell():
		user.progression.gain("magic", 1.5)
	return true


# --- Acerto e efeitos ------------------------------------------------------------------------

## Dano + efeitos num inimigo. Retorna true se acertou algo vivo.
func _hit(target: Node, mult := 1.0, extra_stun := 0.0) -> bool:
	if not deal_damage(target, base_damage() * mult):
		return false
	_effects(target, extra_stun)
	return true


## Empurrão, puxão, atordoamento, lentidão e o "effect" da habilidade.
func _effects(target: Node, extra_stun := 0.0) -> void:
	var z := target as Zombie
	if z == null or z.is_dead():
		return
	if stat("push", 0.0) > 0.0:
		z.request_status("push", stat("push", 0.0), 0.0, user)
	if data.get("pull", false) or data.get("grab", false):
		z.request_status("pull", 0.0, 0.0, user)
	var stun := stat("stun", 0.0) + extra_stun
	if stun > 0.0:
		z.request_status("stun", 0.0, stun, user)
	if stat("slow", 0.0) > 0.0:
		z.request_status("slow", stat("slow", 0.0), stat("slow_time", 3.0), user)
	var effect := str(data.get("effect", ""))
	if effect in ["poison", "burn", "bleed", "vulnerable"] and kind() != "buff":
		for i in maxi(int(stat("effect_stacks", 1.0)), 1):
			z.request_status(effect, stat("effect_power", 3.0), stat("effect_time", 5.0), user)


func _alive_zombies() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(z: Node) -> bool: return not z.is_dead())


## Inimigos dentro de um raio (no plano) de um ponto.
func _in_radius(center: Vector3, radius: float) -> Array:
	return _alive_zombies().filter(func(z: Node3D) -> bool:
		return Vector2(z.global_position.x - center.x, z.global_position.z - center.z).length() <= radius \
			and absf(z.global_position.y - center.y) < 3.0)


## Inimigos num cone à frente do personagem.
func _in_cone(reach: float, arc_deg: float) -> Array:
	var forward := -user.global_basis.z
	return _in_radius(user.global_position, reach).filter(func(z: Node3D) -> bool:
		var to := Vector3(z.global_position.x - user.global_position.x, 0.0, z.global_position.z - user.global_position.z)
		return to.length() < 0.8 or rad_to_deg(forward.angle_to(to.normalized())) <= arc_deg * 0.5)


# --- Tipos -------------------------------------------------------------------------------------

func _strike() -> void:
	var w: Weapon = user.weapons.current()
	var reach := (w.stat("range", 2.0) if w and not w is SkillCaster else 1.8) + stat("reach", 0.3)
	if data.get("grab", false):
		var z := _grab_target()
		if z:
			_hit(z)
		return
	var hits := int(stat("hits", 1.0))
	for i in hits:
		var last := i == hits - 1
		if i > 0:
			await get_tree().create_timer(stat("hit_interval", 0.2)).timeout
			if not is_instance_valid(user) or user.health.is_dead:
				return
			user.play_action_synced(&"Punch_Cross" if i % 2 == 1 else &"Punch_Jab", stat("hit_interval", 0.2) + 0.1, true)
		var mult := stat("last_mult", 1.0) if last and hits > 1 else 1.0
		var stun := stat("last_stun", 0.0) if last else 0.0
		for z: Node in _in_cone(reach, stat("arc", 90.0)):
			_hit(z, mult, stun)


## Agarrão: o alvo (se perto) ou o inimigo mais perto à frente.
func _grab_target() -> Zombie:
	var reach := stat("range", 7.0)
	if user.has_target() and user.target is Zombie and user.target.global_position.distance_to(user.global_position) <= reach:
		return user.target
	var best: Zombie = null
	for z: Node in _in_cone(reach, 120.0):
		if best == null or z.global_position.distance_to(user.global_position) < best.global_position.distance_to(user.global_position):
			best = z
	return best


func _move_dir() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() > 0.1:
		return (Basis(Vector3.UP, user.camera_yaw) * Vector3(input.x, 0.0, input.y)).normalized()
	return -user.global_basis.z


func _dash() -> void:
	var distance := stat("distance", 6.0)
	var dir := _move_dir()
	if data.get("to_target", false) and user.has_target():
		var to: Vector3 = user.target.global_position - user.global_position
		to.y = 0.0
		dir = to.normalized()
		distance = clampf(to.length() - 1.3, 0.0, distance)
	user.face_point(user.global_position + dir)
	if data.get("teleport", false):
		user.teleport_toward(dir, distance)
		_flash(user.global_position)
		return
	var speed := stat("speed", 20.0)
	var time := distance / speed
	user.start_dash(dir * speed, time, stat("invuln", 0.0))
	var hit_list: Array = []
	var elapsed := 0.0
	while elapsed < time:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if not is_instance_valid(user):
			return
		if data.get("through", false):
			for z: Node in _in_radius(user.global_position, stat("radius", 1.5)):
				if not z in hit_list:
					hit_list.append(z)
					_hit(z)
	if data.get("to_target", false):
		user.play_action_synced(&"Sword_Regular_C", 0.4, true)
		for z: Node in _in_radius(user.global_position, stat("radius", 2.2)):
			_hit(z)
		_ring(user.global_position, stat("radius", 2.2))


func _nova(center: Vector3) -> void:
	var radius := stat("radius", 5.0)
	var damages := float(data.get("damage", 0.0)) > 0.0 or float(data.get("damage_mult", 0.0)) > 0.0
	for z: Node in _in_radius(center, radius):
		if damages:
			_hit(z)
		else:
			_effects(z)
	_ring(center, radius)


func _ground(point: Vector3) -> void:
	if data.get("leap", false):
		var to := point - user.global_position
		to.y = 0.0
		var time := 0.45
		user.start_dash(to / time, time, 0.0, true)
		await get_tree().create_timer(time).timeout
		if not is_instance_valid(user):
			return
		point = user.global_position
	var delay := stat("delay", 0.0)
	if delay > 0.0:
		_ring(point, stat("radius", 3.0), delay)
		if str(data.get("school", "")) == "fire":
			_meteor_fx(point, delay)
		await get_tree().create_timer(delay).timeout
	var duration := stat("duration", 0.0)
	if duration <= 0.0:
		_nova(point)
		return
	var interval := maxf(stat("interval", 0.5), 0.2)
	var t := 0.0
	while t < duration:
		_nova(point)
		_arrows_fx(point, stat("radius", 3.0))
		await get_tree().create_timer(interval).timeout
		t += interval
		if not is_instance_valid(user):
			return


func _projectile() -> void:
	var hit: Dictionary = user.aim_ray(stat("range", 60.0), HIT_MASK, true)
	var aim: Vector3 = hit.position
	var from: Vector3 = user.shot_origin(aim)
	var forward := (aim - from).normalized()
	var count := maxi(int(stat("count", 1.0)), 1)
	var spread := deg_to_rad(stat("spread", 0.0))
	var damage := base_damage() * user.death_penalty.damage_factor()
	for i in count:
		var angle := 0.0 if count == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (count - 1))
		var dir := forward.rotated(Vector3.UP, angle)
		if weapon_type() == "bow":
			var arrow: Node3D = ARROW.new()
			arrow.damage = damage
			arrow.velocity = dir * stat("speed", 50.0)
			arrow.caster = user
			arrow.recover_chance = 0.0
			arrow.item_id = _ammo_id()
			arrow.pierce = int(stat("pierce", 0.0))
			arrow.on_hit = _effects
			get_tree().current_scene.add_child(arrow)
			arrow.global_position = from
			user.broadcast_fx(&"arrow", from, from + dir * stat("speed", 50.0))
		else:
			var bolt: Area3D = PROJECTILE.new()
			bolt.damage = damage
			bolt.speed = stat("speed", 24.0)
			bolt.caster = user
			bolt.color = Color(0.55, 0.55, 0.6) if str(data.get("visual", "")) == "chain" else color()
			bolt.weapon_type = weapon_type()
			bolt.on_hit = _effects
			bolt.max_lifetime = stat("range", 60.0) / bolt.speed
			get_tree().current_scene.add_child(bolt)
			bolt.global_position = from
			bolt.direction = dir
			user.broadcast_fx(&"bolt", from, from + dir * stat("range", 60.0), bolt.color)
	if stat("self_push", 0.0) > 0.0:
		var back := -Vector3(forward.x, 0.0, forward.z).normalized()
		user.start_dash(back * 14.0, stat("self_push", 0.0) / 14.0)


func _chain() -> void:
	var hit: Dictionary = user.aim_ray(stat("range", 30.0), HIT_MASK, true)
	var first: Node3D = hit.get("collider") as Node3D
	var from: Vector3 = user.shot_origin(hit.position)
	if not first is Zombie or first.is_dead():
		spawn_tracer(user, from, hit.position)
		user.broadcast_fx(&"tracer", from, hit.position)
		return
	var mult := Weather.lightning_factor(get_tree())
	var hit_list: Array = []
	var current: Node3D = first
	for i in int(stat("chains", 3.0)) + 1:
		var to := current.global_position + Vector3.UP * 1.2
		spawn_tracer(user, from, to)
		user.broadcast_fx(&"tracer", from, to)
		_hit(current, mult)
		hit_list.append(current)
		mult *= 0.8
		from = to
		var next: Node3D = null
		for z: Node3D in _alive_zombies():
			if z in hit_list:
				continue
			var d := z.global_position.distance_to(current.global_position)
			if d <= stat("chain_range", 6.0) and (next == null or d < next.global_position.distance_to(current.global_position)):
				next = z
		if next == null:
			break
		current = next


## Elo Arcano: drena o inimigo alvo (dano e mana de volta) ou passa mana a um aliado.
func _link() -> void:
	var amount := stat("amount", 40.0)
	if user.has_target() and not user.has_ally_target(stat("range", 20.0)):
		var t: Node3D = user.target
		spawn_tracer(user, user.shot_origin(t.global_position), t.global_position + Vector3.UP * 1.2)
		if _hit(t):
			user.mana.restore(amount)
		return
	var ally: Player = user.ally_target if user.has_ally_target(stat("range", 20.0)) else _nearest_ally()
	if ally:
		spawn_tracer(user, user.shot_origin(ally.global_position), ally.global_position + Vector3.UP * 1.2)
		ally.give_mana(amount)
		user.notify(tr("Passou %d de mana para %s") % [roundi(amount), ally.display_name()])


func _nearest_ally() -> Player:
	var best: Player = null
	for p: Node in get_tree().get_nodes_in_group("player"):
		var other := p as Player
		if other == null or other == user or other.health.is_dead:
			continue
		var d := other.global_position.distance_to(user.global_position)
		if d <= stat("range", 20.0) and (best == null or d < best.global_position.distance_to(user.global_position)):
			best = other
	return best


func _heal() -> void:
	var amount := stat("heal", 30.0) * user.progression.mult("heal") * user.progression.mult("magic.damage")
	var radius := stat("radius", 5.0)
	# Com um aliado selecionado (perto), a cura vai inteira nele (etapa 9).
	if user.has_ally_target(25.0):
		var ally: Player = user.ally_target
		ally.health.heal_by(amount * 1.3, user)
		spawn_tracer(user, user.shot_origin(ally.global_position), ally.global_position + Vector3.UP * 1.2)
		_ring(ally.global_position, 1.5)
		return
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.global_position.distance_to(user.global_position) <= radius:
			var h := Health.find_in(p)
			if h and not h.is_dead:
				h.heal_by(amount, user)
	_ring(user.global_position, radius)


# --- Canalização (Redemoinho) ------------------------------------------------------------------

func start_channel() -> void:
	_channeling = true
	_channel_timer = 0.0


## Chamado todo quadro enquanto a tecla está segurada. false = parou (sem stamina).
func channel_tick() -> bool:
	if not _channeling:
		return false
	_channel_timer -= get_process_delta_time()
	if _channel_timer > 0.0:
		return true
	var interval := stat("interval", 0.35)
	_channel_timer = interval
	var p := pool()
	if p and not p.spend(stat("cost", 4.0)):
		return false
	if p:
		p.mark_action()
	user.play_action_synced(StringName(str(data.get("anim", "Melee_2H_Attack_Spinning"))), interval + 0.1, true)
	var leech := stat("leech", 0.0)
	for z: Node in _in_radius(user.global_position, stat("radius", 2.5)):
		var dealt := base_damage()
		if _hit(z) and leech > 0.0:
			user.health.heal(dealt * leech)
	count_use()
	return true


func stop_channel() -> void:
	_channeling = false
	cooldown = stat("cooldown", 0.5)


# --- Efeitos visuais ----------------------------------------------------------------------------

func _ring(center: Vector3, radius: float, time := 0.0) -> void:
	ring_fx(user, center, radius, color())
	user.broadcast_fx(&"ring", center, center + Vector3.RIGHT * radius, color())
	if time > 0.0:
		# Aviso no chão enquanto a área não cai (Meteoro).
		var mark := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = 0.05
		mark.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(color(), 0.25)
		mark.material_override = mat
		get_tree().current_scene.add_child(mark)
		mark.global_position = center + Vector3.UP * 0.05
		get_tree().create_timer(time).timeout.connect(mark.queue_free)


func _flash(at: Vector3) -> void:
	ring_fx(user, at, 1.5, color())
	user.broadcast_fx(&"ring", at, at + Vector3.RIGHT * 1.5, color())


func _meteor_fx(point: Vector3, time: float) -> void:
	var rock := Weapon.sphere(0.7, color(), Vector3.ZERO, true)
	get_tree().current_scene.add_child(rock)
	rock.global_position = point + Vector3(4.0, 18.0, 2.0)
	var tw := rock.create_tween()
	tw.tween_property(rock, "global_position", point, time).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Zombie.explosion_fx(get_tree().current_scene, point + Vector3.UP * 0.5)
		rock.queue_free())


func _arrows_fx(point: Vector3, radius: float) -> void:
	for i in 4:
		var at := point + Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius)) * 0.7
		spawn_tracer(user, at + Vector3(0.5, 9.0, 0.3), at)
		user.broadcast_fx(&"tracer", at + Vector3(0.5, 9.0, 0.3), at)


func hud_text() -> String:
	return ""


## Anel que cresce no chão (áreas, cura, invocação do Necromante).
static func ring_fx(where: Node3D, center: Vector3, radius: float, ring_color: Color) -> void:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.85
	mesh.outer_radius = 1.0
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(ring_color, 0.7)
	mat.emission_enabled = true
	mat.emission = ring_color
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

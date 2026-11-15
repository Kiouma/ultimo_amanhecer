class_name Firearm
extends Weapon
## Arma de fogo com tiro instantâneo (hitscan). Semiautomática: um tiro por clique.
## Munição: o pente fica na arma; a reserva é a munição do tipo certo no inventário
## (campo "ammo" do equipment.json). Recarregar consome do inventário.
## Botão direito mira: menos dispersão e zoom (GDD 5.2).

@export var aim_fov := 55.0
## Dano extra ao acertar a cabeça (a trilha do Atirador aumenta isso depois, GDD 4.2).
@export var headshot_multiplier := 2.0

## Balas no pente: guardadas no slot do inventário (sobrevive a trocar de arma).
var magazine: int:
	get:
		return int(slot.get("mag", 0))
	set(value):
		slot["mag"] = value
var reloading := false

var _default_fov := 80.0
var _muzzle: Node3D
var _flash: OmniLight3D


func setup(entry: Dictionary, owner_player: Player, cam: Camera3D, head_node: Node3D) -> void:
	super(entry, owner_player, cam, head_node)
	_default_fov = cam.fov


func _process(delta: float) -> void:
	super(delta)
	if not visible:
		return
	var aiming := Input.is_action_pressed("aim") and not reloading
	camera.fov = lerpf(camera.fov, aim_fov if aiming else _default_fov, minf(12.0 * delta, 1.0))
	var target_x := 0.0 if aiming else _rest_position.x
	position.x = lerpf(position.x, target_x, minf(12.0 * delta, 1.0))


func handle_attack(_held: bool, just_pressed: bool) -> void:
	if not just_pressed or reloading or cooldown > 0.0:
		return
	if magazine <= 0:
		reload()
		return
	_fire()


func _fire() -> void:
	magazine -= 1
	cooldown = 1.0 / stat("fire_rate", 4.0)
	var aiming := Input.is_action_pressed("aim")
	var spread := stat("spread_aim", 0.3) if aiming else stat("spread_hip", 1.5)
	if Vector2(user.velocity.x, user.velocity.z).length() > 0.5:
		spread *= 1.8
	var hit := aim_ray(stat("range", 60.0), spread)

	if not hit.has("miss"):
		var damage := stat("damage", 25.0)
		var collider: Object = hit.get("collider")
		if collider is Node3D and hit.position.y - collider.global_position.y > 1.45:
			damage *= headshot_multiplier
		if not deal_damage(collider, damage):
			_spawn_impact(hit.position)

	_spawn_tracer(hit.position)
	_flash.visible = true
	get_tree().create_timer(0.05).timeout.connect(func() -> void: _flash.visible = false)
	make_noise(stat("noise", 0.8))
	head.rotation.x += deg_to_rad(1.2)  # recuo da câmera
	kick(Vector3(0, 0.01, 0.06), Vector3(deg_to_rad(8), 0, 0))
	play_body_anim(&"Pistol_Shoot")
	hud_changed.emit()
	if magazine == 0 and reserve() > 0:
		get_tree().create_timer(0.3).timeout.connect(reload)


func reload() -> void:
	var capacity := int(stat("magazine", 12))
	if reloading or magazine >= capacity or reserve() <= 0:
		return
	reloading = true
	hud_changed.emit()
	play_body_anim(&"Pistol_Reload")
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", _rest_rotation.x - 0.8, 0.25)
	tw.tween_interval(maxf(stat("reload_time", 1.6) - 0.5, 0.1))
	tw.tween_property(self, "rotation:x", _rest_rotation.x, 0.25)
	await tw.finished
	if not reloading:  # trocou de arma no meio
		return
	var taken := mini(capacity - magazine, reserve())
	if taken > 0 and user.inventory.remove_item(_ammo_id(), taken):
		magazine += taken
	reloading = false
	hud_changed.emit()


## Munição desse calibre no inventário.
func reserve() -> int:
	return user.inventory.count_of(_ammo_id()) if user and user.inventory else 0


func _ammo_id() -> String:
	return str(data.get("ammo", ""))


func on_unequip() -> void:
	reloading = false
	camera.fov = _default_fov


func hud_text() -> String:
	if reloading:
		return "recarregando..."
	return "%d / %d" % [magazine, reserve()]


func _build_viewmodel() -> void:
	var dark := Color(0.12, 0.12, 0.13)
	add_child(box(Vector3(0.035, 0.05, 0.2), dark, Vector3(0, 0.0, -0.05)))          # ferrolho
	add_child(box(Vector3(0.03, 0.11, 0.045), Color(0.2, 0.17, 0.14), Vector3(0, -0.07, 0.02)))  # cabo
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.0, -0.16)
	add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.4)
	_flash.light_energy = 4.0
	_flash.omni_range = 4.0
	_flash.visible = false
	_muzzle.add_child(_flash)
	_flash.add_child(sphere(0.03, Color(1.0, 0.85, 0.4), Vector3.ZERO, true))


func _spawn_tracer(to: Vector3) -> void:
	Weapon.spawn_tracer(self, _muzzle.global_position, to)
	# Nos outros jogadores, o rastro sai da cabeça do personagem (não há viewmodel lá).
	user.broadcast_fx(&"tracer", head.global_position + head.global_basis.x * 0.2, to)


func _spawn_impact(at: Vector3) -> void:
	var puff := sphere(0.05, Color(0.8, 0.75, 0.6), Vector3.ZERO, false)
	get_tree().current_scene.add_child(puff)
	puff.global_position = at
	var tw := puff.create_tween()
	tw.tween_property(puff, "scale", Vector3.ONE * 2.5, 0.25)
	tw.parallel().tween_property(puff, "transparency", 1.0, 0.25)
	tw.tween_callback(puff.queue_free)

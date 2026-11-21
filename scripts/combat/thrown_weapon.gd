class_name ThrownWeapon
extends Weapon
## Arma de arremesso (faca): segure para dar força (gasta um pouco de stamina) e solte
## para lançar uma do próprio slot. Mais força = mais dano e alcance. Silenciosa:
## combina com furtividade. Pode ser recuperada no chão (como a flecha).

const ARROW := preload("res://scripts/combat/arrow.gd")
const FULL := 0.9

var _pressing := false
var _time := 0.0


func handle_attack(held: bool, just_pressed: bool) -> void:
	if just_pressed and not _pressing and cooldown <= 0.0:
		if user.inventory.count_of(str(data.id)) <= 0:
			return
		_pressing = true
		_time = 0.0
	if not _pressing:
		return
	if held:
		var dt := get_process_delta_time()
		_time = minf(_time + dt, FULL)
		var stamina: StatPool = user.get(&"stamina")
		if stamina and _time < FULL:
			stamina.drain(stat("stamina_cost", 6.0) * dt)
		hud_changed.emit()
	else:
		_throw()


func _throw() -> void:
	_pressing = false
	var power := clampf(_time / FULL, 0.0, 1.0)
	_time = 0.0
	if not user.inventory.remove_item(str(data.id), 1):
		return
	cooldown = stat("attack_time", 0.45)
	var aim_point: Vector3 = aim_ray(60.0).position
	var from: Vector3 = user.shot_origin(aim_point)
	var direction := (aim_point - from).normalized()
	var speed := lerpf(14.0, stat("throw_speed", 30.0), power)
	var knife: Node3D = ARROW.new()
	knife.damage = stat("damage", 30.0) * lerpf(0.6, 2.0, power) * user.death_penalty.damage_factor()
	knife.velocity = direction * speed
	knife.caster = user
	knife.recover_chance = stat("recover_chance", 0.75)
	knife.item_id = str(data.id)
	knife.weapon_type = "thrown"
	knife.sneak_mult = float(data.get("sneak_mult", 1.0))
	get_tree().current_scene.add_child(knife)
	knife.global_position = from
	user.broadcast_fx(&"arrow", from, from + direction * speed)
	make_noise(stat("noise", 0.05))
	Sfx.play("swing", user.global_position + Vector3.UP * 1.4, -4.0)
	count_use()
	play_body_anim(&"Throw", stat("attack_time", 0.6), true)
	hud_changed.emit()


func channel_fraction() -> float:
	return clampf(_time / FULL, 0.0, 1.0) if _pressing else -1.0


func channel_label() -> String:
	return tr("Força do arremesso")


func hud_text() -> String:
	return tr("×%d · segure para mais força") % user.inventory.count_of(str(data.id))


func on_unequip() -> void:
	_pressing = false
	_time = 0.0


func _build_viewmodel() -> void:
	var model := model_viewmodel(0.22)
	if model:
		model.rotation = Vector3(deg_to_rad(-90), 0, 0)  # lâmina para a frente
		add_child(model)
		return
	add_child(Weapon.box(Vector3(0.02, 0.012, 0.16), Color(0.75, 0.75, 0.78), Vector3(0, 0, -0.08)))
	add_child(Weapon.box(Vector3(0.025, 0.02, 0.08), Color(0.25, 0.2, 0.15), Vector3(0, 0, 0.04)))

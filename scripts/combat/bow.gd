class_name Bow
extends Weapon
## Arco (GDD 5.2): a arma de longe do dia a dia. Segure o ataque para puxar a corda
## (até "draw_time" segundos); quanto mais puxada, mais dano e mais rápida a flecha.
## Soltar dispara. Cada disparo gasta uma flecha do inventário ("ammo" do item).
## Quase silencioso: bom para furtividade. Botão direito dá um leve zoom.

const ARROW := preload("res://scripts/combat/arrow.gd")
## Puxada mínima para disparar (soltar antes disso cancela).
const MIN_DRAW := 0.15

@export var aim_fov := 65.0

var draw := 0.0  # 0 a 1
var drawing := false

var _default_fov := 80.0
var _limb_top: Node3D
var _limb_bottom: Node3D
var _string: MeshInstance3D
var _nocked: MeshInstance3D


func setup(entry: Dictionary, owner_player: Player, cam: Camera3D, head_node: Node3D) -> void:
	super(entry, owner_player, cam, head_node)
	_default_fov = cam.fov


func _process(delta: float) -> void:
	super(delta)
	if not visible:
		return
	var zoom := Input.is_action_pressed("aim") or drawing
	var target_fov := lerpf(_default_fov, aim_fov, draw) if drawing else (aim_fov if zoom else _default_fov)
	camera.fov = lerpf(camera.fov, target_fov, minf(10.0 * delta, 1.0))
	_update_visual()


func handle_attack(held: bool, _just_pressed: bool) -> void:
	if held:
		if not drawing:
			if is_broken():
				warn_broken()
				return
			if cooldown > 0.0 or arrows() <= 0:
				return
			drawing = true
			draw = 0.0
		draw = minf(draw + get_process_delta_time() / stat("draw_time", 0.8), 1.0)
		hud_changed.emit()
	elif drawing:
		drawing = false
		if draw >= MIN_DRAW:
			_release()
		draw = 0.0
		hud_changed.emit()


func _release() -> void:
	if not user.inventory.remove_item(_arrow_id(), 1):
		return
	cooldown = 0.35
	var power := draw
	var from := head.global_position + (-head.global_basis.z) * 0.6 + head.global_basis.x * 0.1
	var aim_point: Vector3 = aim_ray(120.0).position
	var direction := (aim_point - from).normalized()
	var speed := lerpf(15.0, stat("arrow_speed", 45.0), power)

	var arrow: Node3D = ARROW.new()
	arrow.damage = stat("damage", 40.0) * lerpf(0.3, 1.0, power) * user.death_penalty.damage_factor()
	arrow.velocity = direction * speed
	arrow.caster = user
	arrow.recover_chance = stat("recover_chance", 0.6)
	arrow.item_id = _arrow_id()
	get_tree().current_scene.add_child(arrow)
	arrow.global_position = from

	user.broadcast_fx(&"arrow", from, from + direction * speed)
	make_noise(stat("noise", 0.08))
	Sfx.play("bow", user.global_position + Vector3.UP * 1.4)
	count_use()
	wear(1.0)
	kick(Vector3(0, 0, 0.04), Vector3(0, 0, 0), 0.15)


func channel_fraction() -> float:
	return draw if drawing else -1.0


func channel_label() -> String:
	return tr("Puxando o arco")


func on_unequip() -> void:
	drawing = false
	draw = 0.0
	camera.fov = _default_fov


func arrows() -> int:
	return user.inventory.count_of(_arrow_id()) if user and user.inventory else 0


func _arrow_id() -> String:
	return str(data.get("ammo", "arrow"))


func hud_text() -> String:
	if drawing:
		var bar := int(draw * 10.0)
		return tr("%s%s  %d flechas") % ["■".repeat(bar), "□".repeat(10 - bar), arrows()]
	return tr("%d flechas") % arrows() if arrows() > 0 else tr("sem flechas")


func _build_viewmodel() -> void:
	var wood := Color(0.45, 0.3, 0.16)
	# Duas hastes (de cima e de baixo) inclinadas para trás, formando o arco.
	_limb_top = Node3D.new()
	_limb_top.add_child(Weapon.box(Vector3(0.025, 0.36, 0.03), wood, Vector3(0, 0.18, 0)))
	add_child(_limb_top)
	_limb_bottom = Node3D.new()
	_limb_bottom.add_child(Weapon.box(Vector3(0.025, 0.36, 0.03), wood, Vector3(0, -0.18, 0)))
	add_child(_limb_bottom)
	add_child(Weapon.box(Vector3(0.035, 0.1, 0.04), Color(0.25, 0.17, 0.1)))  # empunhadura
	_string = Weapon.box(Vector3(0.004, 0.66, 0.004), Color(0.9, 0.88, 0.8))
	add_child(_string)
	_nocked = Weapon.box(Vector3(0.012, 0.012, 0.6), Color(0.6, 0.5, 0.35))
	add_child(_nocked)
	rotation = Vector3(0, deg_to_rad(8), deg_to_rad(-14))
	scale = Vector3.ONE * 0.55
	_update_visual()


## Curva as hastes, recua a corda e mostra a flecha conforme a puxada.
func _update_visual() -> void:
	if _limb_top == null:
		return
	var bend := 0.25 + draw * 0.35
	_limb_top.rotation.x = bend
	_limb_bottom.rotation.x = -bend
	var pull := 0.06 + draw * 0.28
	_string.position.z = pull
	_string.scale.y = lerpf(1.0, 0.8, draw)
	_nocked.visible = arrows() > 0
	_nocked.position.z = pull - 0.3
